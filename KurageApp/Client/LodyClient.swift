import Foundation

/// A process-local creation that must resume its existing session and first turn.
struct PendingSessionStart: Identifiable, Equatable {
    let id: SessionSummary.ID
    let projectID: String
    let templateSessionID: SessionSummary.ID
    let text: String
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
    var supportsTextSending: Bool { get }
    var supportsTextSendingWhileRunning: Bool { get }
    var supportsSessionCancellation: Bool { get }
    var supportsSessionArchiving: Bool { get }
    var supportsPermissionResponses: Bool { get }
    /// Whether a local project can start a session from its most recent one.
    var supportsSessionCreation: Bool { get }

    func beginDeviceAuthorization() async throws -> DeviceAuthorization
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws
    func restoreSession() async -> Account?
    func signOut()
    func workspaces() async throws -> [WorkspaceSummary]
    func sessions(workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary]
    func conversation(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> Conversation
    func observeConversation(sessionID: String, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error>
    /// Returns the choice used to author the turn, including on retries.
    /// `nil` means the turn inherited its configuration without an explicit choice.
    /// `runConfig` applies only when this call creates the turn.
    @discardableResult
    func send(
        _ text: String,
        runConfig: RunConfigChoice?,
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> RunConfigChoice?
    func cancelSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws
    /// `templateSessionID` is the project's most recent root session. The new
    /// session reuses its machine and project and works in the project directory.
    /// `agentConfigID` picks another agent on that machine; `nil` keeps the template's.
    func newSessionOptions(
        templateSessionID: SessionSummary.ID,
        agentConfigID: String?,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> NewSessionOptions
    func pendingSessionStarts(workspaceID: WorkspaceSummary.ID) -> [PendingSessionStart]
    func retrySessionStart(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> SessionSummary.ID
    /// Returns the new session's ID. An unconfirmed start is retried with the
    /// same session and turn IDs until it is confirmed.
    func startSession(
        _ text: String,
        agentConfigID: String?,
        selections: [RunConfigChoice],
        projectID: String,
        templateSessionID: SessionSummary.ID,
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
    func observeConversation(sessionID: String, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error> {
        let snapshot = try await conversation(sessionID: sessionID, workspaceID: workspaceID)
        return AsyncThrowingStream { continuation in
            continuation.yield(ConversationUpdate(conversation: snapshot, activity: nil, syncState: .live))
            continuation.finish()
        }
    }

    @discardableResult
    func send(_ text: String, sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> RunConfigChoice? {
        try await send(text, runConfig: nil, sessionID: sessionID, workspaceID: workspaceID)
    }

    var cachedSession: SessionCache? { nil }
    func saveSessionCache(_ cache: SessionCache) {}
    var requiresExternalAuthorization: Bool { true }
    var supportsConversations: Bool { false }
    var supportsTextSending: Bool { false }
    var supportsTextSendingWhileRunning: Bool { false }
    var supportsSessionCancellation: Bool { false }
    var supportsSessionArchiving: Bool { false }
    var supportsPermissionResponses: Bool { false }
    var supportsSessionCreation: Bool { false }

    func newSessionOptions(
        templateSessionID: SessionSummary.ID,
        agentConfigID: String?,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> NewSessionOptions {
        throw LodyClientError.notConnected
    }

    func pendingSessionStarts(workspaceID: WorkspaceSummary.ID) -> [PendingSessionStart] { [] }

    func retrySessionStart(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> SessionSummary.ID {
        throw LodyClientError.sessionMissing
    }

    func startSession(
        _ text: String,
        agentConfigID: String?,
        selections: [RunConfigChoice],
        projectID: String,
        templateSessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> SessionSummary.ID {
        throw LodyClientError.notConnected
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
