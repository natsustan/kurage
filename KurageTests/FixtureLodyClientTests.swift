import Testing
@testable import Kurage

@MainActor
struct FixtureLodyClientTests {
    @Test func sessionsRequireSignIn() async {
        let client = FixtureLodyClient()
        await #expect(throws: LodyClientError.signedOut) {
            try await client.sessions(workspaceID: "ws-demo")
        }
    }

    @Test func signInListsSampleSessions() async throws {
        let client = FixtureLodyClient()
        let authorization = try await client.beginDeviceAuthorization()
        #expect(authorization.userCode == "ABCD-EFGH")
        try await client.finishDeviceAuthorization(authorization)

        let sessions = try await client.sessions(workspaceID: "ws-demo")
        #expect(sessions.map(\.id) == ["session-tests", "session-long", "session-pr"])
        #expect(sessions[0].activity == .running)
        #expect(sessions[1].activity == .idle)

        let conversation = try await client.conversation(sessionID: "session-tests", workspaceID: "ws-demo")
        #expect(conversation.permission?.id == "perm-npm-test")
        #expect(conversation.turns.count == 2)
    }

    @Test func sendAppendsTrimmedUserTurn() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        try await client.send("  look again  ", sessionID: "session-pr", workspaceID: "ws-demo")

        let conversation = try await client.conversation(sessionID: "session-pr", workspaceID: "ws-demo")
        #expect(conversation.turns.last?.author == .user)
        #expect(conversation.turns.last?.text == "look again")

        let sessions = try await client.sessions(workspaceID: "ws-demo")
        #expect(sessions.first { $0.id == "session-pr" }?.preview == "look again")
    }

    @Test func emptySendIsRejected() async {
        let client = FixtureLodyClient(startsSignedIn: true)
        await #expect(throws: LodyClientError.emptyMessage) {
            try await client.send("   ", sessionID: "session-pr", workspaceID: "ws-demo")
        }
    }

    @Test func allowClearsPermission() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        try await client.respond(.allow, requestID: "perm-npm-test", sessionID: "session-tests", workspaceID: "ws-demo")

        let conversation = try await client.conversation(sessionID: "session-tests", workspaceID: "ws-demo")
        #expect(conversation.permission == nil)

        let sessions = try await client.sessions(workspaceID: "ws-demo")
        #expect(sessions.first { $0.id == "session-tests" }?.preview == "Allowed")
    }

    @Test func unknownPermissionIsRejected() async {
        let client = FixtureLodyClient(startsSignedIn: true)
        await #expect(throws: LodyClientError.permissionMissing) {
            try await client.respond(.deny, requestID: "missing", sessionID: "session-tests", workspaceID: "ws-demo")
        }
    }

    @Test func signOutBlocksLaterReads() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        client.signOut()
        await #expect(throws: LodyClientError.signedOut) {
            try await client.conversation(sessionID: "session-pr", workspaceID: "ws-demo")
        }
    }
}

@MainActor
struct AppModelSessionRefreshTests {
    @Test func sharesRefreshAndDiscardsCancelledWorkspaceResult() async {
        let client = DeferredSessionClient()
        let model = AppModel(client: client)
        var requests = client.started.makeAsyncIterator()

        let initial = Task { await model.adoptExistingAccount() }
        #expect(await requests.next() == "ws-a")

        let (secondStarted, secondSignal) = AsyncStream<Void>.makeStream()
        var secondStart = secondStarted.makeAsyncIterator()
        let second = Task {
            secondSignal.yield(())
            await model.refreshSessions()
        }
        _ = await secondStart.next()
        await Task.yield()
        #expect(client.requestedWorkspaceIDs == ["ws-a"])

        let switchWorkspace = Task { await model.selectWorkspace("ws-b") }
        #expect(await requests.next() == "ws-b")
        client.finish("ws-b", with: [Self.session("new")])
        await switchWorkspace.value

        client.finish("ws-a", with: [Self.session("stale")])
        await initial.value
        await second.value

        #expect(client.requestedWorkspaceIDs == ["ws-a", "ws-b"])
        #expect(model.selectedWorkspaceID == "ws-b")
        #expect(model.sessions.map(\.id) == ["new"])
        #expect(!model.isRefreshingSessions)
    }

    private static func session(_ id: String) -> SessionSummary {
        SessionSummary(id: id, title: id, agentName: "codex", activity: .idle, preview: "")
    }
}

@MainActor
private final class DeferredSessionClient: LodyClient {
    private(set) var account: Account? = Account(email: "demo@example.com")
    private(set) var requestedWorkspaceIDs: [String] = []
    private var pending: [String: [CheckedContinuation<[SessionSummary], Error>]] = [:]
    let observationsStarted: AsyncStream<String>
    private let observationSignal: AsyncStream<String>.Continuation
    var observation: AsyncThrowingStream<ConversationUpdate, Error>.Continuation?

    func observeConversation(sessionID: String, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error> {
        let (stream, continuation) = AsyncThrowingStream<ConversationUpdate, Error>.makeStream()
        observation = continuation
        observationSignal.yield(workspaceID)
        return stream
    }
    let started: AsyncStream<String>
    private let startedSignal: AsyncStream<String>.Continuation

    init() {
        (started, startedSignal) = AsyncStream.makeStream()
        (observationsStarted, observationSignal) = AsyncStream.makeStream()
    }

    func beginDeviceAuthorization() async throws -> DeviceAuthorization { throw LodyClientError.notConnected }
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws { throw LodyClientError.notConnected }
    func restoreSession() async -> Account? { account }
    func signOut() { account = nil }
    func workspaces() async throws -> [WorkspaceSummary] {
        [WorkspaceSummary(id: "ws-a", name: "A", slug: "a"),
         WorkspaceSummary(id: "ws-b", name: "B", slug: "b")]
    }

    func sessions(workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary] {
        requestedWorkspaceIDs.append(workspaceID)
        startedSignal.yield(workspaceID)
        let sessions: [SessionSummary] = try await withCheckedThrowingContinuation { continuation in
            pending[workspaceID, default: []].append(continuation)
        }
        try Task.checkCancellation()
        return sessions
    }

    func finish(_ workspaceID: String, with sessions: [SessionSummary]) {
        for continuation in pending.removeValue(forKey: workspaceID) ?? [] {
            continuation.resume(returning: sessions)
        }
    }

    func conversation(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> Conversation {
        throw LodyClientError.notConnected
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
}

@MainActor
struct ConversationStreamingTests {
    @Test func patchesReplaceGrowingTurnsAndRemoveDeletedTurns() throws {
        let previous = Conversation(sessionID: "s", turns: [
            ConversationTurn(id: "a", author: .agent, text: "Hello"),
            ConversationTurn(id: "b", author: .user, text: "Remove me"),
        ], permission: nil)
        let patch = ConversationPatch(sessionID: "s", order: ["a"], changed: [
            ConversationTurn(id: "a", author: .agent, text: "Hello world"),
        ], permission: nil, activity: "idle", syncState: .live)
        let update = try patch.applying(to: previous)
        #expect(update.conversation.turns.map(\.id) == ["a"])
        #expect(update.conversation.turns[0].text == "Hello world")
        #expect(update.activity == .idle)
        let statusOnly = ConversationPatch(sessionID: "s", order: ["a"], changed: [],
                                           permission: nil, activity: "running", syncState: .connecting)
        #expect(try statusOnly.applying(to: update.conversation).conversation == update.conversation)
    }

    @Test func rejectsIncompleteOrWrongSessionPatches() {
        let previous = Conversation(sessionID: "s", turns: [], permission: nil)
        for patch in [
            ConversationPatch(sessionID: "other", order: [], changed: [], permission: nil, activity: "idle", syncState: .live),
            ConversationPatch(sessionID: "s", order: ["missing"], changed: [], permission: nil, activity: "idle", syncState: .live),
        ] {
            #expect(throws: LodyClientError.notConnected) { try patch.applying(to: previous) }
        }
    }

    @Test func switchingWorkspaceRejectsLateUpdatesAndPreservesScopedCache() async throws {
        let client = DeferredSessionClient()
        let model = AppModel(client: client)
        var requests = client.started.makeAsyncIterator()
        let adopting = Task { await model.adoptExistingAccount() }
        #expect(await requests.next() == "ws-a")
        client.finish("ws-a", with: [])
        await adopting.value

        let (received, signal) = AsyncStream<ConversationUpdate>.makeStream()
        var changes = received.makeAsyncIterator()
        var subscriptions = client.observationsStarted.makeAsyncIterator()
        let observing = Task { try await model.observeConversation(sessionID: "s") { signal.yield($0) } }
        #expect(await subscriptions.next() == "ws-a")
        let first = ConversationUpdate(conversation: Conversation(sessionID: "s", turns: [
            ConversationTurn(id: "a", author: .agent, text: "Partial"),
        ], permission: nil), activity: .running, syncState: .live)
        client.observation?.yield(first)
        #expect(await changes.next() == first)
        #expect(model.cachedConversation(sessionID: "s") == first.conversation)

        let switching = Task { await model.selectWorkspace("ws-b") }
        #expect(await requests.next() == "ws-b")
        client.finish("ws-b", with: [])
        await switching.value
        client.observation?.yield(first)
        switch await observing.result {
        case .success: Issue.record("A stale subscription must terminate")
        case .failure(let error): #expect(error is CancellationError)
        }
        #expect(model.cachedConversation(sessionID: "s") == nil)
        signal.finish()
        #expect(await changes.next() == nil)
    }
}
