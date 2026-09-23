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
        #expect(sessions.map(\.id) == ["session-tests", "session-pr"])
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
