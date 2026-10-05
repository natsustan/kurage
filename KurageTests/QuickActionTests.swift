import Foundation
import Testing
@testable import Kurage

@MainActor
struct QuickActionTests {
    @Test func nativeTabRequestCarriesItsTitleIDsAndFirstTurnChoicesToJavaScript() throws {
        let choices = [RunConfigChoice(configOptionID: nil, value: "gpt-5.4-mini"),
                       RunConfigChoice(configOptionID: "reasoning_effort", value: "low")]
        let request = SessionTabStart(text: QuickAction.commit.prompt, selections: choices,
                                      agentConfigID: "codex", title: "Commit")
        let value = try request.bridgeValue(attachments: [], parentSessionID: "root", userID: "user")
        let json = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: value)) as? [String: Any]
        #expect(json?["title"] as? String == "Commit")
        #expect(json?["templateSessionID"] as? String == "root")
        #expect(json?["parentSessionID"] as? String == "root")
        #expect(json?["sessionID"] as? String == request.sessionID)
        #expect(json?["turnID"] as? String == request.turnID)
        #expect(json?["agentConfigID"] as? String == "codex")
        #expect(json?["text"] as? String == QuickAction.commit.prompt)
        let selections = try #require(json?["selections"] as? [[String: Any]])
        #expect(selections.map { $0["value"] as? String } == ["gpt-5.4-mini", "low"])
        #expect(selections[0]["configOptionID"] is NSNull)
        #expect(selections[1]["configOptionID"] as? String == "reasoning_effort")
        let ordinary = try SessionTabStart(text: "Continue").bridgeValue(attachments: [], parentSessionID: "root", userID: "user")
        #expect(ordinary["title"] is NSNull)
    }

    @Test func taskUsesANamedTabAndIndependentModelWithoutChangingParentHistory() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let rootID = "session-pr"
        let before = try await client.conversation(sessionID: rootID, workspaceID: "ws-demo")
        let options = try await model.newSessionOptions(templateSessionID: rootID, agentConfigID: "codex", isTab: true)
        var config = try #require(options.runConfig)
        config.selectModel("gpt-5.4-mini")
        config.selectReasoning("low")
        let id = try model.stageQuickAction(.createBranchAndCommit, rootID: rootID, options: options,
            runConfig: config, workspaceGeneration: model.workspaceGeneration)
        #expect(model.sessionSummary(id)?.title == "Create Branch & Commit")
        #expect(model.sessionSummary(id)?.projectID == model.sessionSummary(rootID)?.projectID)
        #expect(model.sessionSummary(id)?.parentSessionID == rootID)
        #expect(!model.sessions.contains { $0.id == id })
        #expect(!model.shouldFocusSessionStartComposer(sessionID: id))
        try await model.deliverOutgoingMessage(sessionID: id)
        try await model.observeConversation(sessionID: id, rootSessionID: rootID) { update in
            #expect(update.conversation.turns.first?.text == QuickAction.createBranchAndCommit.prompt)
            #expect(update.runConfig?.model?.value == "gpt-5.4-mini")
            #expect(update.runConfig?.reasoning?.value == "low")
        }
        #expect(try await client.conversation(sessionID: rootID, workspaceID: "ws-demo") == before)
    }

    @Test func uncertainTaskRetryKeepsItsTabTurnTitleAndFirstConfiguration() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, failTabStartOnce: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let options = try await model.newSessionOptions(templateSessionID: "session-pr", agentConfigID: "codex", isTab: true)
        var config = try #require(options.runConfig)
        config.selectModel("gpt-5.4-mini")
        config.selectReasoning("low")
        let id = try model.stageQuickAction(.commit, rootID: "session-pr", options: options,
            runConfig: config, workspaceGeneration: model.workspaceGeneration)
        let pending = try #require(model.pendingSessionTab(rootID: "session-pr"))
        await #expect(throws: LodyClientError.deliveryUnconfirmed) { try await model.deliverOutgoingMessage(sessionID: id) }
        #expect(model.quickActionBlockingFailure(rootID: "session-pr") == .pending)
        #expect(model.retryOutgoingMessage(sessionID: id))
        try await model.deliverOutgoingMessage(sessionID: id)
        let conversation = try await client.conversation(sessionID: id, workspaceID: "ws-demo")
        #expect(conversation.turns.map(\.id) == [pending.turnID])
        #expect(model.sessionSummary(id)?.title == "Commit")
        try await model.observeConversation(sessionID: id, rootSessionID: "session-pr") { update in
            #expect(update.runConfig?.model?.value == "gpt-5.4-mini")
            #expect(update.runConfig?.reasoning?.value == "low")
        }
    }

    @Test func busyProjectsAndStaleWorkspaceCannotStageGitActions() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, workspaceSummaries: [
            WorkspaceSummary(id: "ws-demo", name: "Demo", slug: "demo"),
            WorkspaceSummary(id: "ws-studio", name: "Studio", slug: "studio"),
        ])
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let options = try await model.newSessionOptions(templateSessionID: "session-long", isTab: true)
        let generation = model.workspaceGeneration
        #expect(model.quickActionBlockingFailure(rootID: "session-long") == .busy)
        #expect(throws: QuickActionFailure.busy) {
            try model.stageQuickAction(.commit, rootID: "session-long", options: options,
                                      runConfig: options.runConfig, workspaceGeneration: generation)
        }
        #expect(model.pendingSessionTab(rootID: "session-long") == nil)
        await model.selectWorkspace("ws-studio")
        #expect(throws: CancellationError.self) {
            try model.stageQuickAction(.commit, rootID: "session-long", options: options,
                                      runConfig: options.runConfig, workspaceGeneration: generation)
        }
    }

    @Test func preferencesPersistAcrossLaunchesShareOneMachineAndRespectScopes() async throws {
        let suite = "QuickActionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await model.adoptExistingAccount()
        let preference = QuickActionPreference(agentConfigID: "codex", modelID: "gpt-5.4-mini", reasoning: "low")
        model.saveQuickActionPreference(preference, rootID: "session-pr", workspaceGeneration: model.workspaceGeneration)
        #expect(model.quickActionPreference(rootID: "session-long") == preference)
        let relaunched = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await relaunched.adoptExistingAccount()
        #expect(relaunched.quickActionPreference(rootID: "session-pr") == preference)
        let account = try #require(model.account)
        let key = QuickActionPreference.storageKey(account: account, workspaceID: "ws-demo", machineID: "machine-1")
        #expect(key != QuickActionPreference.storageKey(account: account, workspaceID: "other", machineID: "machine-1"))
        #expect(key != QuickActionPreference.storageKey(account: account, workspaceID: "ws-demo", machineID: "other"))
        #expect(key != QuickActionPreference.storageKey(account: Account(email: "other@example.test", id: "other"),
                                                       workspaceID: "ws-demo", machineID: "machine-1"))
        model.signOut()
        #expect(model.quickActionPreference(rootID: "session-pr") == nil)
        model.saveQuickActionPreference(nil, rootID: "session-pr", workspaceGeneration: model.workspaceGeneration)
        #expect(relaunched.quickActionPreference(rootID: "session-pr") == preference)
        relaunched.saveQuickActionPreference(nil, rootID: "session-pr", workspaceGeneration: relaunched.workspaceGeneration)
        #expect(relaunched.quickActionPreference(rootID: "session-pr") == nil)
    }

    @Test func savedConfigurationIsCheckedAgainstCurrentModelCapabilities() throws {
        var config: NewSessionRunConfig? = .fixture
        let valid = QuickActionPreference(agentConfigID: "codex", modelID: "gpt-5.4-mini", reasoning: "low")
        try valid.apply(to: &config)
        #expect(config?.model?.value == "gpt-5.4-mini")
        #expect(config?.selectedReasoning?.value == "low")
        #expect(throws: QuickActionFailure.savedReasoningUnavailable) {
            try QuickActionPreference(agentConfigID: "codex", modelID: "gpt-5.4-mini", reasoning: "high").apply(to: &config)
        }
        #expect(throws: QuickActionFailure.savedModelUnavailable) {
            try QuickActionPreference(agentConfigID: "codex", modelID: "removed").apply(to: &config)
        }
    }
}
