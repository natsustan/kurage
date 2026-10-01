import Foundation

enum SessionMetadataChange: Sendable {
    case tabClosed(Bool)
    case pin(Bool)
    case rename(String)
    case read(Double)
}

struct SessionTabStart: Equatable, Sendable {
    var sessionID = UUID().uuidString.lowercased()
    var turnID = UUID().uuidString.lowercased()
    var timestamp = ISO8601DateFormatter().string(from: Date())
    let text: String
    var attachments: [ComposerAttachment] = []
    var selections: [RunConfigChoice] = []
    /// Another agent on the parent's machine; `nil` keeps the parent's.
    var agentConfigID: String?
}

/// A process-local creation that must resume its existing session and first turn.
struct PendingSessionStart: Identifiable, Equatable {
    let id: SessionSummary.ID
    let projectID: String
    let templateSessionID: SessionSummary.ID
    let text: String
    var attachments: [ComposerAttachment] = []
    var turnID: ConversationTurn.ID? = nil

    var displayText: String { text.isEmpty ? attachments.map(\.fileName).joined(separator: ", ") : text }
}

struct PendingTextSend: Equatable {
    let text: String
    let turnID: ConversationTurn.ID
    var attachments: [ComposerAttachment] = []
}

/// App-facing seam for one Lody account.
///
/// The fixture implements this in memory. The HTTP client uses Lody's device
/// authorization and synchronizes workspace sessions through Streams.
@MainActor
protocol LodyClient: AnyObject {
    var account: Account? { get }
    var cachedSession: SessionCache? { get }
    func saveSessionCache(_ cache: SessionCache)
    var requiresExternalAuthorization: Bool { get }
    /// Whether conversation history and updates can be read.
    var supportsConversations: Bool { get }
    var supportsHistoricalFilePreviews: Bool { get }
    func filePreview(sessionID: String, turnID: String, path: String, workspaceID: String) async throws -> ConversationFilePreview
    var supportsTextSending: Bool { get }
    var supportsTextSendingWhileRunning: Bool { get }
    var supportsSessionCancellation: Bool { get }
    var supportsSessionArchiving: Bool { get }
    var supportsSessionMetadataEditing: Bool { get }
    func updateSessionMetadata(_ change: SessionMetadataChange, sessionID: String, workspaceID: String) async throws
    var supportsPermissionResponses: Bool { get }
    var supportsQuestionResponses: Bool { get }
    func respondToQuestion(_ request: ConversationQuestionRequest, answers: [String: QuestionAnswer]?,
                           sessionID: String, workspaceID: String) async throws
    /// Whether a local project can start a session from its most recent one.
    var supportsSessionCreation: Bool { get }
    var supportsProjectGitReading: Bool { get }
    /// Read the current branch of the registered project folder.
    func projectGit(templateSessionID: String, projectID: String, workspaceID: String) async throws -> ProjectGitResult

    var supportsSessionTabs: Bool { get }
    func startSessionTab(_ request: SessionTabStart, parentSessionID: String, workspaceID: String) async throws

    func beginDeviceAuthorization() async throws -> DeviceAuthorization
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws
    func restoreSession() async -> Account?
    func signOut()
    func workspaces() async throws -> [WorkspaceSummary]
    func sessions(workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary]
    func mentionSessions(projectID: String, excluding sessionID: String?, workspaceID: WorkspaceSummary.ID) async throws -> [MentionSession]
    func mentionSkills(templateSessionID: String, agentConfigID: String?, projectID: String?, workspaceID: WorkspaceSummary.ID) async throws -> [MentionSkill]
    func conversation(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> Conversation
    /// The turn ID reserved for an in-flight or unconfirmed text send.
    func pendingTextSend(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) -> PendingTextSend?
    func observeConversation(sessionID: String, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error>
    func observeConversation(sessionID: String, rootSessionID: String?, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error>
    /// Returns the choice used to author the turn, including on retries.
    /// `nil` means the turn inherited its configuration without an explicit choice.
    /// `runConfig` applies only when this call creates the turn.
    /// A running session uses steer against its active assistant turn. The
    /// machine owns any fallback to a follow-up when steer cannot be applied.
    @discardableResult
    func send(
        _ text: String, attachments: [ComposerAttachment],
        runConfig: RunConfigChoice?,
        turnID: ConversationTurn.ID,
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> RunConfigChoice?
    func cancelSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws
    /// `templateSessionID` supplies the machine and default agent. `projectID`
    /// may select another registered local project on that same machine.
    /// `agentConfigID` picks another agent on that machine; `nil` keeps the template's.
    func sessionProjects(templateSessionID: String, action: SessionProjectAction, path: String?, cursor: String?,
                         workspaceID: String) async throws -> SessionProjectResult
    /// `isTab` reads the options a tab inherits: the template is the parent
    /// session and only that agent's run configuration stays editable.
    func newSessionOptions(
        templateSessionID: SessionSummary.ID,
        agentConfigID: String?,
        projectID: String?,
        isTab: Bool,
        refresh: Bool,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> NewSessionOptions
    func pendingSessionStarts(workspaceID: WorkspaceSummary.ID) -> [PendingSessionStart]
    func retrySessionStart(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> SessionSummary.ID
    /// Returns the new session's ID. An unconfirmed start is retried with the
    /// same session and turn IDs until it is confirmed.
    func startSession(
        _ text: String, attachments: [ComposerAttachment],
        agentConfigID: String?,
        selections: [RunConfigChoice],
        projectID: String,
        templateSessionID: SessionSummary.ID,
        sessionID: SessionSummary.ID,
        turnID: ConversationTurn.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> SessionSummary.ID
    /// Returns every confirmed archived document session ID, including lifecycle descendants.
    @discardableResult
    func archiveSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary.ID]
    func archivedSessions(workspaceID: WorkspaceSummary.ID) async throws -> [ArchivedSessionSummary]
    func restoreArchivedSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws
    func deleteArchivedSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws
    /// `sessionID` is the blob namespace (`storageSessionId` when a fork copied the image).
    func loadSessionImage(
        workspaceID: WorkspaceSummary.ID,
        sessionID: SessionSummary.ID,
        imageID: String,
        variant: SessionImageVariant
    ) async throws -> Data
    func respond(
        _ decision: PermissionDecision,
        requestID: PermissionPrompt.ID,
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws
}

extension LodyClient {
    func observeConversation(sessionID: String, rootSessionID: String?, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error> {
        try await observeConversation(sessionID: sessionID, workspaceID: workspaceID)
    }

    var supportsSessionTabs: Bool { false }

    func startSessionTab(_ request: SessionTabStart, parentSessionID: String, workspaceID: String) async throws {
        throw LodyClientError.notConnected
    }

    func mentionSessions(projectID: String, excluding sessionID: String?, workspaceID: WorkspaceSummary.ID) async throws -> [MentionSession] { [] }
    func mentionSkills(templateSessionID: String, agentConfigID: String?, projectID: String?, workspaceID: WorkspaceSummary.ID) async throws -> [MentionSkill] { [] }
    func pendingTextSend(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) -> PendingTextSend? { nil }

    func observeConversation(sessionID: String, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error> {
        let snapshot = try await conversation(sessionID: sessionID, workspaceID: workspaceID)
        return AsyncThrowingStream { continuation in
            continuation.yield(ConversationUpdate(conversation: snapshot, activity: nil, syncState: .live))
            continuation.finish()
        }
    }

    @discardableResult
    func send(_ text: String, attachments: [ComposerAttachment] = [], sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> RunConfigChoice? {
        try await send(text, attachments: attachments, runConfig: nil, turnID: UUID().uuidString.lowercased(),
                       sessionID: sessionID, workspaceID: workspaceID)
    }

    @discardableResult
    func send(_ text: String, attachments: [ComposerAttachment] = [], runConfig: RunConfigChoice?, sessionID: SessionSummary.ID,
              workspaceID: WorkspaceSummary.ID) async throws -> RunConfigChoice? {
        try await send(text, attachments: attachments, runConfig: runConfig, turnID: UUID().uuidString.lowercased(),
                       sessionID: sessionID, workspaceID: workspaceID)
    }

    var cachedSession: SessionCache? { nil }
    func saveSessionCache(_ cache: SessionCache) {}
    var requiresExternalAuthorization: Bool { true }
    var supportsConversations: Bool { false }
    var supportsHistoricalFilePreviews: Bool { false }
    func filePreview(sessionID: String, turnID: String, path: String, workspaceID: String) async throws -> ConversationFilePreview {
        ConversationFilePreview(status: .unavailable, reason: "unsupported")
    }
    var supportsTextSending: Bool { false }
    var supportsTextSendingWhileRunning: Bool { false }
    var supportsSessionCancellation: Bool { false }
    var supportsSessionArchiving: Bool { false }
    var supportsSessionMetadataEditing: Bool { false }
    func updateSessionMetadata(_ change: SessionMetadataChange, sessionID: String, workspaceID: String) async throws {
        throw LodyClientError.notConnected
    }
    var supportsPermissionResponses: Bool { false }
    var supportsQuestionResponses: Bool { false }
    func respondToQuestion(_ request: ConversationQuestionRequest, answers: [String: QuestionAnswer]?,
                           sessionID: String, workspaceID: String) async throws {
        throw LodyClientError.notConnected
    }
    var supportsSessionCreation: Bool { false }
    var supportsProjectGitReading: Bool { false }
    func projectGit(templateSessionID: String, projectID: String, workspaceID: String) async throws -> ProjectGitResult {
        ProjectGitResult(failure: .unsupported)
    }

    func sessionProjects(templateSessionID: String, action: SessionProjectAction, path: String?, cursor: String?,
                         workspaceID: String) async throws -> SessionProjectResult {
        throw LodyClientError.notConnected
    }

    func newSessionOptions(
        templateSessionID: SessionSummary.ID,
        agentConfigID: String?,
        projectID: String?,
        isTab: Bool,
        refresh: Bool,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> NewSessionOptions {
        throw LodyClientError.notConnected
    }

    func pendingSessionStarts(workspaceID: WorkspaceSummary.ID) -> [PendingSessionStart] { [] }

    func retrySessionStart(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> SessionSummary.ID {
        throw LodyClientError.sessionMissing
    }

    func startSession(
        _ text: String, attachments: [ComposerAttachment] = [],
        agentConfigID: String?,
        selections: [RunConfigChoice],
        projectID: String,
        templateSessionID: SessionSummary.ID,
        sessionID: SessionSummary.ID,
        turnID: ConversationTurn.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> SessionSummary.ID {
        throw LodyClientError.notConnected
    }

    func startSession(
        _ text: String, attachments: [ComposerAttachment] = [],
        agentConfigID: String?, selections: [RunConfigChoice], projectID: String,
        templateSessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID
    ) async throws -> SessionSummary.ID {
        try await startSession(text, attachments: attachments, agentConfigID: agentConfigID, selections: selections,
                               projectID: projectID, templateSessionID: templateSessionID,
                               sessionID: UUID().uuidString.lowercased(), turnID: UUID().uuidString.lowercased(),
                               workspaceID: workspaceID)
    }

    @discardableResult
    func archiveSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary.ID] {
        throw LodyClientError.notConnected
    }

    func archivedSessions(workspaceID: WorkspaceSummary.ID) async throws -> [ArchivedSessionSummary] {
        throw LodyClientError.notConnected
    }

    func restoreArchivedSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        throw LodyClientError.notConnected
    }

    func deleteArchivedSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        throw LodyClientError.notConnected
    }

    func loadSessionImage(
        workspaceID: WorkspaceSummary.ID,
        sessionID: SessionSummary.ID,
        imageID: String,
        variant: SessionImageVariant
    ) async throws -> Data {
        throw LodyClientError.notConnected
    }
}
