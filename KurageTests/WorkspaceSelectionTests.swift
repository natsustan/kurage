import Foundation
import Testing
@testable import Kurage

@MainActor
struct WorkspaceSelectionTests {
    private let demo = WorkspaceSummary(id: "ws-demo", name: "Demo", slug: "demo")
    private let studio = WorkspaceSummary(id: "ws-studio", name: "Studio", slug: "studio")

    @Test(arguments: [false, true])
    func olderRefreshCannotOverwriteNewerResult(fails: Bool) async throws {
        let client = DeferredWorkspaceClient()
        let model = AppModel(client: client)
        var requests = client.requests.makeAsyncIterator()
        let first = Task { await model.refreshWorkspaces() }
        let firstID = try #require(await requests.next())
        let second = Task { await model.refreshWorkspaces() }
        let secondID = try #require(await requests.next())
        client.complete(secondID, with: [studio])
        await second.value
        if fails { client.fail(firstID) }
        else { client.complete(firstID, with: [demo]) }
        await first.value
        #expect(model.workspaces == [studio])
        #expect(model.selectedWorkspaceID == studio.id)
        #expect(model.workspaceLoadStatusNote == nil)
        #expect(!model.isRefreshingWorkspaces)
    }

    @Test func oldCompletionDoesNotClearCurrentLoadingState() async throws {
        let client = DeferredWorkspaceClient()
        let model = AppModel(client: client)
        var requests = client.requests.makeAsyncIterator()
        let first = Task { await model.refreshWorkspaces() }
        let firstID = try #require(await requests.next())
        let second = Task { await model.refreshWorkspaces() }
        let secondID = try #require(await requests.next())
        client.complete(firstID, with: [demo])
        await first.value
        #expect(model.isRefreshingWorkspaces)
        #expect(model.workspaces.isEmpty)
        client.complete(secondID, with: [studio])
        await second.value
        #expect(!model.isRefreshingWorkspaces)
        #expect(model.workspaces == [studio])
    }

    @Test func cancelledRefreshIgnoresUncooperativeResult() async throws {
        let client = DeferredWorkspaceClient()
        let model = AppModel(client: client)
        var requests = client.requests.makeAsyncIterator()
        let refresh = Task { await model.refreshWorkspaces() }
        let id = try #require(await requests.next())
        refresh.cancel()
        client.complete(id, with: [demo])
        await refresh.value
        #expect(model.workspaces.isEmpty)
        #expect(model.selectedWorkspaceID == nil)
        #expect(model.workspaceLoadStatusNote == nil)
        #expect(!model.isRefreshingWorkspaces)
    }

    @Test func refreshFromPreviousAccountCannotRestoreSignedOutData() async throws {
        let client = DeferredWorkspaceClient()
        let model = AppModel(client: client)
        var requests = client.requests.makeAsyncIterator()
        let refresh = Task { await model.refreshWorkspaces() }
        let id = try #require(await requests.next())
        model.signOut()
        #expect(!model.isRefreshingWorkspaces)
        client.complete(id, with: [demo])
        await refresh.value
        #expect(!model.isSignedIn)
        #expect(model.workspaces.isEmpty)
        #expect(model.selectedWorkspaceID == nil)
    }

    @Test func refreshFailureKeepsSelectionAndCachedListThenRecovers() async throws {
        let client = DeferredWorkspaceClient()
        let model = AppModel(client: client)
        var requests = client.requests.makeAsyncIterator()
        let initial = Task { await model.refreshWorkspaces() }
        client.complete(try #require(await requests.next()), with: [demo, studio])
        await initial.value
        let failing = Task { await model.refreshWorkspaces() }
        client.fail(try #require(await requests.next()))
        await failing.value
        #expect(model.workspaces == [demo, studio])
        #expect(model.selectedWorkspaceID == demo.id)
        #expect(model.workspaceLoadStatusNote != nil)
        #expect(!model.isRefreshingWorkspaces)
        let retry = Task { await model.refreshWorkspaces() }
        client.complete(try #require(await requests.next()), with: [demo, studio])
        await retry.value
        #expect(model.workspaceLoadStatusNote == nil)
    }

    @Test func sameWorkspaceDoesNotRefreshAndOtherWorkspaceIsIsolated() async throws {
        let client = DeferredWorkspaceClient()
        let model = AppModel(client: client)
        var requests = client.requests.makeAsyncIterator()
        let initial = Task { await model.refreshWorkspaces() }
        client.complete(try #require(await requests.next()), with: [demo, studio])
        await initial.value
        await model.refreshSessions()
        let generation = model.workspaceGeneration
        await model.selectWorkspace(demo.id)
        #expect(model.workspaceGeneration == generation)
        #expect(client.sessionRequests == [demo.id])
        await model.selectWorkspace(studio.id)
        #expect(model.sessions.map(\.id) == ["session-ws-studio"])
        #expect(model.workspaceGeneration == generation + 1)
        await model.selectWorkspace(demo.id)
        #expect(model.sessions.map(\.id) == ["session-ws-demo"])
    }

    @Test func sessionFailureDoesNotUndoCommittedWorkspace() async throws {
        let client = DeferredWorkspaceClient()
        let model = AppModel(client: client)
        var requests = client.requests.makeAsyncIterator()
        let initial = Task { await model.refreshWorkspaces() }
        client.complete(try #require(await requests.next()), with: [demo, studio])
        await initial.value
        client.failingSessionWorkspaceID = studio.id
        await model.selectWorkspace(studio.id)
        #expect(model.selectedWorkspaceID == studio.id)
        #expect(model.sessions.isEmpty)
        #expect(model.statusNote != nil)
        #expect(model.workspaceLoadStatusNote == nil)
    }

    @Test func removingSelectedWorkspaceChoosesAnAvailableOne() async throws {
        let client = DeferredWorkspaceClient()
        let model = AppModel(client: client)
        var requests = client.requests.makeAsyncIterator()
        let initial = Task { await model.refreshWorkspaces() }
        client.complete(try #require(await requests.next()), with: [demo, studio])
        await initial.value
        await model.selectWorkspace(studio.id)
        let refresh = Task { await model.refreshWorkspaces() }
        client.complete(try #require(await requests.next()), with: [demo])
        await refresh.value
        #expect(model.selectedWorkspaceID == demo.id)
        #expect(!model.sessions.contains { $0.id == "session-ws-studio" })
    }

    @Test func additionalFixtureWorkspacesCannotReadDemoSessions() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, workspaceSummaries: [demo, studio])
        #expect(try await client.workspaces() == [demo, studio])
        #expect(try await client.sessions(workspaceID: studio.id).isEmpty)
        let primarySessions = try await client.sessions(workspaceID: demo.id)
        #expect(!primarySessions.isEmpty)
        await #expect(throws: LodyClientError.notConnected) {
            try await client.conversation(sessionID: "session-long", workspaceID: studio.id)
        }
    }
}

@MainActor
private final class DeferredWorkspaceClient: LodyClient {
    private(set) var account: Account? = Account(email: "fixture@kurage.app")
    let requests: AsyncStream<UUID>
    private let requestSignal: AsyncStream<UUID>.Continuation
    private var pending: [UUID: CheckedContinuation<[WorkspaceSummary], Error>] = [:]
    private(set) var sessionRequests: [String] = []
    var failingSessionWorkspaceID: String?

    init() { (requests, requestSignal) = AsyncStream.makeStream() }

    func workspaces() async throws -> [WorkspaceSummary] {
        try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            pending[id] = continuation
            requestSignal.yield(id)
        }
    }

    func complete(_ id: UUID, with workspaces: [WorkspaceSummary]) {
        pending.removeValue(forKey: id)?.resume(returning: workspaces)
    }

    func fail(_ id: UUID) {
        pending.removeValue(forKey: id)?.resume(throwing: LodyClientError.unreachable)
    }

    func sessions(workspaceID: String) async throws -> [SessionSummary] {
        sessionRequests.append(workspaceID)
        if workspaceID == failingSessionWorkspaceID { throw LodyClientError.unreachable }
        return [SessionSummary(id: "session-\(workspaceID)", title: workspaceID,
                               agentName: "Agent", activity: .idle, preview: "")]
    }

    func restoreSession() async -> Account? { account }
    func signOut() { account = nil }
    func beginDeviceAuthorization() async throws -> DeviceAuthorization { throw LodyClientError.notConnected }
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws { throw LodyClientError.notConnected }
    func conversation(sessionID: String, workspaceID: String) async throws -> Conversation { throw LodyClientError.notConnected }
    func send(_ text: String, attachments: [ComposerAttachment], runConfig: RunConfigChoice?, turnID: String,
              sessionID: String, workspaceID: String) async throws -> RunConfigChoice? { throw LodyClientError.notConnected }
    func cancelSession(sessionID: String, workspaceID: String) async throws { throw LodyClientError.notConnected }
    func respond(_ decision: PermissionDecision, requestID: String, sessionID: String, workspaceID: String) async throws {
        throw LodyClientError.notConnected
    }
}
