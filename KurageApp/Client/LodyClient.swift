import Foundation

/// App-facing seam for one Lody account.
///
/// The fixture implements this in memory. The HTTP client uses Lody's device
/// authorization and reads workspace session metadata through Streams.
@MainActor
protocol LodyClient: AnyObject {
    var account: Account? { get }
    var requiresExternalAuthorization: Bool { get }
    var supportsConversations: Bool { get }

    func beginDeviceAuthorization() async throws -> DeviceAuthorization
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws
    func restoreSession() async -> Account?
    func signOut()
    func workspaces() async throws -> [WorkspaceSummary]
    func sessions(workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary]
    func conversation(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> Conversation
    func observeConversation(sessionID: String, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error>
    func send(_ text: String, sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws
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

    var requiresExternalAuthorization: Bool { true }
    var supportsConversations: Bool { false }
}
