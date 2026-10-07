import Foundation
import Testing
@testable import Kurage

// Exercise the same staging and delivery entry points as the feature views.
@MainActor
@discardableResult
func stageAndDeliverMessage(_ model: AppModel, _ text: String, attachments: [ComposerAttachment] = [],
                            runConfig: RunConfigChoice? = nil, turnID: String = UUID().uuidString.lowercased(),
                            sessionID: String) async throws -> RunConfigChoice? {
    try model.stageOutgoingMessage(text, composerText: text, mentions: .init(), attachments: attachments,
                                   runConfig: runConfig, sessionID: sessionID, turnID: turnID)
    return try await model.deliverOutgoingMessage(sessionID: sessionID)
}

@MainActor
func stageAndDeliverSession(_ model: AppModel, _ text: String, attachments: [ComposerAttachment] = [],
                            agentConfigID: String? = nil, selections: [RunConfigChoice] = [],
                            projectID: String, templateSessionID: String, parentSessionID: String? = nil) async throws -> String {
    let id = try model.stageSessionStart(text, composerText: text, mentions: .init(), attachments: attachments,
        agentConfigID: agentConfigID, selections: selections, projectID: projectID,
        projectName: model.sessionSummary(templateSessionID)?.projectName ?? "Project",
        templateSessionID: templateSessionID, parentSessionID: parentSessionID)
    try await model.deliverOutgoingMessage(sessionID: id)
    return id
}

@MainActor
func stageAndDeliverTab(_ model: AppModel, _ text: String, attachments: [ComposerAttachment] = [],
                        selections: [RunConfigChoice] = [], agentConfigID: String? = nil, rootID: String) async throws -> String {
    let root = try #require(model.sessionSummary(rootID))
    return try await stageAndDeliverSession(model, text, attachments: attachments, agentConfigID: agentConfigID,
        selections: selections, projectID: root.projectID ?? "", templateSessionID: rootID, parentSessionID: rootID)
}

@MainActor
struct FixtureLodyClientTests {
    @Test func attachmentOnlyMessagesKeepImageBytesAndFileMetadata() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let image = try ComposerAttachment(fileName: "photo.png", mimeType: "image/png", data: FixtureImage.png, isImage: true)
        let file = try ComposerAttachment(fileName: "notes.txt", mimeType: "text/plain", data: Data("hello".utf8), isImage: false)
        try await client.send("", attachments: [image, file], sessionID: "session-long", workspaceID: "ws-demo")
        let conversation = try await client.conversation(sessionID: "session-long", workspaceID: "ws-demo")
        let turn = try #require(conversation.turns.last)
        #expect(turn.content.count == 2)
        #expect(try JSONDecoder().decode(ConversationTurn.self, from: JSONEncoder().encode(turn)) == turn)
        #expect(try await client.loadSessionImage(workspaceID: "ws-demo", sessionID: "session-long",
                                                 imageID: image.id.uuidString, variant: .original) == image.data)
        await #expect(throws: LodyClientError.sessionMissing) {
            try await client.loadSessionImage(workspaceID: "ws-demo", sessionID: "session-tests",
                                              imageID: image.id.uuidString, variant: .original)
        }
    }

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
        try await client.send("  look again  ", runConfig: nil, turnID: "local-turn",
                              sessionID: "session-pr", workspaceID: "ws-demo")

        let conversation = try await client.conversation(sessionID: "session-pr", workspaceID: "ws-demo")
        #expect(conversation.turns.last?.id == "local-turn")
        #expect(conversation.turns.last?.author == .user)
        #expect(conversation.turns.last?.text == "look again")

        let sessions = try await client.sessions(workspaceID: "ws-demo")
        #expect(sessions.first?.id == "session-pr")
        #expect(sessions.first { $0.id == "session-pr" }?.preview == "look again")
    }

    @Test func runningSessionSendKeepsTheReplyActiveAndDeduplicatesRetries() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let before = try await client.conversation(sessionID: "session-tests", workspaceID: "ws-demo")
        #expect(try await client.sessions(workspaceID: "ws-demo").first { $0.id == "session-tests" }?.activity == .running)
        #expect(client.supportsTextSendingWhileRunning)
        for _ in 0..<2 {
            try await client.send("Steer the reply", runConfig: nil, turnID: "steer-turn",
                sessionID: "session-tests", workspaceID: "ws-demo")
        }
        let after = try await client.conversation(sessionID: "session-tests", workspaceID: "ws-demo")
        #expect(after.turns.count == before.turns.count + 1)
        #expect(after.turns.filter { $0.id == "steer-turn" }.count == 1)
        #expect(try await client.sessions(workspaceID: "ws-demo").first { $0.id == "session-tests" }?.activity == .running)
    }

    @Test(.timeLimit(.minutes(1))) func fixtureSubscriptionPublishesSteerAndStopAndEndsAtSignOut() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, streamsConversationUpdates: true)
        let stream = try await client.observeConversation(sessionID: "session-tests", workspaceID: "ws-demo")
        var updates = stream.makeAsyncIterator()
        #expect(try await updates.next()?.activity == .running)
        try await client.send("Guidance", runConfig: nil, turnID: "steer-turn",
            sessionID: "session-tests", workspaceID: "ws-demo")
        let steered = try #require(try await updates.next())
        #expect(steered.activity == .running)
        #expect(steered.conversation.turns.last?.id == "steer-turn")
        try await client.cancelSession(sessionID: "session-tests", workspaceID: "ws-demo")
        #expect(try await updates.next()?.activity == .idle)
        client.signOut()
        #expect(try await updates.next() == nil)
    }

    @Test func sendingMovesSessionAndProjectToRecentPosition() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()

        try await stageAndDeliverMessage(model, "  look again  ", sessionID: "session-pr")

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

        let sentChoice = try await stageAndDeliverMessage(model, "faster please", runConfig: choice, sessionID: "session-long")
        #expect(sentChoice == choice)
        #expect(try await latestRunConfig(model, sessionID: "session-long")?.reasoning?.value == "low")
    }

    @Test(arguments: [false, true])
    func unconfirmedSendRetryKeepsOriginalTurnAndConfiguration(hasChoice: Bool) async throws {
        let client = FixtureLodyClient(startsSignedIn: true, failSendOnce: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let initial = try #require(await latestRunConfig(model, sessionID: "session-long"))
        let firstChoice = hasChoice ? try #require(initial.choosing("low")) : nil
        let retryChoice = try #require(initial.choosing("high"))
        await #expect(throws: LodyClientError.deliveryUnconfirmed) {
            try await stageAndDeliverMessage(model, "retry me", runConfig: firstChoice, turnID: "original", sessionID: "session-long")
        }
        #expect(model.pendingTextSend(sessionID: "session-long")?.turnID == "original")
        #expect(retryChoice != firstChoice)
        #expect(model.retryOutgoingMessage(sessionID: "session-long"))
        let sentChoice = try await model.deliverOutgoingMessage(sessionID: "session-long")
        #expect(sentChoice == firstChoice)
        #expect(try await latestRunConfig(model, sessionID: "session-long")?.reasoning?.value ==
                (firstChoice?.value ?? initial.reasoning?.value))
        let conversation = try await model.conversation(sessionID: "session-long")
        #expect(conversation.turns.filter { $0.text == "retry me" }.map(\.id) == ["original"])
        #expect(model.pendingTextSend(sessionID: "session-long") == nil)
    }

    @Test func runConfigPatchDecodesBridgeProjection() throws {
        let json = """
        {"sessionID":"s","order":[],"changed":[],"permission":null,"activity":"idle","syncState":"live",
         "contextWindowUsage":{"size":258000,"used":217000},
         "lastMessageAt":123456,
         "runConfig":{"model":{"value":"flash","label":"Flash"},"reasoning":null,
           "editable":{"kind":"model","configOptionID":"model","options":[{"value":"flash","label":"Flash"}]}}}
        """
        let patch = try JSONDecoder().decode(ConversationPatch.self, from: Data(json.utf8))
        let update = try patch.applying(to: Conversation(sessionID: "s", turns: [], permission: nil))
        #expect(update.runConfig?.model?.label == "Flash")
        #expect(update.runConfig?.reasoning == nil)
        #expect(update.runConfig?.choosing("flash") == RunConfigChoice(configOptionID: "model", value: "flash"))
        #expect(update.lastMessageAt == 123456)
        #expect(update.contextWindowUsage?.used == 217_000)
        #expect(update.contextWindowUsage?.size == 258_000)
        #expect(update.contextWindowUsage?.usedFraction == 217.0 / 258.0)
    }

    @Test func sessionCacheUsagePatchesReplaceClearAndSurviveCacheCoding() throws {
        let initial = Conversation(sessionID: "s", turns: [ConversationTurn(id: "a", author: .agent, text: "Answer")], permission: nil)
        let json = """
        {"sessionID":"s","order":["a"],"changed":[],"permission":null,"activity":"idle","syncState":"live",
         "cacheUsage":{"inputTokens":60000,"cacheReadInputTokens":320000,"cacheCreationInputTokens":20000,"reportedTurns":18,"totalTurns":20}}
        """
        let patch = try JSONDecoder().decode(ConversationPatch.self, from: Data(json.utf8))
        let loaded = try patch.applying(to: initial).conversation
        let usage = try #require(loaded.cacheUsage)
        #expect(usage.isValid)
        #expect(usage.hitFraction == 0.8)
        #expect(loaded.turns == initial.turns)
        let cached = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(loaded))
        #expect(cached.cacheUsage == usage)
        let cleared = json.replacingOccurrences(of: #"{"inputTokens":60000,"cacheReadInputTokens":320000,"cacheCreationInputTokens":20000,"reportedTurns":18,"totalTurns":20}"#, with: "null")
        #expect(try JSONDecoder().decode(ConversationPatch.self, from: Data(cleared.utf8)).applying(to: loaded).conversation.cacheUsage == nil)
        let other = try JSONDecoder().decode(ConversationPatch.self, from: Data(json.replacingOccurrences(of: "\"s\"", with: "\"other\"").utf8))
        #expect(throws: LodyClientError.notConnected) { try other.applying(to: loaded) }
    }

    @Test func sessionCacheRateDistinguishesZeroInputFromZeroHits() {
        var usage = ConversationCacheUsage(inputTokens: 0, cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0, reportedTurns: 1, totalTurns: 2)
        #expect(usage.hitFraction == nil)
        usage.inputTokens = 100
        #expect(usage.hitFraction == 0)
        usage.cacheReadInputTokens = 300
        usage.cacheCreationInputTokens = 100
        #expect(usage.hitFraction == 0.6)
        usage.reportedTurns = 3
        #expect(!usage.isValid)
        #expect(usage.hitFraction == nil)
    }

    @Test func machineDirectoryPreservesDistinctRowsForCanonicalPathAliases() throws {
        let json = #"{"path":"/projects","parentPath":"/","truncated":false,"entries":[{"name":"app","absolutePath":"/projects/app","isSymlink":false},{"name":"app-link","absolutePath":"/projects/app","isSymlink":true},{"name":"here","absolutePath":"/projects","isSymlink":true}]}"#
        let directory = try JSONDecoder().decode(MachineDirectory.self, from: Data(json.utf8))
        #expect(directory.entries[0].absolutePath == directory.entries[1].absolutePath)
        #expect(Set(directory.entries.map(\.id)).count == 3)
        #expect(directory.entries[2].absolutePath == directory.path)
        let reloaded = try JSONDecoder().decode(MachineDirectory.self, from: Data(json.utf8))
        #expect(directory.entries.map(\.id) == reloaded.entries.map(\.id))
    }

    @Test func newSessionCanSelectUnusedMachineFolderAndKeepsTargetDuringRetry() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, failStartAndArchiveProjectOnce: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let template = try #require(model.newSessionTemplate(projectID: "local:machine-1:prism"))
        let directory = try #require(try await model.sessionProjects(templateSessionID: template.id, action: .browse).directory)
        #expect(directory.entries.map(\.name) == ["projects", "Documents"])
        let project = try #require(try await model.sessionProjects(templateSessionID: template.id,
            action: .select, path: "/Users/demo/projects/New App").project)
        let options = try await model.newSessionOptions(templateSessionID: template.id)
        await #expect(throws: LodyClientError.deliveryUnconfirmed) {
            try await stageAndDeliverSession(model, "Create in selected folder", selections: options.runConfig?.selections ?? [],
                projectID: project.id, templateSessionID: template.id)
        }
        let pending = try #require(model.pendingSessionStarts.first)
        #expect(pending.projectID == project.id)
        #expect(model.retryOutgoingMessage(sessionID: pending.id))
        try await model.deliverOutgoingMessage(sessionID: pending.id)
        let id = pending.id
        #expect(id == pending.id)
        let refreshed = try await client.sessions(workspaceID: "ws-demo")
        #expect(refreshed.first { $0.id == id }?.projectID == project.id)
        #expect(refreshed.first { $0.id == id }?.projectName == "New App")
        #expect(model.pendingSessionStarts.isEmpty)
        model.signOut()
        await #expect(throws: LodyClientError.notConnected) {
            try await model.sessionProjects(templateSessionID: template.id, action: .browse)
        }
    }

    @Test func newSessionStartsInTheTemplateProjectWithChosenConfig() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()
        #expect(model.newSessionTemplate(projectID: SessionProjectGroup.unassignedID) == nil)
        #expect(model.newSessionTemplate(projectID: "github:a/b") == nil)
        let template = try #require(model.newSessionTemplate(projectID: "local:machine-1:prism"))
        #expect(template.id == "session-pr")

        let inherited = try await model.newSessionOptions(templateSessionID: template.id)
        #expect(inherited.agentConfigID == "claude")
        #expect(inherited.providers.map(\.value) == ["claude", "codex"])
        #expect(inherited.runConfig?.reasoning == nil)

        let codex = try await model.newSessionOptions(templateSessionID: template.id, agentConfigID: "codex")
        var runConfig = try #require(codex.runConfig)
        runConfig.selectModel("gpt-5.4-mini")
        runConfig.selectReasoning("low")
        let sessionID = try await stageAndDeliverSession(model,
            "  Add a settings screen  ", agentConfigID: "codex", selections: runConfig.selections,
            projectID: "local:machine-1:prism", templateSessionID: template.id
        )

        #expect(model.sessions.first?.id == sessionID)
        #expect(model.sessions.first?.title == "Add a settings screen")
        #expect(SessionProjectGroup.make(from: model.sessions).first?.id == "local:machine-1:prism")
        let conversation = try await model.conversation(sessionID: sessionID)
        #expect(conversation.turns.map(\.text) == ["Add a settings screen"])
        let config = try #require(await latestRunConfig(model, sessionID: sessionID))
        #expect(config.model?.value == "gpt-5.4-mini")
        #expect(config.reasoning?.value == "low")

        await #expect(throws: LodyClientError.notConnected) {
            try await stageAndDeliverSession(model, "Wrong project", selections: [],
                                         projectID: "local:machine-1:kurage", templateSessionID: template.id)
        }
    }

    @Test func pendingCreationSurvivesArchivedTemplateAndFailedOptions() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, failStartAndArchiveProjectOnce: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let projectID = "local:machine-1:prism"
        let template = try #require(model.newSessionTemplate(projectID: projectID))
        let options = try await model.newSessionOptions(templateSessionID: template.id)
        await #expect(throws: LodyClientError.deliveryUnconfirmed) {
            try await stageAndDeliverSession(model, "Recover original task", selections: options.runConfig?.selections ?? [], projectID: projectID,
                                         templateSessionID: template.id)
        }
        let pending = try #require(model.pendingSessionStarts.first)
        await model.refreshSessions()
        #expect(model.newSessionTemplate(projectID: projectID) == nil)
        let configuration = NewSessionConfiguration()
        await configuration.load(providerID: nil) { provider in
            try await model.newSessionOptions(templateSessionID: template.id, agentConfigID: provider)
        }
        #expect(configuration.loadFailed)
        #expect(try model.restoreSessionStart(pending, projectName: "Prism") == pending.id)
        #expect(model.retryOutgoingMessage(sessionID: pending.id))
        try await model.deliverOutgoingMessage(sessionID: pending.id)
        #expect(model.pendingSessionStarts.isEmpty)
        let conversation = try await client.conversation(sessionID: pending.id, workspaceID: "ws-demo")
        #expect(conversation.turns.filter { $0.author == .user }.map(\.text) == ["Recover original task"])
        #expect(!model.retryOutgoingMessage(sessionID: pending.id))
    }

    @Test func signingOutClearsPendingCreationRecovery() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, failStartAndArchiveProjectOnce: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let template = try #require(model.newSessionTemplate(projectID: "local:machine-1:prism"))
        let options = try await model.newSessionOptions(templateSessionID: template.id)
        await #expect(throws: LodyClientError.deliveryUnconfirmed) {
            try await stageAndDeliverSession(model, "Pending", selections: options.runConfig?.selections ?? [], projectID: "local:machine-1:prism",
                                         templateSessionID: template.id)
        }
        #expect(model.pendingSessionStarts.count == 1)
        model.signOut()
        #expect(model.pendingSessionStarts.isEmpty)
        #expect(client.pendingSessionStarts(workspaceID: "ws-demo").isEmpty)
    }

    @Test func newSessionReasoningFollowsTheChosenModel() throws {
        let json = """
        {"machineName":"mac","agentConfigID":"cfg",
         "providers":[{"value":"claude","label":"Claude Code"},{"value":"cfg","label":"Codex"}],
         "runConfig":{
          "model":{"configOptionID":null,"value":"big","options":[
            {"value":"big","label":"Big","reasoning":[{"value":"low","label":"Low"},{"value":"high","label":"High"}]},
            {"value":"mini","label":"Mini","reasoning":[{"value":"low","label":"Low"}]}]},
          "reasoning":{"configOptionID":"reasoning_effort","value":"high","options":[]}}}
        """
        let options = try JSONDecoder().decode(NewSessionOptions.self, from: Data(json.utf8))
        var config = try #require(options.runConfig)
        #expect(config.selections == [
            RunConfigChoice(configOptionID: nil, value: "big"),
            RunConfigChoice(configOptionID: "reasoning_effort", value: "high"),
        ])
        let menu = options.menu(config)
        #expect(menu.sections.map(\.kind) == [.provider, .model, .reasoning])
        #expect(menu.sections.map(\.selection) == ["cfg", "big", "high"])
        #expect(menu.providerLabel == "Codex")
        #expect(menu.modelLabel == "Big")
        #expect(menu.reasoningLabel == "High")
        #expect(menu.accessibilitySummary == "Provider Codex, model Big, reasoning High")

        config.selectModel("mini")
        // High is not offered for Mini; show and send its concrete supported effort.
        #expect(config.selectedReasoning?.value == "low")
        #expect(config.selections == [RunConfigChoice(configOptionID: nil, value: "mini"),
                                     RunConfigChoice(configOptionID: "reasoning_effort", value: "low")])
        #expect(options.menu(config).sections.map(\.kind) == [.provider, .model, .reasoning])
        #expect(options.menu(config).modelLabel == "Mini")
        #expect(options.menu(config).reasoningLabel == "Low")
        var single = options
        single.providers = [SessionRunConfig.Value(value: "cfg", label: "Codex")]
        #expect(single.menu(config).sections.map(\.kind) == [.model, .reasoning])
        config.selectReasoning("unknown")
        #expect(config.selectedReasoning?.value == "low")
        config.selectModel("big")
        #expect(config.selectedReasoning?.value == "high")
        config.selectModel("unknown")
        #expect(config.model?.value == "big")
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
    @Test(arguments: [false, true])
    func refreshFailureAfterCancellationDoesNotPublishStatus(cancel: Bool) async {
        let client = DeferredSessionClient()
        let model = AppModel(client: client)
        await model.refreshWorkspaces()
        var requests = client.started.makeAsyncIterator()
        let refresh = Task { await model.refreshSessions(cancelWhenCallerCancels: true) }
        #expect(await requests.next() == "ws-a")

        // A manual caller can join a request originally owned by automatic refresh.
        let joined = AsyncStream<Void>.makeStream()
        var joins = joined.stream.makeAsyncIterator()
        let manual = Task {
            joined.continuation.yield(())
            await model.refreshSessions()
        }
        _ = await joins.next()
        if cancel { refresh.cancel() }
        client.fail("ws-a", with: NSError(domain: "WKErrorDomain", code: 5))
        await refresh.value
        await manual.value

        #expect(model.isSignedIn)
        #expect(!model.isRefreshingSessions)
        #expect(client.requestedWorkspaceIDs == ["ws-a"])
        if cancel {
            #expect(model.statusNote == nil)
        } else {
            #expect(model.statusNote == StatusNote(tone: .failure, text: "Could not refresh sessions."))
        }
    }

    @Test func visibleListRefreshesRepeatedlyAndStopsWhenCancelled() async {
        let client = DeferredSessionClient()
        let model = AppModel(client: client)
        await model.refreshWorkspaces()
        var requests = client.started.makeAsyncIterator()
        let automatic = Task { await model.refreshSessionsWhileVisible(interval: .milliseconds(1)) }
        #expect(await requests.next() == "ws-a")
        client.finish("ws-a", with: [Self.session("first")])
        #expect(await requests.next() == "ws-a")
        #expect(model.sessions.map(\.id) == ["first"])
        automatic.cancel()
        client.finish("ws-a", with: [Self.session("cancelled")])
        await automatic.value
        #expect(model.sessions.map(\.id) == ["first"])
        #expect(!model.isRefreshingSessions)
        #expect(client.requestedWorkspaceIDs == ["ws-a", "ws-a"])

        let returned = Task { await model.refreshSessionsWhileVisible(interval: .seconds(60)) }
        #expect(await requests.next() == "ws-a")
        client.finish("ws-a", with: [Self.session("returned")])
        await model.refreshSessions()
        #expect(model.sessions.map(\.id) == ["returned"])
        returned.cancel()
        await returned.value
    }

    @Test func stoppingAutomaticWaiterDoesNotCancelManualRefresh() async {
        let client = DeferredSessionClient()
        let model = AppModel(client: client)
        await model.refreshWorkspaces()
        var requests = client.started.makeAsyncIterator()
        let manual = Task { await model.refreshSessions() }
        #expect(await requests.next() == "ws-a")
        let automatic = Task { await model.refreshSessionsWhileVisible() }
        await Task.yield()
        automatic.cancel()
        client.finish("ws-a", with: [Self.session("manual")])
        await manual.value
        await automatic.value
        #expect(model.sessions.map(\.id) == ["manual"])
        #expect(client.requestedWorkspaceIDs == ["ws-a"])
    }

    @Test func sessionRefreshDoesNotWaitForWorkspaceDiscovery() async {
        let client = DeferredSessionClient()
        let model = AppModel(client: client)
        await model.refreshWorkspaces()
        client.defersWorkspaces = true
        var requests = client.started.makeAsyncIterator()
        var discoveries = client.workspaceStarted.stream.makeAsyncIterator()
        let refresh = Task { await model.refreshContent() }
        #expect(await requests.next() == "ws-a")
        _ = await discoveries.next()
        client.finish("ws-a", with: [Self.session("fresh")])
        // Join the same list request; workspace discovery is still suspended.
        await model.refreshSessions()
        #expect(model.sessions.map(\.id) == ["fresh"])
        client.workspaceContinuation?.resume(returning: [WorkspaceSummary(id: "ws-a", name: "A", slug: "a")])
        await refresh.value
        #expect(client.requestedWorkspaceIDs == ["ws-a"])
    }

    @Test func discoveryChangingWorkspaceLoadsReplacementAndRejectsOldRows() async {
        let client = DeferredSessionClient()
        let model = AppModel(client: client)
        await model.refreshWorkspaces()
        client.defersWorkspaces = true
        var requests = client.started.makeAsyncIterator()
        var discoveries = client.workspaceStarted.stream.makeAsyncIterator()
        let refresh = Task { await model.refreshContent() }
        #expect(await requests.next() == "ws-a")
        _ = await discoveries.next()
        client.workspaceContinuation?.resume(returning: [WorkspaceSummary(id: "ws-b", name: "B", slug: "b")])
        client.finish("ws-a", with: [Self.session("stale")])
        #expect(await requests.next() == "ws-b")
        #expect(model.sessions.isEmpty)
        client.finish("ws-b", with: [Self.session("replacement")])
        await refresh.value
        #expect(model.selectedWorkspaceID == "ws-b")
        #expect(model.sessions.map(\.id) == ["replacement"])
    }

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

    @Test func receiptRestartsInterruptedRefreshAndRejectsItsStaleResult() async throws {
        let client = DeferredSessionClient()
        var old = Self.session("old")
        old.lastMessageAt = 100
        client.cachedSession = SessionCache(account: client.account!, workspaces: [
            WorkspaceSummary(id: "ws-a", name: "A", slug: "a")
        ], selectedWorkspaceID: "ws-a", sessionsByWorkspace: ["ws-a": [old]])
        let model = AppModel(client: client)
        var requests = client.started.makeAsyncIterator()
        let initial = Task { await model.refreshSessions() }
        #expect(await requests.next() == "ws-a")
        let receipt = Task {
            try await model.markSessionRead(sessionID: "old", lastMessageAt: 100,
                                            workspaceGeneration: model.workspaceGeneration)
        }
        #expect(await requests.next() == "ws-a")
        #expect(model.sessions.first?.lastReadAt == 100)
        client.finishNext("ws-a", with: [Self.session("stale")])
        await initial.value
        #expect(model.sessions.map(\.id) == ["old"])
        #expect(model.isRefreshingSessions)
        old.lastReadAt = 100
        client.finishNext("ws-a", with: [Self.session("new"), old])
        try await receipt.value
        #expect(model.sessions.map(\.id) == ["new", "old"])
        #expect(model.sessions.last?.lastReadAt == 100)
        #expect(!model.isRefreshingSessions)
        try await model.markSessionRead(sessionID: "old", lastMessageAt: 200,
                                        workspaceGeneration: model.workspaceGeneration)
        #expect(client.requestedWorkspaceIDs == ["ws-a", "ws-a"])
    }

    @Test func streamedActivityReordersRecentProjectsAndCache() async throws {
        let client = DeferredSessionClient()
        var recent = Self.session("recent")
        recent.lastActivityAt = 400
        recent.projectID = "project-a"
        var middle = Self.session("middle")
        middle.lastMessageAt = 200
        middle.projectID = "project-c"
        var old = Self.session("old")
        old.lastMessageAt = 100
        old.projectID = "project-b"
        client.cachedSession = SessionCache(account: client.account!, workspaces: [
            WorkspaceSummary(id: "ws-a", name: "A", slug: "a")
        ], selectedWorkspaceID: "ws-a", sessionsByWorkspace: ["ws-a": [recent, middle, old]])
        let model = AppModel(client: client)
        var subscriptions = client.observationsStarted.makeAsyncIterator()
        let observing = Task { try await model.observeConversation(sessionID: "old") { _ in } }
        #expect(await subscriptions.next() == "ws-a")
        client.observation?.yield(ConversationUpdate(
            conversation: Conversation(sessionID: "old", turns: [], permission: nil),
            activity: .idle, syncState: .live, lastMessageAt: 300))
        client.observation?.finish()
        try await observing.value
        #expect(model.sessions.map(\.id) == ["recent", "old", "middle"])
        #expect(SessionProjectGroup.make(from: model.sessions).map(\.id) == ["project-a", "project-b", "project-c"])
        #expect(client.cachedSession?.sessionsByWorkspace["ws-a"] == model.sessions)
    }

    @Test func messageTimeNeverRegressesAcrossRefreshAndObservation() async throws {
        let client = DeferredSessionClient()
        var session = Self.session("chat")
        session.lastMessageAt = 100
        client.cachedSession = SessionCache(account: client.account!, workspaces: [
            WorkspaceSummary(id: "ws-a", name: "A", slug: "a")
        ], selectedWorkspaceID: "ws-a", sessionsByWorkspace: ["ws-a": [session]])
        let model = AppModel(client: client)
        var requests = client.started.makeAsyncIterator()
        let refreshing = Task { await model.refreshSessions() }
        #expect(await requests.next() == "ws-a")
        var subscriptions = client.observationsStarted.makeAsyncIterator()
        let (received, signal) = AsyncStream<Void>.makeStream()
        var updates = received.makeAsyncIterator()
        let observing = Task { try await model.observeConversation(sessionID: "chat") { _ in signal.yield(()) } }
        #expect(await subscriptions.next() == "ws-a")
        func publish(_ timestamp: Double) {
            client.observation?.yield(ConversationUpdate(
                conversation: Conversation(sessionID: "chat", turns: [], permission: nil),
                activity: .idle, syncState: .live, lastMessageAt: timestamp))
        }
        publish(300)
        _ = await updates.next()
        session.lastMessageAt = 200
        session.title = "Fresh title"
        var other = Self.session("other")
        other.lastMessageAt = 250
        client.finishNext("ws-a", with: [other, session])
        await refreshing.value
        #expect(model.sessions.map(\.id) == ["chat", "other"])
        #expect(model.sessions.first?.lastMessageAt == 300)
        #expect(model.sessions.first?.title == "Fresh title")
        for timestamp in [200.0, Double.nan, Double.infinity] {
            publish(timestamp)
            _ = await updates.next()
            #expect(model.sessions.first?.lastMessageAt == 300)
        }
        try await model.markSessionRead(sessionID: "chat", lastMessageAt: 200,
                                        workspaceGeneration: model.workspaceGeneration)
        #expect(model.sessions.first?.isUnread == true)
        #expect(client.cachedSession?.sessionsByWorkspace["ws-a"]?.first?.lastMessageAt == 300)
        client.observation?.finish()
        try await observing.value
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
    var cachedSession: SessionCache?
    func saveSessionCache(_ cache: SessionCache) { cachedSession = cache }
    var supportsSessionMetadataEditing: Bool { true }
    func updateSessionMetadata(_ change: SessionMetadataChange, sessionID: String, workspaceID: String) async throws {}
    func finishNext(_ workspaceID: String, with sessions: [SessionSummary]) {
        pending[workspaceID]?.removeFirst().resume(returning: sessions)
    }
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
    var defersWorkspaces = false
    let workspaceStarted = AsyncStream<Void>.makeStream()
    var workspaceContinuation: CheckedContinuation<[WorkspaceSummary], Error>?

    func workspaces() async throws -> [WorkspaceSummary] {
        if defersWorkspaces {
            return try await withCheckedThrowingContinuation { continuation in
                workspaceContinuation = continuation
                workspaceStarted.continuation.yield(())
            }
        }
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

    func fail(_ workspaceID: String, with error: Error) {
        for continuation in pending.removeValue(forKey: workspaceID) ?? [] {
            continuation.resume(throwing: error)
        }
    }

    func conversation(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> Conversation {
        if defersConversation {
            return try await withCheckedThrowingContinuation { continuation in
                conversationContinuation = continuation
                conversationStarted.continuation.yield(workspaceID)
            }
        }
        if let conversationResponse { return conversationResponse }
        throw LodyClientError.notConnected
    }
    var defersConversation = false
    var conversationResponse: Conversation?
    let conversationStarted = AsyncStream<String>.makeStream()
    var conversationContinuation: CheckedContinuation<Conversation, Error>?

    func finishConversation(_ conversation: Conversation) {
        conversationContinuation?.resume(returning: conversation)
        conversationContinuation = nil
    }
    @discardableResult
    func send(
        _ text: String, attachments: [ComposerAttachment] = [],
        runConfig: RunConfigChoice?,
        turnID: ConversationTurn.ID,
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
struct ConversationPreviewTests {
    private func model(client: DeferredSessionClient) throws -> AppModel {
        client.cachedSession = SessionCache(account: try #require(client.account), workspaces: [
            WorkspaceSummary(id: "ws-a", name: "A", slug: "a"),
            WorkspaceSummary(id: "ws-b", name: "B", slug: "b"),
        ], selectedWorkspaceID: "ws-a", sessionsByWorkspace: [:])
        return AppModel(client: client)
    }

    @Test(arguments: [false, true])
    func previewReadsLeaveColdAndWarmCachesUnchanged(hasCache: Bool) async throws {
        let client = DeferredSessionClient()
        let model = try model(client: client)
        let original = Conversation(sessionID: "s", turns: [ConversationTurn(id: "a", author: .agent, text: "Original")])
        client.conversationResponse = original
        if hasCache { _ = try await model.conversation(sessionID: "s") }
        let cached = model.cachedConversation(sessionID: "s")
        let loaded = Conversation(sessionID: "s", turns: [ConversationTurn(id: "a", author: .agent, text: "New snapshot")])
        client.conversationResponse = loaded

        #expect(try await model.conversationPreview(sessionID: "s") == loaded)
        #expect(model.cachedConversation(sessionID: "s") == cached)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func latePreviewReadUsesLiveGrowthAndDeletions(hasCache: Bool, deletesTurns: Bool) async throws {
        let client = DeferredSessionClient()
        let model = try model(client: client)
        let original = Conversation(sessionID: "s", turns: [ConversationTurn(id: "a", author: .agent, text: "Partial")])
        let latest = Conversation(sessionID: "s", turns: deletesTurns ? [] : [
            ConversationTurn(id: "a", author: .agent, text: "Partial output has grown"),
            ConversationTurn(id: "b", author: .agent, text: "Another turn"),
        ])
        let (received, signal) = AsyncStream<Void>.makeStream()
        var updates = received.makeAsyncIterator()
        var subscriptions = client.observationsStarted.makeAsyncIterator()
        let observing = Task { try await model.observeConversation(sessionID: "s") { _ in signal.yield(()) } }
        defer { client.observation?.finish(); observing.cancel() }
        #expect(await subscriptions.next() == "ws-a")
        if hasCache {
            client.observation?.yield(ConversationUpdate(conversation: original, activity: .running, syncState: .live))
            _ = await updates.next()
        }

        client.defersConversation = true
        var reads = client.conversationStarted.stream.makeAsyncIterator()
        let preview = Task { try await model.conversationPreview(sessionID: "s") }
        #expect(await reads.next() == "ws-a")
        // Publish and consume a newer update before releasing the earlier one-shot result.
        client.observation?.yield(ConversationUpdate(conversation: latest, activity: .running, syncState: .live))
        _ = await updates.next()
        client.finishConversation(original)

        #expect(try await preview.value == latest)
        #expect(model.cachedConversation(sessionID: "s") == latest)
        client.observation?.finish()
        try await observing.value
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["cancel", "workspace", "workspace-round-trip", "sign-out"])
    func latePreviewReadsRejectCancelledOrObsoleteScopes(change: String) async throws {
        let client = DeferredSessionClient()
        let model = try model(client: client)
        client.defersConversation = true
        var reads = client.conversationStarted.stream.makeAsyncIterator()
        let preview = Task { try await model.conversationPreview(sessionID: "s") }
        #expect(await reads.next() == "ws-a")

        switch change {
        case "cancel": preview.cancel()
        case "sign-out": model.signOut()
        default:
            var requests = client.started.makeAsyncIterator()
            for workspaceID in change == "workspace-round-trip" ? ["ws-b", "ws-a"] : ["ws-b"] {
                let switching = Task { await model.selectWorkspace(workspaceID) }
                #expect(await requests.next() == workspaceID)
                client.finish(workspaceID, with: [])
                await switching.value
            }
        }
        // This test client ignores cancellation, exposing the model's own late-result guard.
        client.finishConversation(Conversation(sessionID: "s", turns: [
            ConversationTurn(id: "a", author: .agent, text: "Obsolete"),
        ]))
        await #expect(throws: CancellationError.self) { try await preview.value }
        #expect(model.cachedConversation(sessionID: "s") == nil)
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
        ], permission: nil, cacheUsage: ConversationCacheUsage(inputTokens: 100, cacheReadInputTokens: 300,
            cacheCreationInputTokens: 100, reportedTurns: 1, totalTurns: 2)), activity: .running, syncState: .live)
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

@MainActor
struct NewSessionConfigurationTests {
    private func options(_ id: String) -> NewSessionOptions {
        NewSessionOptions(machineName: "mac", agentConfigID: id, providers: [
            .init(value: "claude", label: "Claude Code"), .init(value: "codex", label: "Codex"),
        ], runConfig: id == "codex" ? .fixture : .fixtureModelOnly)
    }

    @Test func staleOptionsStayUsableAndRefreshPreservesEdits() async {
        let configuration = NewSessionConfiguration()
        let (events, continuation) = AsyncStream<Void>.makeStream()
        var response: CheckedContinuation<NewSessionOptions, Never>?
        let load = Task {
            await configuration.load(providerID: nil, refresh: { id in
                #expect(id == "codex")
                return await withCheckedContinuation { pending in
                    response = pending
                    continuation.yield(())
                }
            }) { id in
                var loaded = options(id ?? "codex")
                loaded.needsRefresh = id == nil
                return loaded
            }
        }
        var iterator = events.makeAsyncIterator()
        await iterator.next()
        #expect(configuration.options?.agentConfigID == "codex")
        #expect(!configuration.isLoading)
        #expect(!configuration.loadFailed)
        configuration.selectReasoning("low")
        var fresh = options("codex")
        fresh.runConfig?.selectReasoning("medium")
        if let index = fresh.runConfig?.model?.options.firstIndex(where: { $0.value == fresh.runConfig?.model?.value }) {
            fresh.runConfig?.model?.options[index].label = "Updated model"
        }
        response?.resume(returning: fresh)
        await load.value
        #expect(configuration.options?.needsRefresh != true)
        #expect(configuration.runConfig?.selectedReasoning?.value == "low")
        #expect(configuration.runConfig?.selectedModel?.label == "Updated model")
        continuation.finish()
    }

    @Test func failedRefreshKeepsCachedOptionsWithoutBlockingCreation() async {
        let configuration = NewSessionConfiguration()
        await configuration.load(providerID: nil, refresh: { _ in throw LodyClientError.notConnected }) { id in
            var loaded = options(id ?? "codex")
            loaded.needsRefresh = id == nil
            return loaded
        }
        #expect(configuration.options?.agentConfigID == "codex")
        #expect(configuration.runConfig != nil)
        #expect(!configuration.isLoading)
        #expect(!configuration.loadFailed)
    }

    @Test func lateBackgroundRefreshCannotReplaceAnotherProvider() async {
        let configuration = NewSessionConfiguration()
        let (events, continuation) = AsyncStream<Void>.makeStream()
        var response: CheckedContinuation<NewSessionOptions, Never>?
        // Prefetch both providers before exercising a refresh of cached options.
        await configuration.load(providerID: nil) { id in
            var loaded = options(id ?? "claude")
            loaded.needsRefresh = id == "codex"
            return loaded
        }
        configuration.selectProvider("codex")
        let load = Task {
            await configuration.load(providerID: "codex", refresh: { _ in
                await withCheckedContinuation { pending in
                    response = pending
                    continuation.yield(())
                }
            }) { id in options(id ?? "codex") }
        }
        var iterator = events.makeAsyncIterator()
        await iterator.next()
        configuration.selectProvider("claude")
        response?.resume(returning: options("codex"))
        await load.value
        #expect(configuration.options?.agentConfigID == "claude")
        #expect(!configuration.isLoading)
        continuation.finish()
    }

    @Test func prefetchedProvidersSwitchLocallyAndRetainSelections() async {
        let configuration = NewSessionConfiguration()
        var requests: [String] = []
        await configuration.load(providerID: nil) { id in
            requests.append(id ?? "default")
            return options(id ?? "claude")
        }
        #expect(requests == ["default", "codex"])
        #expect(configuration.selectProvider("codex"))
        #expect(!configuration.isLoading)
        #expect(configuration.runConfig?.selectedReasoning?.value == "high")
        configuration.selectReasoning("low")
        #expect(configuration.selectProvider("claude"))
        #expect(configuration.selectProvider("codex"))
        #expect(configuration.runConfig?.selectedReasoning?.value == "low")
        await configuration.load(providerID: "codex") { _ in
            Issue.record("A cached provider must not make another request")
            return options("codex")
        }
        #expect(configuration.runConfig?.selectedReasoning?.value == "low")
    }

    @Test func failedPrefetchShowsPendingProviderWithoutOldModelsAndCanRetry() async {
        let configuration = NewSessionConfiguration()
        await configuration.load(providerID: nil) { id in
            if id == "codex" { throw LodyClientError.notConnected }
            return options("claude")
        }
        #expect(!configuration.loadFailed)
        #expect(configuration.selectProvider("codex"))
        #expect(configuration.menu?.providerLabel == "Codex")
        #expect(configuration.menu?.modelLabel == nil)
        #expect(configuration.isLoading)
        configuration.selectModel("opus")
        #expect(configuration.runConfig == nil)
        await configuration.load(providerID: "codex") { _ in throw LodyClientError.notConnected }
        #expect(configuration.loadFailed)
        #expect(configuration.selectProvider("codex"))
        await configuration.load(providerID: "codex") { _ in options("codex") }
        #expect(!configuration.isLoading)
        #expect(!configuration.loadFailed)
    }

    @Test func selectingAProviderReusesItsPendingPrefetch() async {
        let configuration = NewSessionConfiguration()
        let (events, eventsContinuation) = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<NewSessionOptions, Never>?
        let preload = Task {
            await configuration.load(providerID: nil) { id in
                guard id == "codex" else { return options("claude") }
                return await withCheckedContinuation { continuation in
                    pending = continuation
                    eventsContinuation.yield(())
                }
            }
        }
        var iterator = events.makeAsyncIterator()
        await iterator.next()
        configuration.selectProvider("codex")
        preload.cancel()
        Task { pending?.resume(returning: options("codex")) }
        await configuration.load(providerID: "codex") { _ in
            Issue.record("Selecting a pending provider must reuse its prefetch")
            return options("codex")
        }
        await preload.value
        #expect(configuration.options?.agentConfigID == "codex")
        #expect(!configuration.isLoading)
        eventsContinuation.finish()
    }

    @Test func lateProviderResponseCannotReplaceNewerSelection() async {
        let configuration = NewSessionConfiguration()
        await configuration.load(providerID: nil) { id in
            if id == "codex" { throw LodyClientError.notConnected }
            return options("claude")
        }
        configuration.selectProvider("codex")
        let (events, eventsContinuation) = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<NewSessionOptions, Never>?
        let load = Task {
            await configuration.load(providerID: "codex") { _ in
                await withCheckedContinuation { continuation in
                    pending = continuation
                    eventsContinuation.yield(())
                }
            }
        }
        var iterator = events.makeAsyncIterator()
        await iterator.next()
        configuration.selectProvider("claude")
        pending?.resume(returning: options("codex"))
        await load.value
        #expect(configuration.options?.agentConfigID == "claude")
        #expect(configuration.runConfig?.selectedModel?.label == "Sonnet")
        #expect(!configuration.isLoading)
        eventsContinuation.finish()
    }
}

@MainActor
struct ReasoningPresentationTests {
    @Test func unorderedProviderEffortsIncreaseFromLeftToRight() {
        let values = ["medium", "high", "xhigh", "low"]
        let section = RunConfigMenu.Section(kind: .reasoning,
            options: values.map { .init(value: $0, label: $0.capitalized) }, selection: "low")
        #expect(section.options.map(\.value) == ["low", "medium", "high", "xhigh"])
        var menu = RunConfigMenu(accessibilitySummary: "Grok", sections: [section])
        #expect(menu.reasoningProgress == 1.0 / 4.0)
        menu.sections[0].selection = "high"
        #expect(menu.reasoningProgress == 3.0 / 4.0)
        menu.sections[0].selection = "xhigh"
        #expect(menu.reasoningProgress == 1)
    }

    @Test(arguments: ["none", "off", "disabled"])
    func actualOffOptionOccupiesZeroWithoutAnExtraTick(off: String) {
        let section = RunConfigMenu.Section(kind: .reasoning,
            options: [off, "low", "high"].map { .init(value: $0, label: $0) }, selection: off)
        #expect(section.reasoningZeroOffset == 0)
        #expect(section.reasoningTickCount == 3)
        var menu = RunConfigMenu(accessibilitySummary: "Reasoning", sections: [section])
        #expect(menu.reasoningProgress == 0)
        menu.sections[0].selection = "low"
        #expect(menu.reasoningProgress == 0.5)
    }

    @Test func missingOrUnavailableReasoningDisplaysFullGauge() {
        #expect(RunConfigMenu(accessibilitySummary: "Model", sections: []).reasoningProgress == 1)
        let section = RunConfigMenu.Section(kind: .reasoning,
            options: [.init(value: "high", label: "High")], selection: "high")
        #expect(RunConfigMenu(accessibilitySummary: "Model", sections: [section]).reasoningProgress == 1)
    }

    @Test func aliasesAndOpaqueValuesRetainProtocolValues() {
        let section = RunConfigMenu.Section(kind: .reasoning, options: [
            .init(value: "custom", label: "Automatic"),
            .init(value: "opaque-high", label: "Extra High"),
            .init(value: "low", label: "Low"),
            .init(value: "max", label: "Max")
        ], selection: "opaque-high")
        #expect(section.options.map(\.value) == ["custom", "low", "opaque-high", "max"])
        #expect(section.selection == "opaque-high")
        let models = RunConfigMenu.Section(kind: .model, options: section.options.reversed(), selection: "low")
        #expect(models.options.map(\.value) == ["max", "opaque-high", "low", "custom"])
    }
}
