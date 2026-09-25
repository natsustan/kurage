import Foundation

/// In-memory stand-in so the shell can be tapped before a real Lody connection exists.
@MainActor
final class FixtureLodyClient: LodyClient {
    private(set) var account: Account?
    let requiresExternalAuthorization = false
    let supportsConversations = true
    let supportsTextSending = true
    let supportsTextSendingWhileRunning = true
    let supportsSessionCancellation = true
    let supportsSessionArchiving = true
    let supportsPermissionResponses = true

    private var records: [SessionRecord]
    private var archivedSessionIDs: Set<SessionSummary.ID>
    private var archivedActivity: [SessionSummary.ID: Date] = [
        "archived-newer": Date(timeIntervalSince1970: 1_700_000_000),
        "archived-older": Date(timeIntervalSince1970: 1_600_000_000),
    ]
    private var nextTurnNumber = 0

    init(
        startsSignedIn: Bool = false,
        records: [SessionRecord] = SessionRecord.samples,
        archivedIDs: Set<SessionSummary.ID>? = nil
    ) {
        self.records = records
        if let archivedIDs {
            self.archivedSessionIDs = archivedIDs
        } else {
            let seeded: Set<SessionSummary.ID> = ["archived-newer", "archived-older"]
            self.archivedSessionIDs = Set(records.map(\.summary.id)).intersection(seeded)
        }
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
        return records
            .filter { !archivedSessionIDs.contains($0.summary.id) }
            .map(\.summary)
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

    func observeConversation(sessionID: String, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error> {
        let snapshot = try await conversation(sessionID: sessionID, workspaceID: workspaceID)
        let update = ConversationUpdate(conversation: snapshot, activity: nil, syncState: .live,
                                        runConfig: try record(sessionID).runConfig)
        return AsyncThrowingStream { continuation in
            continuation.yield(update)
            continuation.finish()
        }
    }

    func send(
        _ text: String,
        runConfig: RunConfigChoice?,
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LodyClientError.emptyMessage }

        try update(sessionID) { record in
            if let runConfig {
                guard let current = record.runConfig,
                      current.choosing(runConfig.value) == runConfig else { throw LodyClientError.notConnected }
                record.runConfig = current.applying(runConfig)
            }
            let turn = ConversationTurn(id: makeTurnID(), author: .user, text: trimmed)
            record.turns.append(turn)
            record.summary.preview = trimmed
        }
        if let index = records.firstIndex(where: { $0.summary.id == sessionID }) {
            records.insert(records.remove(at: index), at: 0)
        }
    }

    func cancelSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        try update(sessionID) { record in
            guard record.summary.activity == .running else { throw LodyClientError.sessionBusy }
            record.summary.activity = .idle
            record.permission = nil
        }
    }

    func loadSessionImage(
        workspaceID: WorkspaceSummary.ID,
        sessionID: SessionSummary.ID,
        imageID: String,
        variant: SessionImageVariant
    ) async throws -> Data {
        try requireAccount()
        try requireWorkspace(workspaceID)
        let known = records.contains { record in
            record.turns.contains { turn in
                turn.content.contains { part in
                    guard case .image(let image) = part, image.imageID == imageID else { return false }
                    return (image.storageSessionID ?? record.summary.id) == sessionID
                }
            }
        }
        guard known else { throw LodyClientError.sessionMissing }
        return FixtureImage.png
    }

    func archiveSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        guard records.contains(where: { $0.summary.id == sessionID }) else {
            throw LodyClientError.sessionMissing
        }
        archivedSessionIDs.insert(sessionID)
        archivedActivity[sessionID] = Date()
    }

    func archivedSessions(workspaceID: WorkspaceSummary.ID) async throws -> [ArchivedSessionSummary] {
        try requireAccount()
        try requireWorkspace(workspaceID)
        return records.compactMap { record in
            guard archivedSessionIDs.contains(record.summary.id) else { return nil }
            return ArchivedSessionSummary(
                id: record.summary.id,
                title: record.summary.title,
                lastActivityAt: archivedActivity[record.summary.id] ?? .distantPast,
                canRestore: record.canRestore,
                projectName: record.summary.projectName
            )
        }
        .sorted { lhs, rhs in
            if lhs.lastActivityAt != rhs.lastActivityAt { return lhs.lastActivityAt > rhs.lastActivityAt }
            return lhs.id < rhs.id
        }
    }

    func restoreArchivedSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        guard let record = records.first(where: { $0.summary.id == sessionID }),
              archivedSessionIDs.contains(sessionID) else {
            throw LodyClientError.sessionMissing
        }
        guard record.canRestore else { throw LodyClientError.archivedProjectUnavailable }
        archivedSessionIDs.remove(sessionID)
        if let index = records.firstIndex(where: { $0.summary.id == sessionID }) {
            records.insert(records.remove(at: index), at: 0)
        }
    }

    func deleteArchivedSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        guard archivedSessionIDs.contains(sessionID) else { throw LodyClientError.sessionMissing }
        records.removeAll { $0.summary.id == sessionID }
        archivedSessionIDs.remove(sessionID)
        archivedActivity.removeValue(forKey: sessionID)
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
    var runConfig: SessionRunConfig? = nil
    var canRestore: Bool = true
}

extension SessionRunConfig {
    static let fixtureReasoning = SessionRunConfig(
        model: Value(value: "gpt-5.5", label: "gpt-5.5"),
        reasoning: Value(value: "high", label: "High"),
        editable: Editable(kind: .reasoning, configOptionID: "reasoning_effort", options: [
            Value(value: "low", label: "Low"),
            Value(value: "medium", label: "Medium"),
            Value(value: "high", label: "High"),
        ])
    )

    static let fixtureModel = SessionRunConfig(
        model: Value(value: "sonnet", label: "Sonnet"),
        reasoning: nil,
        editable: Editable(kind: .model, configOptionID: nil, options: [
            Value(value: "sonnet", label: "Sonnet"),
            Value(value: "opus", label: "Opus"),
        ])
    )
}

enum FixtureImage {
    /// 120×80 PNG, so fixture layouts also exercise non-square image content.
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAHgAAABQCAYAAADSm7GJAAAA00lEQVR4nO3RMQ0AIADAMPwLQARyMAQySEaP/ks21tyHrvE6AIMxGIM/ZXCcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGx10d8AQ+quhfSQAAAABJRU5ErkJggg==")!
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
            ),
            runConfig: .fixtureReasoning
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
            permission: nil,
            runConfig: .fixtureReasoning
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
                ConversationTurn(
                    id: "pr-user", author: .user, text: "Look at this PR",
                    parts: [
                        .image(ConversationImage(
                            imageID: "pr-user-shot", mimeType: "image/png", fileName: "screenshot.png",
                            width: 80, height: 80
                        )),
                        .text("Look at this PR"),
                    ]
                ),
                ConversationTurn(
                    id: "pr-agent", author: .agent, text: "The diff is small. Waiting for you.",
                    parts: [
                        .text("The diff is small. Waiting for you."),
                        .image(ConversationImage(
                            imageID: "pr-shot", mimeType: "image/png", fileName: "diff.png",
                            width: 120, height: 80
                        )),
                        .image(ConversationImage(imageID: "pr-shot-2", mimeType: "image/png", fileName: "details.png")),
                        .image(ConversationImage(imageID: "pr-shot-3", mimeType: "image/png", fileName: "result.png")),
                    ]
                ),
            ],
            permission: nil,
            runConfig: .fixtureModel
        ),
        SessionRecord(
            summary: SessionSummary(
                id: "archived-newer",
                title: "newer archived",
                agentName: "codex",
                activity: .idle,
                preview: "Archived note",
                projectID: "local:machine-1:kurage",
                projectName: "kurage"
            ),
            turns: [
                ConversationTurn(id: "archived-newer-user", author: .user, text: "Archived note"),
            ],
            permission: nil
        ),
        SessionRecord(
            summary: SessionSummary(
                id: "archived-older",
                title: "older archived",
                agentName: "codex",
                activity: .idle,
                preview: "Old note",
                projectID: "local:machine-1:prism",
                projectName: "prism"
            ),
            turns: [
                ConversationTurn(id: "archived-older-user", author: .user, text: "Old note"),
            ],
            permission: nil
        ),
    ]
}
