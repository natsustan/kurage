import Foundation
import Testing
import WebKit
@testable import Kurage

@MainActor
@Suite(.serialized)
struct HTTPLodyClientTests {
    @Test func realConversationsNeedAnAccountIDToSendText() {
        let model = AppModel(client: HTTPLodyClient(tokenStore: MemoryAuthTokenStore()))

        #expect(model.supportsConversations)
        #expect(!model.supportsTextSending)
        #expect(!model.supportsPermissionResponses)
    }

    @Test func restoredAccountKeepsUserIDForAuthoredTurns() async throws {
        let store = MemoryAuthTokenStore()
        _ = store.write("account-token")
        let log = AuthRequestLog()
        log.install { _ in (200, Data(#"{"user":{"id":"current-user","email":"ada@lody.ai"}}"#.utf8)) }
        let client = HTTPLodyClient(session: log.session, tokenStore: store,
                                    baseURL: log.baseURL, cacheURL: Self.isolatedCacheURL)
        #expect(await client.restoreSession()?.id == "current-user")
        #expect(client.supportsTextSending)
    }

    @Test func changedTextCannotAbandonAnUnconfirmedSend() async throws {
        let store = MemoryAuthTokenStore()
        _ = store.write("account-token")
        let log = AuthRequestLog()
        log.install { _ in (200, Data(#"{"user":{"id":"current-user","email":"ada@lody.ai"}}"#.utf8)) }
        let client = HTTPLodyClient(session: log.session, tokenStore: store,
                                    baseURL: log.baseURL, cacheURL: Self.isolatedCacheURL)
        _ = try #require(await client.restoreSession())
        log.install { _ in (503, Data()) }

        await #expect(throws: LodyClientError.unreachable) {
            try await client.send("First", sessionID: "chat", workspaceID: "work")
        }
        await #expect(throws: LodyClientError.previousSendPending("First")) {
            try await client.send("Edited", sessionID: "chat", workspaceID: "work")
        }
    }

    @Test func changedTextCannotAbandonAnUnconfirmedSessionStart() async throws {
        let store = MemoryAuthTokenStore()
        _ = store.write("account-token")
        let log = AuthRequestLog()
        log.install { _ in (200, Data(#"{"user":{"id":"current-user","email":"ada@lody.ai"}}"#.utf8)) }
        let client = HTTPLodyClient(session: log.session, tokenStore: store,
                                    baseURL: log.baseURL, cacheURL: Self.isolatedCacheURL)
        _ = try #require(await client.restoreSession())
        #expect(client.supportsSessionCreation)
        log.install { _ in (503, Data()) }

        await #expect(throws: LodyClientError.unreachable) {
            try await client.startSession("First", agentConfigID: nil, selections: [], projectID: "local:mac:p",
                                          templateSessionID: "t", workspaceID: "work")
        }
        await #expect(throws: LodyClientError.previousSendPending("First")) {
            try await client.startSession("Edited", agentConfigID: nil, selections: [], projectID: "local:mac:p",
                                          templateSessionID: "t", workspaceID: "work")
        }
        // Another project is independent.
        await #expect(throws: LodyClientError.unreachable) {
            try await client.startSession("Edited", agentConfigID: nil, selections: [], projectID: "local:mac:q",
                                          templateSessionID: "t", workspaceID: "work")
        }
        client.signOut()
        #expect(!client.supportsSessionCreation)
    }

    private static var isolatedCacheURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func cachedSessionSurvivesRelaunchAndOfflineRefresh() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MemoryAuthTokenStore()
        _ = store.write("persistent-token")
        let log = AuthRequestLog()
        log.install { _ in (200, Data(#"{"user":{"email":"ada@lody.ai"}}"#.utf8)) }
        let client = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL, cacheURL: url)
        let account = try #require(await client.restoreSession())
        let row = SessionSummary(id: "chat", title: "Saved chat", agentName: "Agent", activity: .idle, preview: "Hello")
        let cache = SessionCache(account: account,
                                 workspaces: [WorkspaceSummary(id: "work", name: "Work", slug: "work")],
                                 selectedWorkspaceID: "work", sessionsByWorkspace: ["work": [row]])
        client.saveSessionCache(cache)
        await client.flushSessionCache()

        let relaunched = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL, cacheURL: url)
        let model = AppModel(client: relaunched)
        #expect(model.isSignedIn)
        #expect(model.selectedWorkspaceID == "work")
        #expect(model.sessions == [row])
        log.install { _ in (503, Data()) }
        await model.adoptExistingAccount()
        #expect(model.isSignedIn)
        #expect(model.sessions == [row])
        #expect(model.workspaces == cache.workspaces)

        log.install { _ in (401, Data()) }
        await model.adoptExistingAccount()
        #expect(!model.isSignedIn)
        #expect(model.sessions.isEmpty)
        #expect(store.read() == nil)
        await client.flushSessionCache()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func cacheCannotRestoreWithDifferentCredential() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MemoryAuthTokenStore()
        _ = store.write("first-token")
        let log = AuthRequestLog()
        log.install { _ in (200, Data(#"{"user":{"email":"ada@lody.ai"}}"#.utf8)) }
        let client = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL, cacheURL: url)
        _ = await client.restoreSession()
        #expect(client.cachedSession != nil)
        await client.flushSessionCache()
        _ = store.write("different-token")
        let other = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL, cacheURL: url)
        #expect(other.account == nil)
        #expect(other.cachedSession == nil)
        client.signOut()
        await client.flushSessionCache()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func queuedWritesCannotRecreateCacheAfterSignOut() async throws {
        let url = Self.isolatedCacheURL
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MemoryAuthTokenStore()
        _ = store.write("old-token")
        let log = AuthRequestLog()
        log.install { _ in (200, Data(#"{"user":{"email":"ada@lody.ai"}}"#.utf8)) }
        let client = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL, cacheURL: url)
        let account = try #require(await client.restoreSession())
        for index in 0..<20 {
            client.saveSessionCache(SessionCache(account: account, selectedWorkspaceID: "work-\(index)"))
        }
        client.signOut()
        await client.flushSessionCache()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(client.cachedSession == nil)

        _ = store.write("new-token")
        _ = await client.restoreSession()
        let latest = SessionCache(account: account, selectedWorkspaceID: "new-work")
        client.saveSessionCache(latest)
        await client.flushSessionCache()
        let relaunched = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL, cacheURL: url)
        #expect(relaunched.cachedSession == latest)
    }

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
        let client = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL, cacheURL: Self.isolatedCacheURL)

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
        let client = HTTPLodyClient(session: log.session, tokenStore: MemoryAuthTokenStore(), baseURL: log.baseURL, cacheURL: Self.isolatedCacheURL)
        let authorization = try await client.beginDeviceAuthorization()
        await #expect(throws: LodyClientError.accessDenied) {
            try await client.finishDeviceAuthorization(authorization)
        }
    }

    @Test func deviceFlowRetriesDroppedTokenConnection() async throws {
        let store = MemoryAuthTokenStore()
        let polls = PollCount()
        DeferredAuthURLProtocol.onStart = { request in
            switch request.request.url?.path {
            case "/api/auth/device/token":
                polls.value += 1
                if polls.value == 1 {
                    request.fail(URLError(.networkConnectionLost))
                } else {
                    request.respond(status: 200, data: Data(#"{"access_token":"session-token"}"#.utf8))
                }
            case "/api/auth/get-session":
                request.respond(status: 200, data: Data(#"{"user":{"email":"ada@lody.ai"}}"#.utf8))
            default:
                request.respond(status: 404, data: Data())
            }
        }
        defer { DeferredAuthURLProtocol.onStart = nil }

        let client = HTTPLodyClient(session: deferredSession(), tokenStore: store, cacheURL: Self.isolatedCacheURL)
        try await client.finishDeviceAuthorization(testAuthorization)

        #expect(polls.value == 2)
        #expect(client.account == Account(email: "ada@lody.ai"))
        #expect(store.read() == "session-token")
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
            baseURL: URL(string: "https://backend.lody.ai")!,
            cacheURL: Self.isolatedCacheURL
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

        let client = HTTPLodyClient(session: deferredSession(), tokenStore: store, cacheURL: Self.isolatedCacheURL)
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

        let client = HTTPLodyClient(session: deferredSession(), tokenStore: store, cacheURL: Self.isolatedCacheURL)
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

        let client = HTTPLodyClient(session: deferredSession(), tokenStore: store, cacheURL: Self.isolatedCacheURL)
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

    @Test func signOutCancelsInFlightSignInRefresh() async throws {
        let store = MemoryAuthTokenStore()
        let tokens = AuthTokenSequence()
        let (started, continuation) = AsyncStream<Void>.makeStream()
        DeferredAuthURLProtocol.onStart = { request in
            switch request.request.url?.path {
            case "/api/auth/device/code":
                request.respond(status: 200, data: Data(deviceCodeJSON.utf8))
            case "/api/auth/device/token":
                let token = tokens.next()
                request.respond(status: 200, data: Data(#"{"access_token":"\#(token)"}"#.utf8))
            case "/api/auth/get-session":
                let email = request.request.value(forHTTPHeaderField: "Authorization") == "Bearer old-token"
                    ? "old@lody.ai" : "new@lody.ai"
                request.respond(status: 200, data: Data(#"{"user":{"email":"\#(email)"}}"#.utf8))
            case "/api/auth/organization/list":
                if request.request.value(forHTTPHeaderField: "Authorization") == "Bearer old-token" {
                    _ = continuation.yield(())
                } else {
                    request.respond(status: 200, data: Data(#"[{"id":"new","name":"New","slug":"new"}]"#.utf8))
                }
            default:
                request.respond(status: 404, data: Data())
            }
        }
        defer { DeferredAuthURLProtocol.onStart = nil }

        let model = AppModel(client: HTTPLodyClient(session: deferredSession(), tokenStore: store, cacheURL: Self.isolatedCacheURL))
        model.connect(open: { _ in })
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        #expect(model.account == Account(email: "old@lody.ai"))
        #expect(model.isSigningIn)

        model.signOut()
        for _ in 0..<100 {
            if !model.isSigningIn { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.isSigningIn)
        #expect(model.account == nil)

        model.connect(open: { _ in })
        for _ in 0..<100 {
            if model.account == Account(email: "new@lody.ai") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.account == Account(email: "new@lody.ai"))
        #expect(store.read() == "new-token")
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
        let client = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL, cacheURL: Self.isolatedCacheURL)

        let account = await client.restoreSession()
        #expect(account == Account(email: "ada@lody.ai"))
    }

    @Test func missingSessionClearsToken() async {
        let store = MemoryAuthTokenStore()
        #expect(store.write("stale"))
        let log = AuthRequestLog()
        log.install { _ in (200, Data("null".utf8)) }
        let client = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL, cacheURL: Self.isolatedCacheURL)

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
        let client = HTTPLodyClient(session: log.session, tokenStore: store, baseURL: log.baseURL, cacheURL: Self.isolatedCacheURL)
        let authorization = try await client.beginDeviceAuthorization()
        try await client.finishDeviceAuthorization(authorization)

        let workspaces = try await client.workspaces()
        #expect(workspaces == [WorkspaceSummary(id: "org-1", name: "Spike", slug: "spike")])
    }

    @Test func streamsAccessUsesSelectedWorkspaceAndAccountToken() async throws {
        let log = AuthRequestLog()
        log.install { request in
            switch request.url?.path {
            case "/api/auth/device/code":
                return (200, Data(deviceCodeJSON.utf8))
            case "/api/auth/device/token":
                return (200, Data(#"{"access_token":"session-token"}"#.utf8))
            case "/api/auth/get-session":
                return (200, Data(#"{"user":{"email":"ada@lody.ai"}}"#.utf8))
            case "/api/loro-streams/token":
                guard request.httpMethod == "POST",
                      request.value(forHTTPHeaderField: "Authorization") == "Bearer session-token"
                else { return (401, Data()) }
                return (200, Data(#"{"token":"streams-token","expiresIn":300,"gatewayBaseUrl":"https://streams.lody.ai","shardHostSuffix":"streams.lody.ai"}"#.utf8))
            default:
                return (404, Data())
            }
        }
        let client = HTTPLodyClient(
            session: log.session,
            tokenStore: MemoryAuthTokenStore(),
            baseURL: log.baseURL,
            cacheURL: Self.isolatedCacheURL
        )
        let authorization = try await client.beginDeviceAuthorization()
        try await client.finishDeviceAuthorization(authorization)

        let access = try await client.streamsAccess(workspaceID: "org-1")

        #expect(access.token == "streams-token")
        #expect(access.expiresIn == 300)
        #expect(access.gatewayBaseURL == URL(string: "https://streams.lody.ai"))
        #expect(access.shardHostSuffix == "streams.lody.ai")
        let request = try JSONDecoder().decode(StreamsTokenProbe.self, from: try #require(log.bodies.last))
        #expect(request.workspaceId == "org-1")
        let requestCount = log.bodies.count
        #expect(try await client.streamsAccess(workspaceID: "org-1") == access)
        #expect(log.bodies.count == requestCount)
    }

    @Test func streamsProxyOnlyAllowsGatewayAndShardHosts() throws {
        let gateway = try #require(URL(string: "https://gateway.lody.ai"))
        let policy = StreamsHostPolicy(gatewayBaseURL: gateway, shardHostSuffix: "streams.lody.ai")

        #expect(policy.allows(try #require(URL(string: "https://gateway.lody.ai/ds/lody/meta"))))
        #expect(policy.allows(try #require(URL(string: "https://shard.streams.lody.ai/ds/lody/meta"))))
        #expect(!policy.allows(try #require(URL(string: "https://evilstreams.lody.ai/ds/lody/meta"))))
        #expect(!policy.allows(try #require(URL(string: "https://example.com/ds/lody/meta"))))
        #expect(!policy.allows(try #require(URL(string: "http://gateway.lody.ai/ds/lody/meta"))))
        #expect(!policy.allows(try #require(URL(string: "https://gateway.lody.ai/other/meta"))))
    }

    @Test func sessionsRequireStreamsGateway() async throws {
        let log = AuthRequestLog()
        log.install { request in
            switch request.url?.path {
            case "/api/auth/device/code":
                return (200, Data(deviceCodeJSON.utf8))
            case "/api/auth/device/token":
                return (200, Data(#"{"access_token":"session-token"}"#.utf8))
            case "/api/auth/get-session":
                return (200, Data(#"{"user":{"email":"ada@lody.ai"}}"#.utf8))
            case "/api/loro-streams/token":
                return (200, Data(#"{"token":"streams-token","expiresIn":300}"#.utf8))
            default:
                return (404, Data())
            }
        }
        let client = HTTPLodyClient(
            session: log.session,
            tokenStore: MemoryAuthTokenStore(),
            baseURL: log.baseURL,
            cacheURL: Self.isolatedCacheURL
        )
        let authorization = try await client.beginDeviceAuthorization()
        try await client.finishDeviceAuthorization(authorization)
        await #expect(throws: LodyClientError.notConnected) {
            try await client.sessions(workspaceID: "org-1")
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

private struct StreamsTokenProbe: Decodable {
    let workspaceId: String
}

private final class PollCount: @unchecked Sendable {
    var value = 0
}

private final class AuthTokenSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var isFirst = true

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        if isFirst {
            isFirst = false
            return "old-token"
        }
        return "new-token"
    }
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

    func fail(_ error: Error) {
        client?.urlProtocol(self, didFailWithError: error)
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

@MainActor
@Suite(.serialized)
struct StreamFetchHandlerTests {
    @Test(.timeLimit(.minutes(1))) func forwardsPOSTBodyThroughNativeProxy() async throws {
        let (started, startedSignal) = AsyncStream<Void>.makeStream()
        let requestBox = StreamingRequestBox()
        StreamingTestURLProtocol.onStart = { requestBox.capture($0); startedSignal.yield(()) }
        defer { StreamingTestURLProtocol.onStart = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let handler = StreamFetchHandler(session: session) { _, _ in
            StreamsAccess(token: "test-token", expiresIn: 300,
                          gatewayBaseURL: URL(string: "https://example.test"), shardHostSuffix: nil)
        }
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = .nonPersistent()
        webConfiguration.userContentController.addScriptMessageHandler(handler, contentWorld: .page, name: "streamFetch")
        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        handler.webView = webView
        defer { handler.cancelAll(); webView.stopLoading() }
        webView.loadHTMLString("", baseURL: nil)
        let ready = try await webView.callAsyncJavaScript("""
            const access = await window.webkit.messageHandlers.streamFetch.postMessage({
              command: 'auth', workspaceID: 'test-workspace'
            });
            return await window.webkit.messageHandlers.streamFetch.postMessage({
              command: 'start', id: 'post', url: 'https://example.test/ds/lody/s', method: 'POST',
              headers: {authorization: 'Bearer ' + access.token, 'content-type': 'text/plain'},
              body: btoa(String.fromCharCode(...new TextEncoder().encode('你好')))
            });
            """, arguments: [:], in: nil, contentWorld: .page)
        #expect(ready as? Bool == true)
        var requests = started.makeAsyncIterator()
        _ = await requests.next()
        #expect(requestBox.methodAndBody() == ("POST", Data("你好".utf8)))
    }

    @Test(.timeLimit(.minutes(1))) func forwardsSSEBeforeEOFAndCancelsNativeRequest() async throws {
        let (started, startedSignal) = AsyncStream<Void>.makeStream()
        let pendingRequest = StreamingRequestBox()
        let (stopped, stoppedSignal) = AsyncStream<Void>.makeStream()
        StreamingTestURLProtocol.onStart = { pendingRequest.capture($0); startedSignal.yield(()) }
        StreamingTestURLProtocol.onStop = { stoppedSignal.yield(()) }
        defer {
            StreamingTestURLProtocol.onStart = nil
            StreamingTestURLProtocol.onStop = nil
        }
        var requests = started.makeAsyncIterator()
        var cancellations = stopped.makeAsyncIterator()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let handler = StreamFetchHandler(session: session) { _, _ in
            StreamsAccess(
                token: "synthetic-test-token", expiresIn: 300,
                gatewayBaseURL: URL(string: "https://example.test"), shardHostSuffix: nil
            )
        }
        let sink = StreamEventSink()
        var events = sink.events.makeAsyncIterator()
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = .nonPersistent()
        webConfiguration.userContentController.addScriptMessageHandler(handler, contentWorld: .page, name: "streamFetch")
        webConfiguration.userContentController.addScriptMessageHandler(sink, contentWorld: .page, name: "testEvents")
        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        handler.webView = webView
        defer { handler.cancelAll(); webView.stopLoading() }
        webView.loadHTMLString("""
            <script>
            window.kurageFetchEvent = event => window.webkit.messageHandlers.testEvents.postMessage(event);
            window.webkit.messageHandlers.testEvents.postMessage({type: 'ready'});
            </script>
            """, baseURL: nil)
        #expect(await events.next() == "ready")
        _ = try await webView.callAsyncJavaScript("""
            const access = await window.webkit.messageHandlers.streamFetch.postMessage({
              command: 'auth', workspaceID: 'test-workspace'
            });
            return await window.webkit.messageHandlers.streamFetch.postMessage({
              command: 'start', id: 'test', url: 'https://example.test/ds/lody/s', method: 'GET',
              headers: {authorization: 'Bearer ' + access.token}
            });
            """, arguments: [:], in: nil, contentWorld: .page)
        _ = await requests.next()
        pendingRequest.sendHeaders()
        #expect(await events.next() == "headers")
        // Deliberately keep the response open: a buffered data(for:) bridge hangs here.
        pendingRequest.sendChunk(Data("data: 你好\n".utf8))
        #expect(await events.next() == "data: 你好\n")
        // A long SSE line must flush bounded chunks without waiting for a newline.
        let fullChunk = String(repeating: "x", count: 16_384)
        pendingRequest.sendChunk(Data((fullChunk + fullChunk + "tail\n").utf8))
        #expect(await events.next() == fullChunk)
        #expect(await events.next() == fullChunk)
        #expect(await events.next() == "tail\n")
        _ = try await webView.callAsyncJavaScript("""
            return await window.webkit.messageHandlers.streamFetch.postMessage({command: 'cancel', id: 'test'});
            """, arguments: [:], in: nil, contentWorld: .page)
        _ = await cancellations.next()
    }
}

@MainActor
private final class StreamEventSink: NSObject, WKScriptMessageHandlerWithReply {
    let events: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    override init() {
        (events, continuation) = AsyncStream.makeStream()
        super.init()
    }
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        if let event = message.body as? [String: Any], let type = event["type"] as? String {
            if type == "chunk", let body = event["body"] as? String, let data = Data(base64Encoded: body) {
                continuation.yield(String(decoding: data, as: UTF8.self))
            } else { continuation.yield(type) }
        }
        return (true, nil)
    }
}

private final class StreamingTestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var onStart: (@Sendable (StreamingTestURLProtocol) -> Void)?
    nonisolated(unsafe) static var onStop: (@Sendable () -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.onStart?(self) }
    override func stopLoading() { Self.onStop?() }
    func sendHeaders() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    func sendChunk(_ data: Data) { client?.urlProtocol(self, didLoad: data) }
}

private final class StreamingRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: StreamingTestURLProtocol?
    func capture(_ request: StreamingTestURLProtocol) {
        lock.withLock { self.request = request }
    }
    func sendHeaders() { lock.withLock { request?.sendHeaders() } }
    func sendChunk(_ data: Data) { lock.withLock { request?.sendChunk(data) } }
    func methodAndBody() -> (String?, Data?) {
        lock.withLock {
            guard let request = request?.request else { return (nil, nil) }
            if let body = request.httpBody { return (request.httpMethod, body) }
            guard let stream = request.httpBodyStream else { return (request.httpMethod, nil) }
            stream.open()
            defer { stream.close() }
            var body = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 1024)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            return (request.httpMethod, body)
        }
    }
}
