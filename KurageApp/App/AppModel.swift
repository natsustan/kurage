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
    private var sessionsByWorkspace: [String: [SessionSummary]] = [:]
    private var isRestoringAccount = false

    private(set) var account: Account?
    private(set) var workspaces: [WorkspaceSummary] = []
    private(set) var selectedWorkspaceID: WorkspaceSummary.ID?
    private(set) var sessions: [SessionSummary] = []
    private(set) var isRefreshingSessions = false
    private(set) var isSigningIn = false
    private var currentStatusNote: StatusNote?
    private var workspaceStatusNote: StatusNote?
    var statusNote: StatusNote? { workspaceStatusNote ?? currentStatusNote }
    private(set) var deviceAuthorization: DeviceAuthorization?
    private var signInTask: Task<Void, Never>?
    private var authenticationGeneration = 0
    private var sessionRefreshGeneration = 0
    private var sessionRefreshTask: Task<[SessionSummary], Error>?
    private var sessionRefreshWorkspaceID: WorkspaceSummary.ID?
    private var conversationCache: [WorkspaceSummary.ID: [SessionSummary.ID: Conversation]] = [:]

    init(client: any LodyClient) {
        self.client = client
        account = client.account
        if let cache = client.cachedSession, cache.account == account {
            workspaces = cache.workspaces
            selectedWorkspaceID = cache.selectedWorkspaceID
            sessionsByWorkspace = cache.sessionsByWorkspace
            sessions = cache.selectedWorkspaceID.flatMap { cache.sessionsByWorkspace[$0] } ?? []
        }
    }

    var isSignedIn: Bool { account != nil }
    var supportsConversations: Bool { client.supportsConversations }
    var supportsConversationActions: Bool { client.supportsConversationActions }
    var hasCachedSessions: Bool {
        selectedWorkspaceID.map { sessionsByWorkspace[$0] != nil } ?? false
    }

    func refreshContent() async {
        await refreshWorkspaces()
        await refreshSessions()
    }

    var workspaceLabel: String {
        selectedWorkspace?.name ?? account?.email ?? ""
    }

    var selectedWorkspace: WorkspaceSummary? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    /// Picks up a stored Lody session, or an account the fixture already holds.
    func adoptExistingAccount() async {
        guard !isRestoringAccount, signInTask == nil else { return }
        isRestoringAccount = true
        defer { isRestoringAccount = false }
        let generation = authenticationGeneration
        let restored = await client.restoreSession()
        guard generation == authenticationGeneration, signInTask == nil else { return }
        if restored == nil {
            if account != nil { signOut() }
            return
        }
        account = restored
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
            currentStatusNote = nil
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
                currentStatusNote = StatusNote(tone: .failure, text: Self.signInMessage(for: error))
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
        workspaceStatusNote = nil
        selectedWorkspaceID = nil
        sessions = []
        conversationCache = [:]
        sessionsByWorkspace = [:]
        currentStatusNote = nil
    }

    func refreshWorkspaces() async {
        guard account != nil else { return }
        let generation = authenticationGeneration
        do {
            let loaded = try await client.workspaces()
            guard isCurrentAuthentication(generation) else { return }
            workspaces = loaded
            workspaceStatusNote = nil
            if !loaded.contains(where: { $0.id == selectedWorkspaceID }) {
                cancelSessionRefresh()
                selectedWorkspaceID = loaded.first?.id
                sessions = selectedWorkspaceID.flatMap { sessionsByWorkspace[$0] } ?? []
            }
            sessionsByWorkspace = sessionsByWorkspace.filter { entry in loaded.contains { $0.id == entry.key } }
            persistSession()
        } catch LodyClientError.signedOut {
            guard isCurrentAuthentication(generation) else { return }
            signOut()
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentAuthentication(generation) else { return }
            workspaceStatusNote = StatusNote(tone: .failure, text: "Could not load workspaces.")
        }
    }

    func selectWorkspace(_ workspaceID: WorkspaceSummary.ID) async {
        guard workspaces.contains(where: { $0.id == workspaceID }),
              selectedWorkspaceID != workspaceID else { return }
        cancelSessionRefresh()
        selectedWorkspaceID = workspaceID
        sessions = sessionsByWorkspace[workspaceID] ?? []
        persistSession()
        currentStatusNote = nil
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
            guard isCurrentSessionRefresh(
                generation, workspaceID: workspaceID, refreshGeneration: refreshGeneration
            ) else { return }
            sessions = loaded
            sessionsByWorkspace[workspaceID] = loaded
            persistSession()
            currentStatusNote = nil
        } catch is CancellationError {
            return
        } catch LodyClientError.signedOut {
            guard isCurrentSessionRefresh(
                generation, workspaceID: workspaceID, refreshGeneration: refreshGeneration
            ) else { return }
            signOut()
        } catch LodyClientError.notConnected {
            guard isCurrentSessionRefresh(
                generation, workspaceID: workspaceID, refreshGeneration: refreshGeneration
            ) else { return }
            currentStatusNote = StatusNote(tone: .info, text: "Session sync is not connected yet.")
        } catch {
            guard isCurrentSessionRefresh(
                generation, workspaceID: workspaceID, refreshGeneration: refreshGeneration
            ) else { return }
            currentStatusNote = StatusNote(tone: .failure, text: "Could not refresh sessions.")
        }
    }

    func conversation(sessionID: SessionSummary.ID) async throws -> Conversation {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let loaded = try await client.conversation(sessionID: sessionID, workspaceID: workspaceID)
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else { throw LodyClientError.signedOut }
        conversationCache[workspaceID, default: [:]][sessionID] = loaded
        return loaded
    }

    func observeConversation(
        sessionID: String,
        onUpdate: @MainActor (ConversationUpdate) -> Void
    ) async throws {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let updates = try await client.observeConversation(sessionID: sessionID, workspaceID: workspaceID)
        for try await update in updates {
            try Task.checkCancellation()
            guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else {
                throw CancellationError()
            }
            guard update.conversation.sessionID == sessionID else { throw LodyClientError.notConnected }
            conversationCache[workspaceID, default: [:]][sessionID] = update.conversation
            if let activity = update.activity, let index = sessions.firstIndex(where: { $0.id == sessionID }),
               sessions[index].activity != activity {
                sessions[index].activity = activity
            }
            onUpdate(update)
        }
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

    private func persistSession() {
        guard let account else { return }
        client.saveSessionCache(SessionCache(
            account: account,
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            sessionsByWorkspace: sessionsByWorkspace
        ))
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

    private func isCurrentSessionRefresh(
        _ generation: Int,
        workspaceID: WorkspaceSummary.ID,
        refreshGeneration: Int
    ) -> Bool {
        isCurrentAuthentication(generation) && selectedWorkspaceID == workspaceID &&
            sessionRefreshGeneration == refreshGeneration
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
