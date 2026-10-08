import Foundation
import Testing
@testable import Kurage
@testable import KurageCore

@MainActor
struct SessionMetadataTests {
    @Test func unreadComparisonAndOldCache() throws {
        let data = Data(#"{"id":"old","title":"Old","agentName":"codex","activity":"idle","preview":""}"#.utf8)
        var session = try JSONDecoder().decode(SessionSummary.self, from: data)
        #expect(!session.isUnread)
        session.lastMessageAt = 100
        #expect(session.isUnread)
        session.lastReadAt = 99
        #expect(session.isUnread)
        session.lastReadAt = 100
        #expect(!session.isUnread)
        session.lastReadAt = 101
        #expect(!session.isUnread)
    }

    @Test func readReceiptPersistsWithoutMarkingNewerMessagesRead() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        #expect(model.sessions.first { $0.id == "session-long" }?.isUnread == true)
        let generation = model.workspaceGeneration
        try await model.markSessionRead(sessionID: "session-long", lastMessageAt: 950, workspaceGeneration: generation)
        #expect(model.sessions.first { $0.id == "session-long" }?.isUnread == true)
        try await model.markSessionRead(sessionID: "session-long", lastMessageAt: 1_000, workspaceGeneration: generation)
        await model.refreshSessions()
        #expect(model.sessions.first { $0.id == "session-long" }?.isUnread == false)
        await #expect(throws: CancellationError.self) {
            try await model.markSessionRead(sessionID: "session-long", lastMessageAt: 2_000, workspaceGeneration: generation - 1)
        }
        #expect(model.sessions.first { $0.id == "session-long" }?.lastReadAt == 1_000)
    }

    @Test func metadataEditsPersistAcrossRefreshAndPreserveConversation() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let before = try await client.conversation(sessionID: "session-tests", workspaceID: "ws-demo")
        try await model.updateSessionMetadata(.pin(true), sessionID: "session-tests")
        try await model.updateSessionMetadata(.rename("  My session  "), sessionID: "session-tests")
        await model.refreshSessions()
        let session = try #require(model.sessions.first { $0.id == "session-tests" })
        #expect(session.isPinned == true)
        #expect(session.title == "My session")
        #expect(session.activity == .running)
        #expect(try await client.conversation(sessionID: "session-tests", workspaceID: "ws-demo") == before)
        let workspace = try #require(model.workspaces.first { $0.id == model.selectedWorkspaceID })
        #expect(model.sessionURL(sessionID: session.id)?.absoluteString == "https://lody.ai/\(workspace.slug)/sessions/session-tests")
        try await model.updateSessionMetadata(.pin(false), sessionID: session.id)
        #expect(model.sessions.first { $0.id == session.id }?.isPinned == false)
    }

    @Test func oldCacheWithoutPinStillDecodes() throws {
        let data = Data(#"{"id":"old","title":"Old","agentName":"codex","activity":"idle","preview":""}"#.utf8)
        #expect(try JSONDecoder().decode(SessionSummary.self, from: data).isPinned != true)
    }

    @Test func invalidRenameLeavesOriginalTitle() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()
        for title in ["  ", String(repeating: "x", count: 201)] {
            await #expect(throws: LodyClientError.deliveryUnconfirmed) {
                try await model.updateSessionMetadata(.rename(title), sessionID: "session-tests")
            }
        }
        #expect(model.sessions.first { $0.id == "session-tests" }?.title == "fix flaky tests")
    }
}
