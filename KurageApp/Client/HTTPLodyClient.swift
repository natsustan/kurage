import Foundation

/// Device authorization against Lody better-auth. Session documents are not synced yet.
@MainActor
final class HTTPLodyClient: LodyClient {
    private let session: URLSession
    private let tokenStore: any AuthTokenStore
    private let baseURL: URL
    private(set) var account: Account?

    init(
        session: URLSession = .shared,
        tokenStore: any AuthTokenStore = KeychainAuthTokenStore(),
        baseURL: URL = LodyEndpoints.authBaseURL
    ) {
        self.session = session
        self.tokenStore = tokenStore
        self.baseURL = baseURL
    }

    func beginDeviceAuthorization() async throws -> DeviceAuthorization {
        let (_, data) = try await perform(
            path: "api/auth/device/code",
            method: "POST",
            json: DeviceCodeRequest(clientID: LodyEndpoints.deviceClientID),
            token: nil,
            acceptAnyStatus: false
        )
        let body = try JSONDecoder().decode(DeviceCodeBody.self, from: data)
        guard body.expiresIn > 0, body.interval > 0 else { throw LodyClientError.signInFailed }
        return DeviceAuthorization(
            userCode: body.userCode,
            verificationURL: try Self.authorizationPage(body.verificationURIComplete),
            deviceCode: body.deviceCode,
            expiresIn: body.expiresIn,
            interval: body.interval
        )
    }

    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws {
        var interval = authorization.interval
        let deadline = Date().addingTimeInterval(authorization.expiresIn)
        while Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            try await Task.sleep(for: .seconds(min(interval, remaining)))
            try Task.checkCancellation()
            if Date() >= deadline { break }

            let (_, data) = try await perform(
                path: "api/auth/device/token",
                method: "POST",
                json: DeviceTokenRequest(
                    clientID: LodyEndpoints.deviceClientID,
                    deviceCode: authorization.deviceCode
                ),
                token: nil,
                acceptAnyStatus: true
            )
            let body = try JSONDecoder().decode(DeviceTokenBody.self, from: data)
            if let token = body.accessToken, !token.isEmpty {
                guard tokenStore.write(token) else { throw LodyClientError.signInFailed }
                account = try await loadAccount(token: token)
                return
            }
            switch body.error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
                continue
            case "access_denied":
                throw LodyClientError.accessDenied
            case "expired_token":
                throw LodyClientError.codeExpired
            default:
                throw LodyClientError.signInFailed
            }
        }
        throw LodyClientError.codeExpired
    }

    func restoreSession() async -> Account? {
        guard let token = tokenStore.read(), !token.isEmpty else {
            account = nil
            return nil
        }
        do {
            let data = try await send(path: "api/auth/get-session", method: "GET", json: Optional<String>.none, token: token)
            if data == Data("null".utf8) {
                tokenStore.delete()
                account = nil
                return nil
            }
            let parsed = try JSONDecoder().decode(SessionResponse.self, from: data)
            guard let email = parsed.user?.email, !email.isEmpty else {
                tokenStore.delete()
                account = nil
                return nil
            }
            let restored = Account(email: email)
            account = restored
            return restored
        } catch LodyClientError.signedOut {
            tokenStore.delete()
            account = nil
            return nil
        } catch {
            return account
        }
    }

    func signOut() {
        tokenStore.delete()
        account = nil
    }

    func workspaces() async throws -> [WorkspaceSummary] {
        guard account != nil, let token = tokenStore.read() else { throw LodyClientError.signedOut }
        let data = try await send(
            path: "api/auth/organization/list",
            method: "GET",
            json: Optional<String>.none,
            token: token
        )
        let organizations = try decodeOrganizations(data)
        return organizations.map {
            WorkspaceSummary(id: $0.id, name: $0.name, slug: $0.slug)
        }
    }

    func sessions() async throws -> [SessionSummary] {
        throw LodyClientError.notConnected
    }

    func conversation(sessionID: SessionSummary.ID) async throws -> Conversation {
        throw LodyClientError.notConnected
    }

    func send(_ text: String, sessionID: SessionSummary.ID) async throws {
        throw LodyClientError.notConnected
    }

    func respond(
        _ decision: PermissionDecision,
        requestID: PermissionPrompt.ID,
        sessionID: SessionSummary.ID
    ) async throws {
        throw LodyClientError.notConnected
    }

    private func url(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/" + path
        return components?.url ?? baseURL
    }

    private func loadAccount(token: String) async throws -> Account {
        let data = try await send(path: "api/auth/get-session", method: "GET", json: Optional<String>.none, token: token)
        if data == Data("null".utf8) { throw LodyClientError.signedOut }
        let session = try JSONDecoder().decode(SessionResponse.self, from: data)
        guard let email = session.user?.email, !email.isEmpty else { throw LodyClientError.signInFailed }
        return Account(email: email)
    }

    private func perform(
        path: String,
        method: String,
        json: (some Encodable)?,
        token: String?,
        acceptAnyStatus: Bool
    ) async throws -> (Int, Data) {
        let (status, data) = try await request(path: path, method: method, json: json, token: token)
        if acceptAnyStatus || (200..<300).contains(status) {
            return (status, data)
        }
        throw errorCode(status: status)
    }

    private func send<Body: Encodable>(
        path: String,
        method: String,
        json: Body?,
        token: String?
    ) async throws -> Data {
        let (_, data) = try await perform(
            path: path,
            method: method,
            json: json,
            token: token,
            acceptAnyStatus: false
        )
        return data
    }

    private func request<Body: Encodable>(
        path: String,
        method: String,
        json: Body?,
        token: String?
    ) async throws -> (Int, Data) {
        var request = URLRequest(url: url(path: path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(LodyEndpoints.webOrigin, forHTTPHeaderField: "Origin")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(json)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LodyClientError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw LodyClientError.signInFailed }
        return (http.statusCode, data)
    }

    private func errorCode(status: Int) -> LodyClientError {
        if status == 401 {
            return .signedOut
        }
        if status >= 500 {
            return .unreachable
        }
        return .signInFailed
    }

    private static func authorizationPage(_ raw: String) throws -> URL {
        guard var components = URLComponents(string: raw),
              components.scheme == "https",
              let host = components.host?.lowercased(),
              host == "lody.ai" || host == "backend.lody.ai",
              components.user == nil,
              components.password == nil
        else {
            throw LodyClientError.signInFailed
        }
        components.host = "lody.ai"
        guard let url = components.url else { throw LodyClientError.signInFailed }
        return url
    }

    private func decodeOrganizations(_ data: Data) throws -> [OrganizationBody] {
        if let list = try? JSONDecoder().decode([OrganizationBody].self, from: data) {
            return list
        }
        if let wrapped = try? JSONDecoder().decode(OrganizationListBody.self, from: data) {
            return wrapped.organizations ?? wrapped.data ?? []
        }
        throw LodyClientError.signInFailed
    }
}

private struct DeviceCodeRequest: Encodable {
    var clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct DeviceCodeBody: Decodable {
    var deviceCode: String
    var userCode: String
    var verificationURIComplete: String
    var expiresIn: TimeInterval
    var interval: TimeInterval

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct DeviceTokenRequest: Encodable {
    var clientID: String
    var deviceCode: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case deviceCode = "device_code"
        case grantType = "grant_type"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(deviceCode, forKey: .deviceCode)
        try container.encode("urn:ietf:params:oauth:grant-type:device_code", forKey: .grantType)
    }
}

private struct DeviceTokenBody: Decodable {
    var accessToken: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
    }
}

private struct SessionResponse: Decodable {
    var user: AuthUserBody?
}

private struct AuthUserBody: Decodable {
    var email: String?
}

private struct OrganizationBody: Decodable {
    var id: String
    var name: String
    var slug: String
}

private struct OrganizationListBody: Decodable {
    var organizations: [OrganizationBody]?
    var data: [OrganizationBody]?
}
