import Foundation
import Testing
@testable import Kurage

@MainActor
struct SignInTests {
    @Test(arguments: [false, true])
    func cancelledAuthorizationCannotOpenBrowserOrClearRetry(fails: Bool) async throws {
        let client = DeferredAuthorizationClient()
        let model = AppModel(client: client)
        var openedURLs: [URL] = []
        var requests = client.requests.makeAsyncIterator()
        model.connect { openedURLs.append($0) }
        #expect(model.isSigningIn)
        let first = try #require(await requests.next())

        model.cancelConnect()
        #expect(!model.isSigningIn)
        #expect(model.deviceAuthorization == nil)
        #expect(model.statusNote == nil)
        model.connect { openedURLs.append($0) }
        let second = try #require(await requests.next())

        if fails {
            client.fail(first)
        } else {
            client.authorize(first)
        }
        // The old request deliberately ignores cancellation until it completes.
        for _ in 0..<10 { await Task.yield() }
        #expect(model.isSigningIn)
        #expect(model.deviceAuthorization == nil)
        #expect(model.statusNote == nil)
        #expect(openedURLs.isEmpty)

        client.authorize(second)
        for _ in 0..<100 {
            if model.isSignedIn { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.isSignedIn)
        #expect(openedURLs == [client.authorization.verificationURL])
        #expect(model.deviceAuthorization == nil)
        #expect(!model.isSigningIn)
    }

    @Test func closingBrowserCancelsTokenWaitAndCanStartAgain() async throws {
        let client = FixtureLodyClient(authorizationDelay: .seconds(600))
        let model = AppModel(client: client)
        let (opened, signal) = AsyncStream<URL>.makeStream()
        var pages = opened.makeAsyncIterator()
        model.connect { signal.yield($0) }
        _ = try #require(await pages.next())
        #expect(model.deviceAuthorization != nil)

        model.cancelConnect()
        #expect(!model.isSigningIn)
        #expect(model.deviceAuthorization == nil)
        #expect(client.account == nil)

        model.connect { signal.yield($0) }
        _ = try #require(await pages.next())
        #expect(model.isSigningIn)
        #expect(model.deviceAuthorization != nil)
        model.cancelConnect()
        #expect(model.statusNote == nil)
    }
}

@MainActor
private final class DeferredAuthorizationClient: LodyClient {
    private(set) var account: Account?
    let authorization = DeviceAuthorization(
        userCode: "TEST-CODE", verificationURL: URL(string: "https://lody.ai/device?user_code=TEST-CODE")!,
        deviceCode: "test-device", expiresIn: 600, interval: 1
    )
    let requests: AsyncStream<UUID>
    private let requestSignal: AsyncStream<UUID>.Continuation
    private var pending: [UUID: CheckedContinuation<DeviceAuthorization, Error>] = [:]

    init() {
        (requests, requestSignal) = AsyncStream.makeStream()
    }

    func beginDeviceAuthorization() async throws -> DeviceAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            pending[id] = continuation
            requestSignal.yield(id)
        }
    }

    func authorize(_ id: UUID) {
        pending.removeValue(forKey: id)?.resume(returning: authorization)
    }

    func fail(_ id: UUID) {
        pending.removeValue(forKey: id)?.resume(throwing: LodyClientError.unreachable)
    }

    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws {
        try Task.checkCancellation()
        account = Account(email: "fixture@kurage.app")
    }

    func restoreSession() async -> Account? { account }
    func signOut() { account = nil }
    func workspaces() async throws -> [WorkspaceSummary] { [] }
    func sessions(workspaceID: String) async throws -> [SessionSummary] { [] }
    func conversation(sessionID: String, workspaceID: String) async throws -> Conversation {
        throw LodyClientError.notConnected
    }
    func send(_ text: String, attachments: [ComposerAttachment], runConfig: RunConfigChoice?,
              turnID: String, sessionID: String, workspaceID: String) async throws -> RunConfigChoice? {
        throw LodyClientError.notConnected
    }
    func cancelSession(sessionID: String, workspaceID: String) async throws {
        throw LodyClientError.notConnected
    }
    func respond(_ decision: PermissionDecision, requestID: String, sessionID: String, workspaceID: String) async throws {
        throw LodyClientError.notConnected
    }
}
