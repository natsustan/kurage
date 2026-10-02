import Foundation
import Testing
@testable import Kurage

@MainActor
struct SessionTabsTests {
    @Test func composerDraftsAreIsolatedBySessionAndWorkspaceGeneration() {
        let store = ConversationDraftStore()
        store[sessionID: "root", workspaceGeneration: 1].text = "First workspace draft"
        store[sessionID: "tab", workspaceGeneration: 1].text = "Separate tab draft"
        store[sessionID: "root", workspaceGeneration: 1].banner = "Unconfirmed send"
        #expect(store[sessionID: "root", workspaceGeneration: 2].text.isEmpty)
        #expect(store[sessionID: "root", workspaceGeneration: 2].banner == nil)
        store[sessionID: "root", workspaceGeneration: 2].text = "Other workspace draft"
        #expect(store[sessionID: "root", workspaceGeneration: 1].text == "First workspace draft")
        #expect(store[sessionID: "tab", workspaceGeneration: 1].text == "Separate tab draft")
        #expect(store[sessionID: "root", workspaceGeneration: 2].text == "Other workspace draft")
    }

    @Test func tabCreationReadingClosingAndSendingRemainSeparateFromRoot() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let rootID = "session-long"
        let before = try await client.conversation(sessionID: rootID, workspaceID: "ws-demo")
        let tabID = try await stageAndDeliverTab(model, "A separate conversation", rootID: rootID)
        #expect(!model.sessions.contains { $0.id == tabID })
        #expect(model.sessionSummary(tabID)?.parentSessionID == rootID)
        #expect(model.pendingSessionTab(rootID: rootID) == nil)
        try await model.observeConversation(sessionID: tabID, rootSessionID: rootID) { update in
            #expect(update.sessionTabs?.map(\.id) == [rootID, tabID])
            #expect(update.conversation.turns.map(\.text) == ["A separate conversation"])
            #expect(update.conversation.subtasks?.isEmpty != false)
        }
        try await stageAndDeliverMessage(model, "Only in this tab", sessionID: tabID)
        try await model.updateSessionMetadata(.tabClosed(true), sessionID: tabID)
        #expect(model.sessionTabs(rootID: rootID).first { $0.id == tabID }?.isTabClosed == true)
        let closed = try await client.conversation(sessionID: tabID, workspaceID: "ws-demo")
        #expect(closed.turns.contains { $0.text == "Only in this tab" })
        try await model.updateSessionMetadata(.tabClosed(false), sessionID: tabID)
        #expect(model.sessionTabs(rootID: rootID).first { $0.id == tabID }?.isTabClosed == false)
        #expect(try await client.conversation(sessionID: rootID, workspaceID: "ws-demo") == before)
        model.signOut()
        #expect(model.sessionTabs(rootID: rootID).isEmpty)
        #expect(model.sessionSummary(tabID) == nil)
    }

    @Test func uncertainCreationRetriesSameSessionAndFirstTurn() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, failTabStartOnce: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        await #expect(throws: LodyClientError.deliveryUnconfirmed) {
            try await stageAndDeliverTab(model, "Original", rootID: "session-long")
        }
        let pending = try #require(model.pendingSessionTab(rootID: "session-long"))
        await #expect(throws: LodyClientError.previousSendPending("Original")) {
            try await stageAndDeliverTab(model, "Changed", rootID: "session-long")
        }
        #expect(model.pendingSessionTab(rootID: "session-long") == pending)
        #expect(model.retryOutgoingMessage(sessionID: pending.sessionID))
        try await model.deliverOutgoingMessage(sessionID: pending.sessionID)
        let id = pending.sessionID
        #expect(id == pending.sessionID)
        #expect(model.pendingSessionTab(rootID: "session-long") == nil)
        let conversation = try await client.conversation(sessionID: id, workspaceID: "ws-demo")
        #expect(conversation.turns.map(\.id) == [pending.turnID])
        #expect(!model.sessions.contains { $0.id == id })
    }

    @Test func firstTurnModelChoiceIsAppliedAndRetryKeepsOriginalSelection() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, failTabStartOnce: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let options = try await model.newSessionOptions(templateSessionID: "session-long", isTab: true)
        #expect(options.providers.count == 2)
        var config = try #require(options.runConfig)
        let different = try #require(config.model?.options.last)
        config.selectModel(different.value)
        let choices = config.selections
        await #expect(throws: LodyClientError.deliveryUnconfirmed) {
            try await stageAndDeliverTab(model, "Chosen model", selections: choices, rootID: "session-long")
        }
        let pending = try #require(model.pendingSessionTab(rootID: "session-long"))
        #expect(pending.selections == choices)
        #expect(model.retryOutgoingMessage(sessionID: pending.sessionID))
        try await model.deliverOutgoingMessage(sessionID: pending.sessionID)
        let tabID = pending.sessionID
        let stream = try await client.observeConversation(sessionID: tabID, workspaceID: "ws-demo")
        for try await update in stream {
            #expect(update.runConfig?.model?.value == different.value)
            #expect(update.conversation.turns.count == 1)
        }
    }

    @Test func tabProviderSwitchAppliesTheChosenAgentAndRetryKeepsIt() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, failTabStartOnce: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let options = try await model.newSessionOptions(templateSessionID: "session-long", isTab: true)
        #expect(options.providers.map(\.value) == ["claude", "codex"])
        #expect(options.agentConfigID == "codex")
        let claude = try await model.newSessionOptions(templateSessionID: "session-long", agentConfigID: "claude", isTab: true)
        #expect(claude.agentConfigID == "claude")
        #expect(claude.runConfig?.reasoning == nil)
        #expect(claude.runConfig?.model?.value == "sonnet")
        await #expect(throws: LodyClientError.deliveryUnconfirmed) {
            try await stageAndDeliverTab(model, "On Claude", agentConfigID: "claude", rootID: "session-long")
        }
        let pending = try #require(model.pendingSessionTab(rootID: "session-long"))
        #expect(pending.agentConfigID == "claude")
        #expect(model.retryOutgoingMessage(sessionID: pending.sessionID))
        try await model.deliverOutgoingMessage(sessionID: pending.sessionID)
        let tabID = pending.sessionID
        #expect(tabID == pending.sessionID)
        #expect(model.sessionSummary(tabID)?.agentName == "claude")
        let stream = try await client.observeConversation(sessionID: tabID, workspaceID: "ws-demo")
        for try await update in stream {
            #expect(update.runConfig?.model?.value == "sonnet")
            #expect(update.runConfig?.reasoning == nil)
        }
    }

    @Test func wrongWorkspaceAndNestedParentCannotCreateTabs() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let request = SessionTabStart(text: "First")
        await #expect(throws: (any Error).self) {
            try await client.startSessionTab(request, parentSessionID: "session-long", workspaceID: "wrong")
        }
        try await client.startSessionTab(request, parentSessionID: "session-long", workspaceID: "ws-demo")
        try await client.startSessionTab(request, parentSessionID: "session-long", workspaceID: "ws-demo")
        let history = try await client.conversation(sessionID: request.sessionID, workspaceID: "ws-demo")
        #expect(history.turns.count == 1)
        await #expect(throws: (any Error).self) {
            try await client.startSessionTab(SessionTabStart(text: "Nested"), parentSessionID: request.sessionID,
                                             workspaceID: "ws-demo")
        }
    }

    @Test func activeTabChoiceIsRememberedPerRootAndClearedWithTheAccount() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let rootID = "session-long"
        #expect(model.activeSessionTab(rootID: rootID) == rootID)
        let tabID = try await stageAndDeliverTab(model, "A separate conversation", rootID: rootID)
        model.setActiveSessionTab(tabID, rootID: rootID)
        #expect(model.activeSessionTab(rootID: rootID) == tabID)
        #expect(model.activeSessionTab(rootID: "session-pr") == "session-pr")
        model.signOut()
        #expect(model.activeSessionTab(rootID: rootID) == rootID)
    }

    @Test(arguments: ["closed", "archived", "deleted"])
    func unavailableRememberedTabFallsBackToMain(state: String) async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let rootID = "session-long"
        let tabID = try await stageAndDeliverTab(model, "Remembered tab", rootID: rootID)
        // Like the visible conversation, consume the creation echo before
        // exercising later metadata changes against its authoritative tabs.
        try await model.observeConversation(sessionID: tabID, rootSessionID: rootID) { _ in }
        model.setActiveSessionTab(tabID, rootID: rootID)
        // Change the service independently of the model's cached membership.
        if state == "closed" {
            try await client.updateSessionMetadata(.tabClosed(true), sessionID: tabID, workspaceID: "ws-demo")
        } else {
            _ = try await client.archiveSession(sessionID: tabID, workspaceID: "ws-demo")
            if state == "deleted" {
                try await client.deleteArchivedSession(sessionID: tabID, workspaceID: "ws-demo")
            }
        }
        try await model.observeConversation(sessionID: tabID, rootSessionID: rootID) { update in
            #expect(update.sessionTabs?.first?.id == rootID)
        }
        #expect(model.activeSessionTab(rootID: rootID) == rootID)
        #expect(model.sessionTabs(rootID: rootID).filter { $0.isTabClosed != true }.map(\.id) == [rootID])
    }

    @Test func listAggregatesTabActivityWithoutMakingMainBusyAndClearsAfterStop() async throws {
        let root = SessionRecord(summary: SessionSummary(id: "root", title: "Main", agentName: "codex",
            activity: .idle, preview: ""), turns: [], permission: nil)
        let child = SessionRecord(summary: SessionSummary(id: "child", title: "Tab", agentName: "codex",
            activity: .running, preview: "", parentSessionID: "root", isTabClosed: true), turns: [], permission: nil)
        let client = FixtureLodyClient(startsSignedIn: true, records: [root, child])
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        #expect(model.sessions.map(\.id) == ["root"])
        #expect(model.sessionSummary("root")?.isRunningInList == true)
        #expect(model.sessionSummary("root")?.activity == .idle)
        // Stop at the service, then observe Main: the tab projection must clear
        // the list marker without waiting for a separate session-list refresh.
        try await client.cancelSession(sessionID: "child", workspaceID: "ws-demo")
        try await model.observeConversation(sessionID: "root") { _ in }
        #expect(model.sessionSummary("root")?.isRunningInList == false)
        #expect(model.sessionSummary("root")?.activity == .idle)
        await model.refreshSessions()
        #expect(model.sessionSummary("root")?.isRunningInList == false)
    }

    @Test func childObservationAlsoRefreshesMainActivity() async throws {
        let root = SessionRecord(summary: SessionSummary(id: "root", title: "Main", agentName: "codex",
            activity: .running, preview: ""), turns: [], permission: nil)
        let child = SessionRecord(summary: SessionSummary(id: "child", title: "Tab", agentName: "codex",
            activity: .idle, preview: "", parentSessionID: "root"), turns: [], permission: nil)
        let client = FixtureLodyClient(startsSignedIn: true, records: [root, child])
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        #expect(model.sessionSummary("root")?.isRunningInList == true)
        try await client.cancelSession(sessionID: "root", workspaceID: "ws-demo")
        try await model.observeConversation(sessionID: "child", rootSessionID: "root") { _ in }
        #expect(model.sessionSummary("root")?.activity == .idle)
        #expect(model.sessionSummary("root")?.isRunningInList == false)
        #expect(model.sessionSummary("child")?.activity == .idle)
    }

    @Test func oldSessionCacheWithoutTabActivityStillDecodes() throws {
        let json = #"{"id":"root","title":"Main","agentName":"codex","activity":"idle","preview":""}"#
        var summary = try JSONDecoder().decode(SessionSummary.self, from: Data(json.utf8))
        #expect(summary.hasRunningTabs == nil)
        #expect(!summary.isRunningInList)
        summary.hasRunningTabs = true
        let restored = try JSONDecoder().decode(SessionSummary.self, from: JSONEncoder().encode(summary))
        #expect(restored.isRunningInList)
        #expect(restored.activity == .idle)
    }

    @Test func tabMetadataSurvivesNativePatchReconstruction() throws {
        let json = #"{"sessionID":"child","order":[],"changed":[],"activity":"idle","syncState":"live","sessionTabs":[{"id":"root","title":"Main","agentName":"codex","activity":"idle","preview":""},{"id":"child","title":"Tab","agentName":"codex","activity":"running","preview":"","parentSessionID":"root","isTabClosed":true,"lastMessageAt":10}]}"#
        let patch = try JSONDecoder().decode(ConversationPatch.self, from: Data(json.utf8))
        let update = try patch.applying(to: Conversation(sessionID: "child", turns: []))
        let child = try #require(update.sessionTabs?.last)
        #expect(child.parentSessionID == "root")
        #expect(child.isTabClosed == true)
        #expect(child.isUnread)
        #expect(child.activity == .running)
    }
}
