import Foundation

struct StatusNote: Equatable {
    enum Tone: Equatable {
        case info
        case failure
    }

    var tone: Tone
    var text: String
}

@MainActor
@Observable
final class AppModel {
    private let client: any LodyClient

    private(set) var account: Account?
    private(set) var workspaces: [WorkspaceSummary] = []
    private(set) var sessions: [SessionSummary] = []
    private(set) var isSigningIn = false
    private(set) var statusNote: StatusNote?
    private(set) var deviceAuthorization: DeviceAuthorization?
    private var signInTask: Task<Void, Never>?

    init(client: any LodyClient) {
        self.client = client
    }

    var isSignedIn: Bool { account != nil }

    var workspaceLabel: String {
        if workspaces.count == 1, let name = workspaces.first?.name {
            return name
        }
        if workspaces.count > 1 {
            return "\(workspaces.count) workspaces"
        }
        return account?.email ?? ""
    }

    /// Picks up a stored Lody session, or an account the fixture already holds.
    func adoptExistingAccount() async {
        if account == nil {
            account = await client.restoreSession()
        }
        guard account != nil else { return }
        await refreshWorkspaces()
        await refreshSessions()
    }

    func connect(open: @escaping @MainActor (URL) -> Void) {
        guard signInTask == nil else { return }
        signInTask = Task {
            defer {
                signInTask = nil
                isSigningIn = false
            }
            isSigningIn = true
            statusNote = nil
            deviceAuthorization = nil
            do {
                let authorization = try await client.beginDeviceAuthorization()
                deviceAuthorization = authorization
                open(authorization.verificationURL)
                try await client.finishDeviceAuthorization(authorization)
                account = client.account
                deviceAuthorization = nil
                await refreshWorkspaces()
                await refreshSessions()
            } catch is CancellationError {
                deviceAuthorization = nil
            } catch {
                client.signOut()
                account = nil
                workspaces = []
                sessions = []
                deviceAuthorization = nil
                statusNote = StatusNote(tone: .failure, text: Self.signInMessage(for: error))
            }
        }
    }

    func reopenAuthorization(open: @MainActor (URL) -> Void) {
        guard let url = deviceAuthorization?.verificationURL else { return }
        open(url)
    }

    func cancelConnect() {
        signInTask?.cancel()
    }

    func signOut() {
        client.signOut()
        account = nil
        workspaces = []
        sessions = []
        statusNote = nil
    }

    func refreshWorkspaces() async {
        guard account != nil else { return }
        do {
            workspaces = try await client.workspaces()
        } catch {
            workspaces = []
        }
    }

    func refreshSessions() async {
        guard account != nil else { return }
        do {
            sessions = try await client.sessions()
            if statusNote?.tone == .info {
                statusNote = nil
            }
        } catch LodyClientError.notConnected {
            sessions = []
            statusNote = StatusNote(tone: .info, text: "Session sync is not connected yet.")
        } catch {
            statusNote = StatusNote(tone: .failure, text: "Could not refresh sessions.")
        }
    }

    func conversation(sessionID: SessionSummary.ID) async throws -> Conversation {
        try await client.conversation(sessionID: sessionID)
    }

    func send(_ text: String, sessionID: SessionSummary.ID) async throws {
        try await client.send(text, sessionID: sessionID)
        if let sessions = try? await client.sessions() {
            self.sessions = sessions
        }
    }

    func respond(
        _ decision: PermissionDecision,
        requestID: PermissionPrompt.ID,
        sessionID: SessionSummary.ID
    ) async throws {
        try await client.respond(decision, requestID: requestID, sessionID: sessionID)
        if let sessions = try? await client.sessions() {
            self.sessions = sessions
        }
    }

    private static func signInMessage(for error: Error) -> String {
        guard let error = error as? LodyClientError else { return "Could not sign in." }
        switch error {
        case .accessDenied:
            return "Authorization was denied."
        case .codeExpired:
            return "The code expired. Try again."
        case .unreachable:
            return "Could not reach Lody."
        default:
            return "Could not sign in."
        }
    }
}
