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
    private(set) var selectedWorkspaceID: WorkspaceSummary.ID?
    private(set) var sessions: [SessionSummary] = []
    private(set) var isRefreshingSessions = false
    private(set) var isSigningIn = false
    private(set) var statusNote: StatusNote?
    private(set) var deviceAuthorization: DeviceAuthorization?
    private var signInTask: Task<Void, Never>?
    private var authenticationGeneration = 0
    private var sessionRefreshGeneration = 0
    private var sessionRefreshTask: Task<[SessionSummary], Error>?
    private var sessionRefreshWorkspaceID: WorkspaceSummary.ID?
    private var conversationCache: [WorkspaceSummary.ID: [SessionSummary.ID: Conversation]] = [:]

    init(client: any LodyClient) {
        self.client = client
    }

    var isSignedIn: Bool { account != nil }
    var supportsConversationActions: Bool { client.supportsConversationActions }

    var workspaceLabel: String {
        selectedWorkspace?.name ?? account?.email ?? ""
    }

    var selectedWorkspace: WorkspaceSummary? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    /// Picks up a stored Lody session, or an account the fixture already holds.
    func adoptExistingAccount() async {
        if account == nil && signInTask == nil {
            let generation = authenticationGeneration
            let restored = await client.restoreSession()
            guard generation == authenticationGeneration, signInTask == nil, account == nil else { return }
            account = restored
        }
        guard account != nil else { return }
        await refreshWorkspaces()
        await refreshSessions()
    }

    func connect(open: @escaping @MainActor (URL) -> Void) {
        guard signInTask == nil else { return }
        authenticationGeneration += 1
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
                if client.requiresExternalAuthorization {
                    open(authorization.verificationURL)
                }
                try await client.finishDeviceAuthorization(authorization)
                account = client.account
                deviceAuthorization = nil
                await refreshWorkspaces()
                await refreshSessions()
            } catch is CancellationError {
                deviceAuthorization = nil
            } catch {
                signOut()
                deviceAuthorization = nil
                statusNote = StatusNote(tone: .failure, text: Self.signInMessage(for: error))
            }
        }
    }

    func reopenAuthorization(open: @MainActor (URL) -> Void) {
        guard client.requiresExternalAuthorization,
              let url = deviceAuthorization?.verificationURL else { return }
        open(url)
    }

    func cancelConnect() {
        signInTask?.cancel()
    }

    func signOut() {
        signInTask?.cancel()
        authenticationGeneration += 1
        cancelSessionRefresh()
        client.signOut()
        account = nil
        workspaces = []
        selectedWorkspaceID = nil
        sessions = []
        conversationCache = [:]
        statusNote = nil
    }

    func refreshWorkspaces() async {
        guard account != nil else { return }
        let generation = authenticationGeneration
        do {
            let loaded = try await client.workspaces()
            guard isCurrentAuthentication(generation) else { return }
            workspaces = loaded
            if !loaded.contains(where: { $0.id == selectedWorkspaceID }) {
                cancelSessionRefresh()
                selectedWorkspaceID = loaded.first?.id
                sessions = []
            }
        } catch {
            guard isCurrentAuthentication(generation) else { return }
            cancelSessionRefresh()
            workspaces = []
            selectedWorkspaceID = nil
            sessions = []
            statusNote = StatusNote(tone: .failure, text: "Could not load workspaces.")
        }
    }

    func selectWorkspace(_ workspaceID: WorkspaceSummary.ID) async {
        guard workspaces.contains(where: { $0.id == workspaceID }),
              selectedWorkspaceID != workspaceID else { return }
        cancelSessionRefresh()
        selectedWorkspaceID = workspaceID
        sessions = []
        statusNote = nil
        await refreshSessions()
    }

    func refreshSessions(restart: Bool = false) async {
        guard !Task.isCancelled, account != nil, let workspaceID = selectedWorkspaceID else { return }
        let generation = authenticationGeneration
        if restart || (sessionRefreshTask != nil && sessionRefreshWorkspaceID != workspaceID) {
            cancelSessionRefresh()
        }
        let refreshTask: Task<[SessionSummary], Error>
        if let currentTask = sessionRefreshTask {
            refreshTask = currentTask
        } else {
            sessionRefreshGeneration += 1
            isRefreshingSessions = true
            let client = self.client
            refreshTask = Task { try await client.sessions(workspaceID: workspaceID) }
            sessionRefreshTask = refreshTask
            sessionRefreshWorkspaceID = workspaceID
        }
        let refreshGeneration = sessionRefreshGeneration
        defer {
            if sessionRefreshGeneration == refreshGeneration {
                sessionRefreshTask = nil
                sessionRefreshWorkspaceID = nil
                isRefreshingSessions = false
            }
        }
        do {
            let loaded = try await refreshTask.value
            guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID,
                  sessionRefreshGeneration == refreshGeneration else { return }
            sessions = loaded
            statusNote = nil
        } catch is CancellationError {
            return
        } catch LodyClientError.notConnected {
            guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID,
                  sessionRefreshGeneration == refreshGeneration else { return }
            statusNote = StatusNote(tone: .info, text: "Session sync is not connected yet.")
        } catch {
            guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID,
                  sessionRefreshGeneration == refreshGeneration else { return }
            statusNote = StatusNote(tone: .failure, text: "Could not refresh sessions.")
        }
    }

    func conversation(sessionID: SessionSummary.ID) async throws -> Conversation {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let loaded = try await client.conversation(sessionID: sessionID, workspaceID: workspaceID)
        guard account != nil, selectedWorkspaceID == workspaceID else { throw LodyClientError.signedOut }
        conversationCache[workspaceID, default: [:]][sessionID] = loaded
        return loaded
    }

    func cachedConversation(sessionID: SessionSummary.ID) -> Conversation? {
        guard let workspaceID = selectedWorkspaceID else { return nil }
        return conversationCache[workspaceID]?[sessionID]
    }

    func send(_ text: String, sessionID: SessionSummary.ID) async throws {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        try await client.send(text, sessionID: sessionID, workspaceID: workspaceID)
        if isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID {
            await refreshSessions(restart: true)
        }
    }

    func respond(
        _ decision: PermissionDecision,
        requestID: PermissionPrompt.ID,
        sessionID: SessionSummary.ID
    ) async throws {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        try await client.respond(decision, requestID: requestID, sessionID: sessionID, workspaceID: workspaceID)
        if isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID {
            await refreshSessions(restart: true)
        }
    }

    private func cancelSessionRefresh() {
        sessionRefreshTask?.cancel()
        sessionRefreshTask = nil
        sessionRefreshWorkspaceID = nil
        sessionRefreshGeneration += 1
        isRefreshingSessions = false
    }

    private func isCurrentAuthentication(_ generation: Int) -> Bool {
        generation == authenticationGeneration && account != nil
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
