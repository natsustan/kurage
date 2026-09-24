import Foundation

/// Device authorization and read-only workspace session metadata from Lody.
@MainActor
final class HTTPLodyClient: LodyClient {
    let supportsConversations = true

    private let session: URLSession
    private let tokenStore: any AuthTokenStore
    private let baseURL: URL
    private(set) var account: Account?
    private var authenticationGeneration = 0
    private var sessionBridge: SessionSyncBridge?
    private var streamsAccessCache: [WorkspaceSummary.ID: (access: StreamsAccess, expiresAt: Date, accountToken: String)] = [:]

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
        authenticationGeneration += 1
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
        authenticationGeneration += 1
        var interval = authorization.interval
        var lastPollFailedToConnect = false
        let deadline = Date().addingTimeInterval(authorization.expiresIn)
        while Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            try await Task.sleep(for: .seconds(min(interval, remaining)))
            try Task.checkCancellation()
            if Date() >= deadline { break }

            let status: Int
            let data: Data
            do {
                (status, data) = try await perform(
                    path: "api/auth/device/token",
                    method: "POST",
                    json: DeviceTokenRequest(
                        clientID: LodyEndpoints.deviceClientID,
                        deviceCode: authorization.deviceCode
                    ),
                    token: nil,
                    acceptAnyStatus: true
                )
            } catch LodyClientError.unreachable {
                lastPollFailedToConnect = true
                continue
            }
            if status >= 500 {
                lastPollFailedToConnect = true
                continue
            }
            lastPollFailedToConnect = false
            let body = try JSONDecoder().decode(DeviceTokenBody.self, from: data)
            if let token = body.accessToken, !token.isEmpty {
                let loadedAccount = try await loadAccount(token: token)
                try Task.checkCancellation()
                guard tokenStore.write(token) else { throw LodyClientError.signInFailed }
                account = loadedAccount
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
        throw lastPollFailedToConnect ? LodyClientError.unreachable : LodyClientError.codeExpired
    }

    func restoreSession() async -> Account? {
        let generation = authenticationGeneration
        guard let token = tokenStore.read(), !token.isEmpty else {
            account = nil
            return nil
        }
        do {
            let data = try await send(path: "api/auth/get-session", method: "GET", json: Optional<String>.none, token: token)
            guard generation == authenticationGeneration, tokenStore.read() == token else { return nil }
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
            guard generation == authenticationGeneration, tokenStore.read() == token else { return nil }
            tokenStore.delete()
            account = nil
            return nil
        } catch {
            return generation == authenticationGeneration ? account : nil
        }
    }

    func signOut() {
        authenticationGeneration += 1
        tokenStore.delete()
        account = nil
        sessionBridge?.close()
        sessionBridge = nil
        streamsAccessCache = [:]
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

    /// Exchanges the account credential for a short-lived token scoped to one workspace.
    /// The session transport will consume this token; it is never persisted with the login token.
    func streamsAccess(workspaceID: WorkspaceSummary.ID) async throws -> StreamsAccess {
        guard account != nil, let accountToken = tokenStore.read() else {
            throw LodyClientError.signedOut
        }
        if let cached = streamsAccessCache[workspaceID],
           cached.accountToken == accountToken,
           cached.expiresAt > Date() {
            return cached.access
        }
        let generation = authenticationGeneration
        let requestedAt = Date()
        let data = try await send(
            path: "api/loro-streams/token",
            method: "POST",
            json: StreamsTokenRequest(workspaceId: workspaceID),
            token: accountToken
        )
        guard generation == authenticationGeneration, tokenStore.read() == accountToken else {
            throw LodyClientError.signedOut
        }
        let response = try JSONDecoder().decode(StreamsTokenResponse.self, from: data)
        guard !response.token.isEmpty, response.expiresIn > 0 else {
            throw LodyClientError.notConnected
        }
        let gatewayBaseURL: URL?
        if let rawURL = response.gatewayBaseUrl {
            guard let url = URL(string: rawURL), url.scheme == "https", url.host != nil else {
                throw LodyClientError.notConnected
            }
            gatewayBaseURL = url
        } else {
            gatewayBaseURL = nil
        }
        let access = StreamsAccess(
            token: response.token,
            expiresIn: response.expiresIn,
            gatewayBaseURL: gatewayBaseURL,
            shardHostSuffix: response.shardHostSuffix
        )
        streamsAccessCache[workspaceID] = (
            access,
            requestedAt.addingTimeInterval(max(0, response.expiresIn - min(30, response.expiresIn * 0.1))),
            accountToken
        )
        return access
    }

    func sessions(workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary] {
        try Task.checkCancellation()
        let generation = authenticationGeneration
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        let sessions = try await bridge.sessions(workspaceID: workspaceID, access: access)
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil else {
            throw LodyClientError.signedOut
        }
        return sessions
    }

    func conversation(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> Conversation {
        try Task.checkCancellation()
        let generation = authenticationGeneration
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        let conversation = try await bridge.conversation(
            sessionID: sessionID,
            workspaceID: workspaceID,
            access: access
        )
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil else {
            throw LodyClientError.signedOut
        }
        return conversation
    }

    private func makeSessionBridge() -> SessionSyncBridge {
        SessionSyncBridge { [weak self] workspaceID, refresh in
            guard let self else { throw LodyClientError.signedOut }
            if refresh { streamsAccessCache.removeValue(forKey: workspaceID) }
            return try await streamsAccess(workspaceID: workspaceID)
        }
    }

    func observeConversation(sessionID: String, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error> {
        let generation = authenticationGeneration
        let access = try await streamsAccess(workspaceID: workspaceID)
        try Task.checkCancellation()
        guard generation == authenticationGeneration, account != nil else { throw LodyClientError.signedOut }
        let bridge = sessionBridge ?? makeSessionBridge()
        sessionBridge = bridge
        return bridge.observeConversation(sessionID: sessionID, workspaceID: workspaceID, access: access)
    }

    func send(_ text: String, sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        throw LodyClientError.notConnected
    }

    func respond(
        _ decision: PermissionDecision,
        requestID: PermissionPrompt.ID,
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
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
        if status >= 500 {
            #if DEBUG
            print("Kurage Lody HTTP failure: \(method) /\(path) status=\(status)")
            #endif
        }
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
            if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            #if DEBUG
            let networkError = error as NSError
            print("Kurage Lody transport failure: \(method) /\(path) domain=\(networkError.domain) code=\(networkError.code)")
            #endif
            throw LodyClientError.unreachable
        }
        try Task.checkCancellation()
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

struct StreamsAccess: Equatable, Sendable {
    let token: String
    let expiresIn: TimeInterval
    let gatewayBaseURL: URL?
    let shardHostSuffix: String?
}

private struct StreamsTokenRequest: Encodable {
    let workspaceId: String
}

private struct StreamsTokenResponse: Decodable {
    let token: String
    let expiresIn: TimeInterval
    let gatewayBaseUrl: String?
    let shardHostSuffix: String?
}
