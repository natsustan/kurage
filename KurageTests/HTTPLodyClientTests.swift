import Foundation
import Testing
@testable import Kurage

@MainActor
@Suite(.serialized)
struct HTTPLodyClientTests {
    @Test func deviceFlowStoresTokenAndRewritesHost() async throws {
        let store = MemoryAuthTokenStore()
        let log = AuthRequestLog()
        let polls = PollCount()
        log.install { request in
            switch request.url?.path {
            case "/api/auth/device/code":
                return (200, Data(deviceCodeJSON.utf8))
            case "/api/auth/device/token":
                polls.value += 1
                if polls.value == 1 {
                    return (200, Data(#"{"error":"authorization_pending"}"#.utf8))
                }
                return (200, Data(#"{"access_token":"session-token"}"#.utf8))
            case "/api/auth/get-session":
                return (200, Data(#"{"user":{"email":"ada@lody.ai"}}"#.utf8))
            default:
                return (404, Data())
            }
        }
        let client = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL)

        let authorization = try await client.beginDeviceAuthorization()
        #expect(authorization.userCode == "ABCD-EFGH")
        #expect(authorization.verificationURL.host == "lody.ai")
        let codeRequest = try JSONDecoder().decode(DeviceCodeProbe.self, from: try #require(log.bodies.first))
        #expect(codeRequest.clientID == "lody-cli")

        try await client.finishDeviceAuthorization(authorization)

        #expect(client.account == Account(email: "ada@lody.ai"))
        #expect(store.read() == "session-token")
        #expect(polls.value == 2)
    }

    @Test func deniedDeviceFlowThrows() async throws {
        let log = AuthRequestLog()
        log.install { request in
            switch request.url?.path {
            case "/api/auth/device/code":
                return (200, Data(deviceCodeJSON.utf8))
            case "/api/auth/device/token":
                return (200, Data(#"{"error":"access_denied"}"#.utf8))
            default:
                return (404, Data())
            }
        }
        let client = HTTPLodyClient(session: log.session, tokenStore: MemoryAuthTokenStore(), baseURL: log.baseURL)
        let authorization = try await client.beginDeviceAuthorization()
        await #expect(throws: LodyClientError.accessDenied) {
            try await client.finishDeviceAuthorization(authorization)
        }
    }

    @Test func cancellingInFlightRequestThrowsCancellation() async throws {
        let (started, continuation) = AsyncStream<Void>.makeStream()
        HangingAuthURLProtocol.onStart = { _ = continuation.yield(()) }
        defer { HangingAuthURLProtocol.onStart = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingAuthURLProtocol.self]
        let client = HTTPLodyClient(
            session: URLSession(configuration: configuration),
            tokenStore: MemoryAuthTokenStore(),
            baseURL: URL(string: "https://backend.lody.ai")!
        )

        let authorization = DeviceAuthorization(
            userCode: "ABCD-EFGH",
            verificationURL: URL(string: "https://lody.ai/device")!,
            deviceCode: "device-1",
            expiresIn: 30,
            interval: 0.01
        )
        let task = Task { try await client.finishDeviceAuthorization(authorization) }
        var iterator = started.makeAsyncIterator()
        await iterator.next()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func cancellingAccountLoadDoesNotPersistToken() async throws {
        let store = MemoryAuthTokenStore()
        let (started, continuation) = AsyncStream<Void>.makeStream()
        DeferredAuthURLProtocol.onStart = { request in
            switch request.request.url?.path {
            case "/api/auth/device/token":
                request.respond(status: 200, data: Data(#"{"access_token":"new-token"}"#.utf8))
            case "/api/auth/get-session":
                _ = continuation.yield(())
            default:
                request.respond(status: 404, data: Data())
            }
        }
        defer { DeferredAuthURLProtocol.onStart = nil }

        let client = HTTPLodyClient(session: deferredSession(), tokenStore: store)
        let task = Task { try await client.finishDeviceAuthorization(testAuthorization) }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(store.read() == nil)
        #expect(client.account == nil)
    }

    @Test(arguments: [200, 401])
    func staleRestorationCannotReplaceNewSignIn(status: Int) async throws {
        let store = MemoryAuthTokenStore()
        #expect(store.write("old-token"))
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let oldRequest = PendingAuthRequest()
        DeferredAuthURLProtocol.onStart = { request in
            switch request.request.url?.path {
            case "/api/auth/device/code":
                request.respond(status: 200, data: Data(deviceCodeJSON.utf8))
            case "/api/auth/device/token":
                request.respond(status: 200, data: Data(#"{"access_token":"new-token"}"#.utf8))
            case "/api/auth/get-session":
                if request.request.value(forHTTPHeaderField: "Authorization") == "Bearer old-token" {
                    oldRequest.capture(request)
                    _ = continuation.yield(())
                } else {
                    request.respond(status: 200, data: Data(#"{"user":{"email":"new@lody.ai"}}"#.utf8))
                }
            case "/api/auth/organization/list":
                request.respond(status: 200, data: Data("[]".utf8))
            default:
                request.respond(status: 404, data: Data())
            }
        }
        defer { DeferredAuthURLProtocol.onStart = nil }

        let client = HTTPLodyClient(session: deferredSession(), tokenStore: store)
        let model = AppModel(client: client)
        let restoration = Task { await model.adoptExistingAccount() }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()

        model.connect(open: { _ in })
        for _ in 0..<100 {
            if model.account == Account(email: "new@lody.ai") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.account == Account(email: "new@lody.ai"))
        #expect(store.read() == "new-token")

        let oldResponse = status == 200
            ? Data(#"{"user":{"email":"old@lody.ai"}}"#.utf8)
            : Data()
        oldRequest.respond(status: status, data: oldResponse)
        await restoration.value

        #expect(model.account == Account(email: "new@lody.ai"))
        #expect(client.account == Account(email: "new@lody.ai"))
        #expect(store.read() == "new-token")
    }

    @Test(arguments: [200, 500])
    func staleWorkspaceRefreshCannotChangeNewAccount(status: Int) async throws {
        let store = MemoryAuthTokenStore()
        #expect(store.write("old-token"))
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let oldWorkspaceRequest = PendingAuthRequest()
        DeferredAuthURLProtocol.onStart = { request in
            switch request.request.url?.path {
            case "/api/auth/get-session":
                let email = request.request.value(forHTTPHeaderField: "Authorization") == "Bearer old-token"
                    ? "old@lody.ai" : "new@lody.ai"
                request.respond(status: 200, data: Data(#"{"user":{"email":"\#(email)"}}"#.utf8))
            case "/api/auth/organization/list":
                if request.request.value(forHTTPHeaderField: "Authorization") == "Bearer old-token" {
                    oldWorkspaceRequest.capture(request)
                    _ = continuation.yield(())
                } else {
                    request.respond(status: 200, data: Data(#"[{"id":"new","name":"New","slug":"new"}]"#.utf8))
                }
            case "/api/auth/device/code":
                request.respond(status: 200, data: Data(deviceCodeJSON.utf8))
            case "/api/auth/device/token":
                request.respond(status: 200, data: Data(#"{"access_token":"new-token"}"#.utf8))
            default:
                request.respond(status: 404, data: Data())
            }
        }
        defer { DeferredAuthURLProtocol.onStart = nil }

        let client = HTTPLodyClient(session: deferredSession(), tokenStore: store)
        let model = AppModel(client: client)
        let restoration = Task { await model.adoptExistingAccount() }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        #expect(model.account == Account(email: "old@lody.ai"))

        model.signOut()
        model.connect(open: { _ in })
        let newWorkspaces = [WorkspaceSummary(id: "new", name: "New", slug: "new")]
        for _ in 0..<100 {
            if model.workspaces == newWorkspaces { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.account == Account(email: "new@lody.ai"))
        #expect(model.workspaces == newWorkspaces)

        let oldResponse = status == 200
            ? Data(#"[{"id":"old","name":"Old","slug":"old"}]"#.utf8)
            : Data()
        oldWorkspaceRequest.respond(status: status, data: oldResponse)
        await restoration.value

        #expect(model.account == Account(email: "new@lody.ai"))
        #expect(model.workspaces == newWorkspaces)
    }

    @Test func restoreSessionReadsBearerSession() async {
        let store = MemoryAuthTokenStore()
        #expect(store.write("session-token"))
        let log = AuthRequestLog()
        log.install { request in
            let token = request.value(forHTTPHeaderField: "Authorization")
            if token == "Bearer session-token" {
                return (200, Data(#"{"user":{"email":"ada@lody.ai"},"session":{"token":"session-token"}}"#.utf8))
            }
            return (401, Data(#"{"code":"UNAUTHORIZED"}"#.utf8))
        }
        let client = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL)

        let account = await client.restoreSession()
        #expect(account == Account(email: "ada@lody.ai"))
    }

    @Test func missingSessionClearsToken() async {
        let store = MemoryAuthTokenStore()
        #expect(store.write("stale"))
        let log = AuthRequestLog()
        log.install { _ in (200, Data("null".utf8)) }
        let client = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL)

        let account = await client.restoreSession()
        #expect(account == nil)
        #expect(store.read() == nil)
    }

    @Test func workspaceListDecodesOrganizations() async throws {
        let store = MemoryAuthTokenStore()
        let log = AuthRequestLog()
        log.install { request in
            switch request.url?.path {
            case "/api/auth/device/code":
                return (200, Data(deviceCodeJSON.utf8))
            case "/api/auth/device/token":
                return (200, Data(#"{"access_token":"session-token"}"#.utf8))
            case "/api/auth/get-session":
                return (200, Data(#"{"user":{"email":"ada@lody.ai"}}"#.utf8))
            case "/api/auth/organization/list":
                return (200, Data(#"[{"id":"org-1","name":"Spike","slug":"spike"}]"#.utf8))
            default:
                return (404, Data())
            }
        }
        let client = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL)
        let authorization = try await client.beginDeviceAuthorization()
        try await client.finishDeviceAuthorization(authorization)

        let workspaces = try await client.workspaces()
        #expect(workspaces == [WorkspaceSummary(id: "org-1", name: "Spike", slug: "spike")])
    }

    @Test func sessionsAreNotConnectedYet() async throws {
        let log = AuthRequestLog()
        log.install { request in
            switch request.url?.path {
            case "/api/auth/device/code":
                return (200, Data(deviceCodeJSON.utf8))
            case "/api/auth/device/token":
                return (200, Data(#"{"access_token":"session-token"}"#.utf8))
            case "/api/auth/get-session":
                return (200, Data(#"{"user":{"email":"ada@lody.ai"}}"#.utf8))
            default:
                return (404, Data())
            }
        }
        let client = HTTPLodyClient(
            session: log.session,
            tokenStore: MemoryAuthTokenStore(),
            baseURL: log.baseURL
        )
        let authorization = try await client.beginDeviceAuthorization()
        try await client.finishDeviceAuthorization(authorization)
        await #expect(throws: LodyClientError.notConnected) {
            try await client.sessions()
        }
    }
}

private let deviceCodeJSON = """
{"device_code":"device-1","user_code":"ABCD-EFGH","verification_uri_complete":"https://backend.lody.ai/device?user_code=ABCD-EFGH","expires_in":30,"interval":0.01}
"""

private let testAuthorization = DeviceAuthorization(
    userCode: "ABCD-EFGH",
    verificationURL: URL(string: "https://lody.ai/device")!,
    deviceCode: "device-1",
    expiresIn: 30,
    interval: 0.01
)

private func deferredSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DeferredAuthURLProtocol.self]
    return URLSession(configuration: configuration)
}

private struct DeviceCodeProbe: Decodable {
    var clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private final class PollCount: @unchecked Sendable {
    var value = 0
}

@MainActor
private final class MemoryAuthTokenStore: AuthTokenStore {
    private var token: String?

    func read() -> String? { token }

    func write(_ token: String) -> Bool {
        self.token = token
        return true
    }

    func delete() {
        token = nil
    }
}

private final class AuthRequestLog: @unchecked Sendable {
    let baseURL = URL(string: "https://backend.lody.ai")!
    private let lock = NSLock()
    private var recorded: [Data] = []

    var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    var bodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func install(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        AuthURLProtocol.handler = { [weak self] request in
            if let body = Self.body(of: request) {
                self?.lock.lock()
                self?.recorded.append(body)
                self?.lock.unlock()
            }
            return handler(request)
        }
    }

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class AuthURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://backend.lody.ai")!,
            statusCode: result.0,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class HangingAuthURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var onStart: (@Sendable () -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() { Self.onStart?() }

    override func stopLoading() {}
}

private final class DeferredAuthURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var onStart: (@Sendable (DeferredAuthURLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() { Self.onStart?(self) }

    override func stopLoading() {}

    func respond(status: Int, data: Data) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://backend.lody.ai")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class PendingAuthRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request: DeferredAuthURLProtocol?

    func capture(_ request: DeferredAuthURLProtocol) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func respond(status: Int, data: Data) {
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.respond(status: status, data: data)
    }
}
