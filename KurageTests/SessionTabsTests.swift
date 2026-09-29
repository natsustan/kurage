import Foundation
import Testing
@testable import Kurage

@MainActor
struct SessionTabsTests {
    @Test func tabCreationReadingClosingAndSendingRemainSeparateFromRoot() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let rootID = "session-long"
        let before = try await client.conversation(sessionID: rootID, workspaceID: "ws-demo")
        let tabID = try await model.startSessionTab("A separate conversation", rootID: rootID)
        #expect(!model.sessions.contains { $0.id == tabID })
        #expect(model.sessionSummary(tabID)?.parentSessionID == rootID)
        #expect(model.pendingSessionTab(rootID: rootID) == nil)
        let updates = try await client.observeConversation(sessionID: tabID, workspaceID: "ws-demo")
        for try await update in updates {
            #expect(update.sessionTabs?.map(\.id) == [rootID, tabID])
            #expect(update.conversation.turns.map(\.text) == ["A separate conversation"])
            #expect(update.conversation.subtasks?.isEmpty != false)
        }
        try await model.send("Only in this tab", sessionID: tabID)
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
            try await model.startSessionTab("Original", rootID: "session-long")
        }
        let pending = try #require(model.pendingSessionTab(rootID: "session-long"))
        await #expect(throws: LodyClientError.previousSendPending("Original")) {
            try await model.startSessionTab("Changed", rootID: "session-long")
        }
        #expect(model.pendingSessionTab(rootID: "session-long") == pending)
        let id = try await model.startSessionTab("Original", rootID: "session-long")
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
        let options = try await model.newSessionTabOptions(rootID: "session-long")
        #expect(options.providers.count == 1)
        var config = try #require(options.runConfig)
        let different = try #require(config.model?.options.last)
        config.selectModel(different.value)
        let choices = config.selections
        await #expect(throws: LodyClientError.deliveryUnconfirmed) {
            try await model.startSessionTab("Chosen model", selections: choices, rootID: "session-long")
        }
        let pending = try #require(model.pendingSessionTab(rootID: "session-long"))
        #expect(pending.selections == choices)
        let tabID = try await model.startSessionTab("Chosen model", selections: [], rootID: "session-long")
        let stream = try await client.observeConversation(sessionID: tabID, workspaceID: "ws-demo")
        for try await update in stream {
            #expect(update.runConfig?.model?.value == different.value)
            #expect(update.conversation.turns.count == 1)
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
