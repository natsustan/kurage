import Foundation

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
    var supportsPermissionResponses: Bool { get }

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

    var cachedSession: SessionCache? { nil }
    func saveSessionCache(_ cache: SessionCache) {}
    var requiresExternalAuthorization: Bool { true }
    var supportsConversations: Bool { false }
    var supportsTextSending: Bool { false }
    var supportsTextSendingWhileRunning: Bool { false }
    var supportsPermissionResponses: Bool { false }
}
