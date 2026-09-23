import Foundation

/// App-facing seam for one Lody account.
///
/// The fixture implements this in memory. The HTTP client uses Lody's device
/// authorization, the same flow as the CLI, then reads session documents later.
@MainActor
protocol LodyClient: AnyObject {
    var account: Account? { get }

    func beginDeviceAuthorization() async throws -> DeviceAuthorization
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws
    func restoreSession() async -> Account?
    func signOut()
    func workspaces() async throws -> [WorkspaceSummary]
    func sessions() async throws -> [SessionSummary]
    func conversation(sessionID: SessionSummary.ID) async throws -> Conversation
    func send(_ text: String, sessionID: SessionSummary.ID) async throws
    func respond(
        _ decision: PermissionDecision,
        requestID: PermissionPrompt.ID,
        sessionID: SessionSummary.ID
    ) async throws
}
