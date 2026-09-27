import Foundation
import Testing
@testable import Kurage

@MainActor
struct SessionMetadataTests {
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
