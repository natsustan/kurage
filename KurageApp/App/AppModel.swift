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
    private var pendingStartsByWorkspace: [WorkspaceSummary.ID: [PendingSessionStart]] = [:]
    var pendingSessionStarts: [PendingSessionStart] {
        guard let workspaceID = selectedWorkspaceID else { return [] }
        return pendingStartsByWorkspace[workspaceID] ?? []
    }

    private(set) var account: Account?
    private(set) var workspaces: [WorkspaceSummary] = []
    private(set) var workspaceGeneration = 0
    private(set) var selectedWorkspaceID: WorkspaceSummary.ID? {
        didSet {
            if oldValue != selectedWorkspaceID { workspaceGeneration += 1 }
        }
    }
    private(set) var sessions: [SessionSummary] = []
    private(set) var archivedSessions: [ArchivedSessionSummary] = []
    private(set) var isRefreshingSessions = false
    private(set) var isRefreshingArchivedSessions = false
    private var archiveLoadStatusNote: StatusNote?
    private var archiveOperationStatusNote: StatusNote?
    var archiveStatusNote: StatusNote? { archiveOperationStatusNote ?? archiveLoadStatusNote }
    private struct ActiveArchiveOperation: Equatable {
        let sessionID: SessionSummary.ID
        let id: UUID
    }
    private var activeArchiveOperations: [WorkspaceSummary.ID: ActiveArchiveOperation] = [:]
    var archivingSessionID: SessionSummary.ID? {
        selectedWorkspaceID.flatMap { activeArchiveOperations[$0]?.sessionID }
    }
    private var archiveOperations: [WorkspaceSummary.ID: [ArchivedSessionSummary.ID: UUID]] = [:]
    var archiveBusySessionIDs: Set<ArchivedSessionSummary.ID> {
        guard let workspaceID = selectedWorkspaceID else { return [] }
        return Set(archiveOperations[workspaceID, default: [:]].keys)
    }
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
    private var archiveRefreshGeneration = 0
    private var conversationCache: [WorkspaceSummary.ID: [SessionSummary.ID: Conversation]] = [:]
    /// Transcript text for list search. Memory only — the disk cache stores list display data, not conversation bodies.
    private var searchBodies: [WorkspaceSummary.ID: [SessionSummary.ID: String]] = [:]
    /// Sessions whose transcript was read since the last list refresh.
    private var freshSearchBodies: [WorkspaceSummary.ID: Set<SessionSummary.ID>] = [:]
    private var failedSearchBodies: [WorkspaceSummary.ID: Set<SessionSummary.ID>] = [:]
    private var dirtySearchBodies: [WorkspaceSummary.ID: Set<SessionSummary.ID>] = [:]
    private var searchIndexGeneration = 0
    private var searchIndexTask: Task<Void, Never>?
    private var isSessionSearchActive = false
    private var isApplicationActive = true
    /// Open conversation subscriptions. Search indexing uses the same sync bridge, so it waits until these finish.
    private var conversationObservationCount = 0
    private(set) var isIndexingSessionSearch = false

    var hasIncompleteSessionSearch: Bool {
        guard let workspaceID = selectedWorkspaceID else { return false }
        return failedSearchBodies[workspaceID]?.isEmpty == false
    }

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
    var supportsTextSending: Bool { client.supportsTextSending }
    var supportsTextSendingWhileRunning: Bool { client.supportsTextSendingWhileRunning }
    var supportsSessionCancellation: Bool { client.supportsSessionCancellation }
    var supportsSessionArchiving: Bool { client.supportsSessionArchiving }
    var supportsPermissionResponses: Bool { client.supportsPermissionResponses }
    var supportsSessionCreation: Bool { client.supportsSessionCreation }
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
        pendingStartsByWorkspace = [:]
        archiveOperations = [:]
        activeArchiveOperations = [:]
        account = nil
        workspaces = []
        workspaceStatusNote = nil
        selectedWorkspaceID = nil
        sessions = []
        clearArchivedSessions()
        conversationCache = [:]
        stopSessionSearch()
        searchBodies = [:]
        failedSearchBodies = [:]
        freshSearchBodies = [:]
        dirtySearchBodies = [:]
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
                cancelSessionSearchIndex()
                selectedWorkspaceID = loaded.first?.id
                sessions = selectedWorkspaceID.flatMap { sessionsByWorkspace[$0] } ?? []
                clearArchivedSessions()
            }
            let workspaceIDs = Set(loaded.map(\.id))
            archiveOperations = archiveOperations.filter { workspaceIDs.contains($0.key) }
            activeArchiveOperations = activeArchiveOperations.filter { workspaceIDs.contains($0.key) }
            sessionsByWorkspace = sessionsByWorkspace.filter { workspaceIDs.contains($0.key) }
            searchBodies = searchBodies.filter { workspaceIDs.contains($0.key) }
            failedSearchBodies = failedSearchBodies.filter { workspaceIDs.contains($0.key) }
            freshSearchBodies = freshSearchBodies.filter { workspaceIDs.contains($0.key) }
            dirtySearchBodies = dirtySearchBodies.filter { workspaceIDs.contains($0.key) }
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
        cancelSessionSearchIndex()
        selectedWorkspaceID = workspaceID
        sessions = sessionsByWorkspace[workspaceID] ?? []
        clearArchivedSessions()
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
            let ids = Set(loaded.map(\.id))
            searchBodies[workspaceID] = searchBodies[workspaceID]?.filter { ids.contains($0.key) }
            dirtySearchBodies[workspaceID] = dirtySearchBodies[workspaceID]?.intersection(ids)
            failedSearchBodies[workspaceID] = failedSearchBodies[workspaceID]?.intersection(ids)
            freshSearchBodies[workspaceID] = []
            persistSession()
            currentStatusNote = nil
            if isSessionSearchActive {
                scheduleSessionSearchIndex()
            }
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
        invalidateSearchBody(sessionID: sessionID, workspaceID: workspaceID)
        return loaded
    }

    func sessionSearchBody(sessionID: SessionSummary.ID) -> String {
        guard let workspaceID = selectedWorkspaceID else { return "" }
        return searchBodies[workspaceID]?[sessionID] ?? ""
    }

    /// Reads each visible session's projected transcript. Later keystrokes reuse that text until the list reloads.
    func indexSessionsForSearch() async {
        isSessionSearchActive = true
        guard let task = scheduleSessionSearchIndex() else { return }
        await task.value
    }

    func stopSessionSearch() {
        isSessionSearchActive = false
        cancelSessionSearchIndex()
    }

    func setApplicationActive(_ active: Bool) {
        isApplicationActive = active
        if active {
            scheduleSessionSearchIndex()
        } else {
            cancelSessionSearchIndex()
        }
    }

    func observeConversation(
        sessionID: String,
        onUpdate: @MainActor (ConversationUpdate) -> Void
    ) async throws {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        conversationObservationCount += 1
        cancelSessionSearchIndex()
        defer {
            conversationObservationCount -= 1
            if conversationObservationCount == 0 {
                scheduleSessionSearchIndex()
            }
        }
        let updates = try await client.observeConversation(sessionID: sessionID, workspaceID: workspaceID)
        for try await update in updates {
            try Task.checkCancellation()
            guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else {
                throw CancellationError()
            }
            guard update.conversation.sessionID == sessionID else { throw LodyClientError.notConnected }
            conversationCache[workspaceID, default: [:]][sessionID] = update.conversation
            invalidateSearchBody(sessionID: sessionID, workspaceID: workspaceID)
            if let activity = update.activity, let index = sessions.firstIndex(where: { $0.id == sessionID }),
               sessions[index].activity != activity {
                sessions[index].activity = activity
            }
            onUpdate(update)
        }
    }

    func loadSessionImage(
        _ image: ConversationImage,
        conversationSessionID: SessionSummary.ID,
        variant: SessionImageVariant
    ) async throws -> Data {
        guard image.isDisplayable, let workspaceID = selectedWorkspaceID else {
            throw LodyClientError.notConnected
        }
        let generation = authenticationGeneration
        let storageSessionID = image.storageSessionID ?? conversationSessionID
        let data = try await client.loadSessionImage(
            workspaceID: workspaceID,
            sessionID: storageSessionID,
            imageID: image.imageID,
            variant: variant
        )
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else {
            throw CancellationError()
        }
        return data
    }

    func cachedConversation(sessionID: SessionSummary.ID) -> Conversation? {
        guard let workspaceID = selectedWorkspaceID else { return nil }
        return conversationCache[workspaceID]?[sessionID]
    }

    @discardableResult
    func send(_ text: String, runConfig: RunConfigChoice? = nil, sessionID: SessionSummary.ID) async throws -> RunConfigChoice? {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let sentChoice = try await client.send(text, runConfig: runConfig, sessionID: sessionID, workspaceID: workspaceID)
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else {
            throw CancellationError()
        }
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            var session = sessions.remove(at: index)
            session.preview = text.trimmingCharacters(in: .whitespacesAndNewlines)
            sessions.insert(session, at: 0)
            sessionsByWorkspace[workspaceID] = sessions
            persistSession()
        }
        await refreshSessions(restart: true)
        return sentChoice
    }

    /// A new session starts from the project's most recent local session.
    func newSessionTemplate(projectID: String) -> SessionSummary? {
        guard projectID.hasPrefix("local:") else { return nil }
        return sessions.first { $0.projectID == projectID }
    }

    func newSessionOptions(
        templateSessionID: SessionSummary.ID,
        agentConfigID: String? = nil
    ) async throws -> NewSessionOptions {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let options = try await client.newSessionOptions(
            templateSessionID: templateSessionID, agentConfigID: agentConfigID, workspaceID: workspaceID
        )
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else {
            throw CancellationError()
        }
        return options
    }

    func startSession(
        _ text: String,
        agentConfigID: String? = nil,
        selections: [RunConfigChoice],
        projectID: String,
        templateSessionID: SessionSummary.ID
    ) async throws -> SessionSummary.ID {
        guard supportsSessionCreation, let workspaceID = selectedWorkspaceID,
              let template = sessions.first(where: { $0.id == templateSessionID && $0.projectID == projectID })
        else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        defer { refreshPendingStarts(workspaceID: workspaceID, generation: generation) }
        let sessionID = try await client.startSession(
            text, agentConfigID: agentConfigID, selections: selections, projectID: projectID,
            templateSessionID: templateSessionID, workspaceID: workspaceID
        )
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else {
            throw CancellationError()
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sessions.contains(where: { $0.id == sessionID }) {
            sessions.insert(SessionSummary(
                id: sessionID, title: String(trimmed.prefix(50)), agentName: template.agentName,
                activity: .idle, preview: trimmed, projectID: projectID, projectName: template.projectName
            ), at: 0)
            sessionsByWorkspace[workspaceID] = sessions
            persistSession()
        }
        // Navigation opens the session now; the list catches up in the background.
        Task { await refreshSessions(restart: true) }
        return sessionID
    }

    private func refreshPendingStarts(workspaceID: WorkspaceSummary.ID, generation: Int) {
        guard isCurrentAuthentication(generation) else { return }
        pendingStartsByWorkspace[workspaceID] = client.pendingSessionStarts(workspaceID: workspaceID)
    }

    func retrySessionStart(_ pending: PendingSessionStart) async throws -> SessionSummary.ID {
        guard supportsSessionCreation, let workspaceID = selectedWorkspaceID else {
            throw LodyClientError.notConnected
        }
        let generation = authenticationGeneration
        defer { refreshPendingStarts(workspaceID: workspaceID, generation: generation) }
        guard client.pendingSessionStarts(workspaceID: workspaceID).contains(pending) else {
            throw LodyClientError.sessionMissing
        }
        // Recovery uses the client's original request, independent of active templates or options.
        let sessionID = try await client.retrySessionStart(sessionID: pending.id, workspaceID: workspaceID)
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else {
            throw CancellationError()
        }
        Task { await refreshSessions(restart: true) }
        return sessionID
    }

    func cancelSession(sessionID: SessionSummary.ID) async throws {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        try await client.cancelSession(sessionID: sessionID, workspaceID: workspaceID)
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else {
            throw CancellationError()
        }
        await refreshSessions(restart: true)
    }

    func archiveSession(sessionID: SessionSummary.ID) async throws {
        guard supportsSessionArchiving, let workspaceID = selectedWorkspaceID else {
            throw LodyClientError.notConnected
        }
        guard activeArchiveOperations[workspaceID] == nil else { throw CancellationError() }
        let operation = ActiveArchiveOperation(sessionID: sessionID, id: UUID())
        activeArchiveOperations[workspaceID] = operation
        defer {
            if activeArchiveOperations[workspaceID] == operation {
                activeArchiveOperations.removeValue(forKey: workspaceID)
            }
        }
        let generation = authenticationGeneration
        let selectionGeneration = workspaceGeneration
        func isCurrentOperation() -> Bool {
            isCurrentAuthentication(generation) && selectedWorkspaceID == workspaceID &&
                workspaceGeneration == selectionGeneration && activeArchiveOperations[workspaceID] == operation
        }
        let archivedIDs: Set<SessionSummary.ID>
        do {
            archivedIDs = Set(try await client.archiveSession(sessionID: sessionID, workspaceID: workspaceID))
        } catch {
            guard isCurrentOperation() else { throw CancellationError() }
            throw error
        }
        guard isCurrentOperation() else { throw CancellationError() }
        cancelSessionSearchIndex()
        sessions.removeAll { archivedIDs.contains($0.id) }
        sessionsByWorkspace[workspaceID] = sessions
        for id in archivedIDs {
            conversationCache[workspaceID]?.removeValue(forKey: id)
            searchBodies[workspaceID]?.removeValue(forKey: id)
            freshSearchBodies[workspaceID]?.remove(id)
            dirtySearchBodies[workspaceID]?.remove(id)
            failedSearchBodies[workspaceID]?.remove(id)
        }
        persistSession()
        await refreshSessions(restart: true)
    }

    func refreshArchivedSessions() async {
        guard !Task.isCancelled, account != nil, let workspaceID = selectedWorkspaceID else { return }
        let generation = authenticationGeneration
        archiveRefreshGeneration += 1
        let refreshGeneration = archiveRefreshGeneration
        isRefreshingArchivedSessions = true
        defer {
            if archiveRefreshGeneration == refreshGeneration {
                isRefreshingArchivedSessions = false
            }
        }
        do {
            let loaded = try await client.archivedSessions(workspaceID: workspaceID)
            try Task.checkCancellation()
            guard isCurrentArchivedRefresh(
                generation, workspaceID: workspaceID, refreshGeneration: refreshGeneration
            ) else { return }
            archivedSessions = Self.newestArchivedFirst(loaded)
            archiveLoadStatusNote = nil
        } catch is CancellationError {
            return
        } catch LodyClientError.signedOut {
            guard isCurrentAuthentication(generation) else { return }
            signOut()
        } catch {
            if Task.isCancelled { return }
            guard isCurrentArchivedRefresh(
                generation, workspaceID: workspaceID, refreshGeneration: refreshGeneration
            ) else { return }
            archiveLoadStatusNote = StatusNote(tone: .failure, text: "Could not load archived sessions.")
        }
    }

    func restoreArchivedSession(_ sessionID: ArchivedSessionSummary.ID) async {
        guard account != nil, let workspaceID = selectedWorkspaceID,
              !archiveBusySessionIDs.contains(sessionID) else { return }
        let operationID = UUID()
        archiveOperations[workspaceID, default: [:]][sessionID] = operationID
        defer {
            if archiveOperations[workspaceID]?[sessionID] == operationID {
                archiveOperations[workspaceID]?.removeValue(forKey: sessionID)
            }
        }
        let generation = authenticationGeneration
        let selectionGeneration = workspaceGeneration
        func isCurrentOperation() -> Bool {
            isCurrentAuthentication(generation) && selectedWorkspaceID == workspaceID &&
                workspaceGeneration == selectionGeneration &&
                archiveOperations[workspaceID]?[sessionID] == operationID
        }
        do {
            try await client.restoreArchivedSession(sessionID: sessionID, workspaceID: workspaceID)
            guard isCurrentOperation() else { return }
            archiveOperationStatusNote = nil
            archivedSessions.removeAll { $0.id == sessionID }
            await refreshSessions(restart: true)
            guard isCurrentOperation() else { return }
            await refreshArchivedSessions()
        } catch is CancellationError {
            return
        } catch LodyClientError.signedOut {
            guard isCurrentOperation() else { return }
            signOut()
        } catch LodyClientError.archivedProjectUnavailable {
            guard isCurrentOperation() else { return }
            archiveOperationStatusNote = StatusNote(
                tone: .info,
                text: "Re-add this local project to restore its conversations."
            )
        } catch {
            guard isCurrentOperation() else { return }
            archiveOperationStatusNote = StatusNote(tone: .failure, text: "Could not restore the session.")
        }
    }

    func deleteArchivedSession(_ sessionID: ArchivedSessionSummary.ID) async {
        guard account != nil, let workspaceID = selectedWorkspaceID,
              !archiveBusySessionIDs.contains(sessionID) else { return }
        let operationID = UUID()
        archiveOperations[workspaceID, default: [:]][sessionID] = operationID
        defer {
            if archiveOperations[workspaceID]?[sessionID] == operationID {
                archiveOperations[workspaceID]?.removeValue(forKey: sessionID)
            }
        }
        let generation = authenticationGeneration
        let selectionGeneration = workspaceGeneration
        func isCurrentOperation() -> Bool {
            isCurrentAuthentication(generation) && selectedWorkspaceID == workspaceID &&
                workspaceGeneration == selectionGeneration &&
                archiveOperations[workspaceID]?[sessionID] == operationID
        }
        do {
            try await client.deleteArchivedSession(sessionID: sessionID, workspaceID: workspaceID)
            guard isCurrentOperation() else { return }
            archiveOperationStatusNote = nil
            archivedSessions.removeAll { $0.id == sessionID }
            await refreshArchivedSessions()
        } catch is CancellationError {
            return
        } catch LodyClientError.signedOut {
            guard isCurrentOperation() else { return }
            signOut()
        } catch {
            guard isCurrentOperation() else { return }
            archiveOperationStatusNote = StatusNote(tone: .failure, text: "Could not delete the session.")
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

    @discardableResult
    private func scheduleSessionSearchIndex() -> Task<Void, Never>? {
        guard isApplicationActive, isSessionSearchActive, conversationObservationCount == 0, supportsConversations,
              selectedWorkspaceID != nil else {
            isIndexingSessionSearch = false
            return nil
        }
        cancelSessionSearchIndex()
        searchIndexGeneration += 1
        let generation = searchIndexGeneration
        let task = Task { await self.performSessionSearchIndex(generation: generation) }
        searchIndexTask = task
        return task
    }

    private func cancelSessionSearchIndex() {
        searchIndexGeneration += 1
        searchIndexTask?.cancel()
        searchIndexTask = nil
        isIndexingSessionSearch = false
    }

    private func performSessionSearchIndex(generation: Int) async {
        guard isApplicationActive, isSessionSearchActive, supportsConversations,
              let workspaceID = selectedWorkspaceID else { return }
        let authGeneration = authenticationGeneration
        for session in sessions where searchBodies[workspaceID]?[session.id] == nil ||
            dirtySearchBodies[workspaceID]?.contains(session.id) == true {
            if failedSearchBodies[workspaceID]?.contains(session.id) != true,
               let cached = conversationCache[workspaceID]?[session.id] {
                searchBodies[workspaceID, default: [:]][session.id] = SessionSearch.bodyText(cached.turns)
                dirtySearchBodies[workspaceID]?.remove(session.id)
            }
        }
        let pending = sessions.map(\.id).filter { freshSearchBodies[workspaceID]?.contains($0) != true }
        guard searchIndexGeneration == generation else { return }
        guard !pending.isEmpty else { return }
        isIndexingSessionSearch = true
        defer {
            if searchIndexGeneration == generation {
                isIndexingSessionSearch = false
            }
        }
        for sessionID in pending {
            if Task.isCancelled || searchIndexGeneration != generation { return }
            guard isCurrentAuthentication(authGeneration), selectedWorkspaceID == workspaceID else { return }
            do {
                let loaded = try await client.conversation(sessionID: sessionID, workspaceID: workspaceID)
                if Task.isCancelled || searchIndexGeneration != generation { return }
                guard isCurrentAuthentication(authGeneration), selectedWorkspaceID == workspaceID,
                      sessions.contains(where: { $0.id == sessionID }),
                      loaded.sessionID == sessionID else { continue }
                storeSearchBody(loaded, workspaceID: workspaceID)
            } catch is CancellationError {
                return
            } catch LodyClientError.signedOut {
                return
            } catch {
                guard !Task.isCancelled, searchIndexGeneration == generation,
                      isCurrentAuthentication(authGeneration), selectedWorkspaceID == workspaceID,
                      sessions.contains(where: { $0.id == sessionID }) else { return }
                searchBodies[workspaceID]?.removeValue(forKey: sessionID)
                failedSearchBodies[workspaceID, default: []].insert(sessionID)
            }
        }
    }

    private func storeSearchBody(_ conversation: Conversation, workspaceID: WorkspaceSummary.ID) {
        failedSearchBodies[workspaceID]?.remove(conversation.sessionID)
        searchBodies[workspaceID, default: [:]][conversation.sessionID] = SessionSearch.bodyText(conversation.turns)
        freshSearchBodies[workspaceID, default: []].insert(conversation.sessionID)
        dirtySearchBodies[workspaceID]?.remove(conversation.sessionID)
    }

    // Streaming only marks the cached snapshot for indexing. Build text once
    // search resumes, rather than joining the entire history on every update.
    private func invalidateSearchBody(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) {
        failedSearchBodies[workspaceID]?.remove(sessionID)
        dirtySearchBodies[workspaceID, default: []].insert(sessionID)
        freshSearchBodies[workspaceID, default: []].insert(sessionID)
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

    private func clearArchivedSessions() {
        archiveRefreshGeneration += 1
        archivedSessions = []
        archiveLoadStatusNote = nil
        archiveOperationStatusNote = nil
        isRefreshingArchivedSessions = false
    }

    private func isCurrentArchivedRefresh(
        _ generation: Int,
        workspaceID: WorkspaceSummary.ID,
        refreshGeneration: Int
    ) -> Bool {
        isCurrentAuthentication(generation) && selectedWorkspaceID == workspaceID &&
            archiveRefreshGeneration == refreshGeneration
    }

    private static func newestArchivedFirst(_ sessions: [ArchivedSessionSummary]) -> [ArchivedSessionSummary] {
        sessions.sorted { lhs, rhs in
            if lhs.lastActivityAt != rhs.lastActivityAt { return lhs.lastActivityAt > rhs.lastActivityAt }
            return lhs.id < rhs.id
        }
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
