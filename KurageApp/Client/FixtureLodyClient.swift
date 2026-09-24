import Foundation

/// In-memory stand-in so the shell can be tapped before a real Lody connection exists.
@MainActor
final class FixtureLodyClient: LodyClient {
    private(set) var account: Account?
    let requiresExternalAuthorization = false
    let supportsConversations = true

    private var records: [SessionRecord]
    private var nextTurnNumber = 0

    init(startsSignedIn: Bool = false, records: [SessionRecord] = SessionRecord.samples) {
        self.records = records
        if startsSignedIn {
            account = Account(email: "demo@kurage.app")
        }
    }

    func beginDeviceAuthorization() async throws -> DeviceAuthorization {
        DeviceAuthorization(
            userCode: "ABCD-EFGH",
            verificationURL: URL(string: "https://lody.ai/device")!,
            deviceCode: "device-1",
            expiresIn: 600,
            interval: 0.01
        )
    }

    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws {
        guard authorization.deviceCode == "device-1" else { throw LodyClientError.signInFailed }
        try Task.checkCancellation()
        account = Account(email: "demo@kurage.app")
    }

    func restoreSession() async -> Account? {
        account
    }

    func signOut() {
        account = nil
    }

    func workspaces() async throws -> [WorkspaceSummary] {
        try requireAccount()
        return [WorkspaceSummary(id: "ws-demo", name: "Demo", slug: "demo")]
    }

    func sessions(workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary] {
        try requireAccount()
        try requireWorkspace(workspaceID)
        return records.map(\.summary)
    }

    func conversation(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> Conversation {
        try requireAccount()
        try requireWorkspace(workspaceID)
        let record = try record(sessionID)
        return Conversation(
            sessionID: record.summary.id,
            turns: record.turns,
            permission: record.permission
        )
    }

    func send(_ text: String, sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LodyClientError.emptyMessage }

        try update(sessionID) { record in
            let turn = ConversationTurn(id: makeTurnID(), author: .user, text: trimmed)
            record.turns.append(turn)
            record.summary.preview = trimmed
        }
    }

    func respond(
        _ decision: PermissionDecision,
        requestID: PermissionPrompt.ID,
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        try update(sessionID) { record in
            guard record.permission?.id == requestID else {
                throw LodyClientError.permissionMissing
            }
            record.permission = nil
            switch decision {
            case .allow:
                record.summary.preview = "Allowed"
            case .deny:
                record.summary.preview = "Denied"
            }
        }
    }

    private func requireAccount() throws {
        guard account != nil else { throw LodyClientError.signedOut }
    }

    private func requireWorkspace(_ workspaceID: WorkspaceSummary.ID) throws {
        guard workspaceID == "ws-demo" else { throw LodyClientError.notConnected }
    }

    private func record(_ sessionID: SessionSummary.ID) throws -> SessionRecord {
        guard let record = records.first(where: { $0.summary.id == sessionID }) else {
            throw LodyClientError.sessionMissing
        }
        return record
    }

    private func update(
        _ sessionID: SessionSummary.ID,
        _ body: (inout SessionRecord) throws -> Void
    ) throws {
        guard let index = records.firstIndex(where: { $0.summary.id == sessionID }) else {
            throw LodyClientError.sessionMissing
        }
        try body(&records[index])
    }

    private func makeTurnID() -> String {
        nextTurnNumber += 1
        return "turn-\(nextTurnNumber)"
    }
}

struct SessionRecord: Equatable, Sendable {
    var summary: SessionSummary
    var turns: [ConversationTurn]
    var permission: PermissionPrompt?
}

extension SessionRecord {
    static let samples: [SessionRecord] = [
        SessionRecord(
            summary: SessionSummary(
                id: "session-tests",
                title: "fix flaky tests",
                agentName: "codex",
                activity: .running,
                preview: "Running npm test",
                projectID: "local:machine-1:kurage",
                projectName: "kurage"
            ),
            turns: [
                ConversationTurn(id: "tests-user", author: .user, text: "Run the tests again"),
                ConversationTurn(id: "tests-agent", author: .agent, text: "Running npm test"),
            ],
            permission: PermissionPrompt(
                id: "perm-npm-test",
                title: "Allow npm test?",
                detail: "codex wants to run npm test on this machine"
            )
        ),
        SessionRecord(
            summary: SessionSummary(
                id: "session-long",
                title: "long conversation",
                agentName: "codex",
                activity: .idle,
                preview: "Latest reply in long conversation",
                projectID: "local:machine-1:kurage",
                projectName: "kurage"
            ),
            turns: (1...20).flatMap { number in
                [
                    ConversationTurn(id: "long-user-\(number)", author: .user, text: "Question \(number)"),
                    ConversationTurn(
                        id: "long-agent-\(number)",
                        author: .agent,
                        text: number == 20 ? "Latest reply in long conversation" : "Answer \(number): More details about this question."
                    ),
                ]
            },
            permission: nil
        ),
        SessionRecord(
            summary: SessionSummary(
                id: "session-pr",
                title: "review the PR",
                agentName: "claude",
                activity: .idle,
                preview: "Waiting for you",
                projectID: "local:machine-1:prism",
                projectName: "prism"
            ),
            turns: [
                ConversationTurn(id: "pr-user", author: .user, text: "Look at this PR"),
                ConversationTurn(id: "pr-agent", author: .agent, text: "The diff is small. Waiting for you."),
            ],
            permission: nil
        ),
    ]
}
