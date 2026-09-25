import Foundation
import Testing
@testable import Kurage

@MainActor
struct FixtureLodyClientTests {
    @Test func fixtureConversationsSupportReadingAndActions() {
        let model = AppModel(client: FixtureLodyClient())

        #expect(model.supportsConversations)
        #expect(model.supportsTextSending)
        #expect(model.supportsPermissionResponses)
    }

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

    @Test func sessionImagesLoadForTheOwningSessionOnly() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let image = try await client.loadSessionImage(
            workspaceID: "ws-demo", sessionID: "session-pr", imageID: "pr-shot", variant: .square
        )
        #expect(image == FixtureImage.png)
        await #expect(throws: LodyClientError.sessionMissing) {
            try await client.loadSessionImage(
                workspaceID: "ws-demo", sessionID: "session-tests", imageID: "pr-shot", variant: .original
            )
        }
        client.signOut()
        await #expect(throws: LodyClientError.signedOut) {
            try await client.loadSessionImage(
                workspaceID: "ws-demo", sessionID: "session-pr", imageID: "pr-shot", variant: .original
            )
        }
    }

    @Test func sendAppendsTrimmedUserTurn() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        try await client.send("  look again  ", sessionID: "session-pr", workspaceID: "ws-demo")

        let conversation = try await client.conversation(sessionID: "session-pr", workspaceID: "ws-demo")
        #expect(conversation.turns.last?.author == .user)
        #expect(conversation.turns.last?.text == "look again")

        let sessions = try await client.sessions(workspaceID: "ws-demo")
        #expect(sessions.first?.id == "session-pr")
        #expect(sessions.first { $0.id == "session-pr" }?.preview == "look again")
    }

    @Test func sendingMovesSessionAndProjectToRecentPosition() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()

        try await model.send("  look again  ", sessionID: "session-pr")

        #expect(model.sessions.first?.id == "session-pr")
        #expect(model.sessions.first?.preview == "look again")
        #expect(SessionProjectGroup.make(from: model.sessions).first?.id == "local:machine-1:prism")
    }

    @Test func runConfigChoiceAppliesToNextTurn() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()
        let initial = try #require(await latestRunConfig(model, sessionID: "session-long"))
        #expect(initial.editable?.kind == .reasoning)
        #expect(initial.choosing("ultra") == nil)
        let choice = try #require(initial.choosing("low"))
        #expect(choice == RunConfigChoice(configOptionID: "reasoning_effort", value: "low"))
        #expect(initial.applying(choice).reasoning?.label == "Low")
        #expect(initial.applying(choice).model == initial.model)

        let sentChoice = try await model.send("faster please", runConfig: choice, sessionID: "session-long")
        #expect(sentChoice == choice)
        #expect(try await latestRunConfig(model, sessionID: "session-long")?.reasoning?.value == "low")
    }

    @Test func runConfigPatchDecodesBridgeProjection() throws {
        let json = """
        {"sessionID":"s","order":[],"changed":[],"permission":null,"activity":"idle","syncState":"live",
         "runConfig":{"model":{"value":"flash","label":"Flash"},"reasoning":null,
           "editable":{"kind":"model","configOptionID":"model","options":[{"value":"flash","label":"Flash"}]}}}
        """
        let patch = try JSONDecoder().decode(ConversationPatch.self, from: Data(json.utf8))
        let update = try patch.applying(to: Conversation(sessionID: "s", turns: [], permission: nil))
        #expect(update.runConfig?.model?.label == "Flash")
        #expect(update.runConfig?.reasoning == nil)
        #expect(update.runConfig?.choosing("flash") == RunConfigChoice(configOptionID: "model", value: "flash"))
    }

    private func latestRunConfig(_ model: AppModel, sessionID: String) async -> SessionRunConfig? {
        var latest: SessionRunConfig?
        try? await model.observeConversation(sessionID: sessionID) { latest = $0.runConfig }
        return latest
    }

    @Test func emptySendIsRejected() async {
        let client = FixtureLodyClient(startsSignedIn: true)
        await #expect(throws: LodyClientError.emptyMessage) {
            try await client.send("   ", sessionID: "session-pr", workspaceID: "ws-demo")
        }
    }

    @Test func cancellingRunningSessionMakesItIdle() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()
        try await model.cancelSession(sessionID: "session-tests")
        #expect(model.sessions.first { $0.id == "session-tests" }?.activity == .idle)
    }

    @Test func archivingRemovesOneSessionFromTheWorkspace() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        try await model.archiveSession(sessionID: "session-pr")
        #expect(model.sessions.map(\.id) == ["session-tests", "session-long"])
        #expect(try await client.sessions(workspaceID: "ws-demo").map(\.id) == ["session-tests", "session-long"])
        try await model.archiveSession(sessionID: "session-pr")
        #expect(model.sessions.map(\.id) == ["session-tests", "session-long"])
    }

    @Test func archivedSessionsRestoreAndDeleteNewestFirst() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        await model.refreshArchivedSessions()
        #expect(model.archivedSessions.map(\.id) == ["archived-newer", "archived-older"])
        #expect(model.sessions.map(\.id) == ["session-tests", "session-long", "session-pr"])

        await model.restoreArchivedSession("archived-newer")
        #expect(model.archivedSessions.map(\.id) == ["archived-older"])
        #expect(model.sessions.contains { $0.id == "archived-newer" })

        await model.deleteArchivedSession("archived-older")
        #expect(model.archivedSessions.isEmpty)
        try await client.archiveSession(sessionID: "session-pr", workspaceID: "ws-demo")
        #expect(try await client.archivedSessions(workspaceID: "ws-demo").map(\.id) == ["session-pr"])
        await #expect(throws: LodyClientError.sessionMissing) {
            try await client.conversation(sessionID: "archived-older", workspaceID: "ws-demo")
        }
        model.signOut()
        #expect(model.archivedSessions.isEmpty)
    }

    @Test func restoreRejectsARemovedProjectAndDeleteLeavesActiveSessions() async throws {
        var removed = SessionRecord(
            summary: SessionSummary(id: "gone", title: "gone project", agentName: "codex", activity: .idle, preview: ""),
            turns: []
        )
        removed.canRestore = false
        let client = FixtureLodyClient(startsSignedIn: true, records: [removed], archivedIDs: ["gone"])
        await #expect(throws: LodyClientError.archivedProjectUnavailable) {
            try await client.restoreArchivedSession(sessionID: "gone", workspaceID: "ws-demo")
        }
        #expect(try await client.archivedSessions(workspaceID: "ws-demo").map(\.canRestore) == [false])
        await #expect(throws: LodyClientError.notConnected) {
            try await client.archivedSessions(workspaceID: "other")
        }
        await #expect(throws: LodyClientError.sessionMissing) {
            try await client.deleteArchivedSession(sessionID: "session-tests", workspaceID: "ws-demo")
        }
    }

    @Test func archiveRejectsAMissingSession() async {
        let client = FixtureLodyClient(startsSignedIn: true)
        await #expect(throws: LodyClientError.sessionMissing) {
            try await client.archiveSession(sessionID: "missing", workspaceID: "ws-demo")
        }
        client.signOut()
        await #expect(throws: LodyClientError.signedOut) {
            try await client.archiveSession(sessionID: "session-pr", workspaceID: "ws-demo")
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

    @Test func workspaceFailureSurvivesSuccessfulSessionRefresh() async {
        let client = DeferredSessionClient()
        let model = AppModel(client: client)
        await model.refreshWorkspaces()
        client.workspaceError = .unreachable
        var requests = client.started.makeAsyncIterator()
        let refresh = Task { await model.refreshContent() }
        #expect(await requests.next() == "ws-a")
        client.finish("ws-a", with: [Self.session("fresh")])
        await refresh.value
        #expect(model.sessions.map(\.id) == ["fresh"])
        #expect(model.statusNote == StatusNote(tone: .failure, text: "Could not load workspaces."))

        client.workspaceError = nil
        await model.refreshWorkspaces()
        #expect(model.statusNote == nil)

        client.workspaceError = .unreachable
        await model.refreshWorkspaces()
        model.signOut()
        #expect(model.statusNote == nil)
    }

    private static func session(_ id: String) -> SessionSummary {
        SessionSummary(id: id, title: id, agentName: "codex", activity: .idle, preview: "")
    }
}

@MainActor
private final class DeferredSessionClient: LodyClient {
    private(set) var account: Account? = Account(email: "demo@example.com")
    var workspaceError: LodyClientError?
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
        if let workspaceError { throw workspaceError }
        return [WorkspaceSummary(id: "ws-a", name: "A", slug: "a"),
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
    @discardableResult
    func send(
        _ text: String,
        runConfig: RunConfigChoice?,
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> RunConfigChoice? {
        throw LodyClientError.notConnected
    }
    func cancelSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
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
        // Streaming keeps the snapshot but defers search text until indexing resumes.
        #expect(model.sessionSearchBody(sessionID: "s").isEmpty)

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
        #expect(model.sessionSearchBody(sessionID: "s").isEmpty)
        signal.finish()
        #expect(await changes.next() == nil)
    }
}

@MainActor
struct ConversationRunConfigStateTests {
    private let low = RunConfigChoice(configOptionID: "reasoning_effort", value: "low")
    private let high = RunConfigChoice(configOptionID: "reasoning_effort", value: "high")

    private var initial: SessionRunConfig {
        SessionRunConfig(
            model: .init(value: "model", label: "Model"),
            reasoning: .init(value: "medium", label: "Medium"),
            editable: .init(kind: .reasoning, configOptionID: "reasoning_effort", options: [
                .init(value: "low", label: "Low"),
                .init(value: "medium", label: "Medium"),
                .init(value: "high", label: "High"),
            ])
        )
    }

    @Test(arguments: [true, false], [true, false])
    func retryKeepsUnusedChoice(observationBeforeCompletion: Bool, originalHasChoice: Bool) {
        var state = ConversationRunConfigState()
        state.receive(initial)
        if originalHasChoice { state.choose(low.value) }
        let originalChoice = state.choice
        // The first attempt is unconfirmed. A different choice is made before retrying.
        state.choose(high.value)
        let confirmed = initial.applying(originalChoice)
        if observationBeforeCompletion { state.receive(confirmed) }
        state.didSend(originalChoice)
        if !observationBeforeCompletion { state.receive(confirmed) }

        #expect(state.config == confirmed)
        #expect(state.choice == high)
        #expect(state.displayed?.reasoning?.value == "high")
        // Sending the next new turn consumes the preserved choice.
        state.didSend(state.choice)
        #expect(state.config?.reasoning?.value == "high")
        #expect(state.choice == nil)
    }

    @Test func successfulSendClearsOnlyTheAppliedChoice() {
        var state = ConversationRunConfigState()
        state.receive(initial)
        state.choose(low.value)
        state.didSend(low)
        #expect(state.config?.reasoning?.value == "low")
        #expect(state.choice == nil)

        state.choose(high.value)
        state.receive(initial.applying(high))
        state.choose("medium") // A new selection made while the send is completing.
        state.didSend(high)
        #expect(state.config?.reasoning?.value == "high")
        #expect(state.choice?.value == "medium")
    }

    @Test(arguments: [true, false])
    func retryPreservesExplicitReturnToBaseline(observationBeforeCompletion: Bool) {
        var state = ConversationRunConfigState()
        state.receive(initial)
        state.choose(low.value)
        let originalChoice = state.choice
        // Sending Low was unconfirmed. The user chooses the original Medium
        // baseline for their next draft before retrying the earlier message.
        state.choose("medium")
        let nextChoice = RunConfigChoice(configOptionID: "reasoning_effort", value: "medium")
        #expect(state.choice == nextChoice)

        let confirmed = initial.applying(originalChoice)
        if observationBeforeCompletion { state.receive(confirmed) }
        state.didSend(originalChoice)
        if !observationBeforeCompletion { state.receive(confirmed) }
        #expect(state.config?.reasoning?.value == "low")
        #expect(state.choice == nextChoice)
        #expect(state.displayed?.reasoning?.value == "medium")

        // The next new turn sends Medium explicitly instead of inheriting Low.
        state.didSend(state.choice)
        #expect(state.config?.reasoning?.value == "medium")
        #expect(state.choice == nil)
    }
}
