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
    private var tabsByWorkspace: [String: [String: [SessionSummary]]] = [:]
    private var pendingTabs: [String: [String: SessionTabStart]] = [:]
    private var startingTabs: Set<String> = []
    var supportsSessionTabs: Bool { client.supportsSessionTabs }

    func sessionSummary(_ id: String) -> SessionSummary? {
        if let root = sessions.first(where: { $0.id == id }) { return root }
        guard let workspaceID = selectedWorkspaceID else { return nil }
        return tabsByWorkspace[workspaceID]?.values.lazy.flatMap { $0 }.first { $0.id == id }
    }

    func sessionTabs(rootID: String) -> [SessionSummary] {
        guard let workspaceID = selectedWorkspaceID else { return [] }
        return tabsByWorkspace[workspaceID]?[rootID] ?? sessions.filter { $0.id == rootID }
    }

    func pendingSessionTab(rootID: String) -> SessionTabStart? {
        selectedWorkspaceID.flatMap { pendingTabs[$0]?[rootID] }
    }

    func newSessionTabOptions(rootID: String, agentConfigID: String?) async throws -> NewSessionOptions {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let selection = workspaceGeneration
        let result = try await client.newSessionTabOptions(parentSessionID: rootID, agentConfigID: agentConfigID,
                                                           workspaceID: workspaceID)
        try Task.checkCancellation()
        guard isCurrentAuthentication(generation), workspaceGeneration == selection else { throw CancellationError() }
        return result
    }

    func startSessionTab(_ text: String, attachments: [ComposerAttachment] = [], selections: [RunConfigChoice] = [],
                         agentConfigID: String? = nil, rootID: String) async throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { throw LodyClientError.emptyMessage }
        guard supportsSessionTabs, supportsSessionCreation, let workspaceID = selectedWorkspaceID,
              let root = sessions.first(where: { $0.id == rootID }) else { throw LodyClientError.sessionMissing }
        let generation = authenticationGeneration
        let selection = workspaceGeneration
        let operationKey = "\(generation):\(workspaceID):\(rootID)"
        guard startingTabs.insert(operationKey).inserted else { throw LodyClientError.deliveryUnconfirmed }
        defer { startingTabs.remove(operationKey) }
        if let pending = pendingTabs[workspaceID]?[rootID], pending.text != text || pending.attachments != attachments {
            throw LodyClientError.previousSendPending(pending.text)
        }
        let request = pendingTabs[workspaceID]?[rootID] ??
            SessionTabStart(text: text, attachments: attachments, selections: selections, agentConfigID: agentConfigID)
        pendingTabs[workspaceID, default: [:]][rootID] = request
        do {
            try await client.startSessionTab(request, parentSessionID: rootID, workspaceID: workspaceID)
        } catch LodyClientError.sessionCreationRejected {
            if isCurrentAuthentication(generation) { pendingTabs[workspaceID]?[rootID] = nil }
            throw LodyClientError.sessionCreationRejected
        }
        guard isCurrentAuthentication(generation), workspaceGeneration == selection else { throw CancellationError() }
        // Keep the retry identity if the initiating sheet disappeared after the
        // write: a later caller must confirm this tab, not create a duplicate.
        try Task.checkCancellation()
        pendingTabs[workspaceID]?[rootID] = nil
        var tabs = sessionTabs(rootID: rootID)
        if !tabs.contains(where: { $0.id == request.sessionID }) {
            tabs.append(SessionSummary(id: request.sessionID, title: String((text.isEmpty ? attachments.first?.fileName ?? "New tab" : text).prefix(50)),
                agentName: request.agentConfigID ?? root.agentName, activity: .idle, preview: text,
                projectID: root.projectID, projectName: root.projectName, machineName: root.machineName,
                parentSessionID: rootID))
        }
        tabsByWorkspace[workspaceID, default: [:]][rootID] = tabs
        return request.sessionID
    }

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
        guard !Task.isCancelled, account != nil else { return }
        let generation = authenticationGeneration
        let workspaceID = selectedWorkspaceID
        if workspaceID == nil {
            await refreshWorkspaces()
        } else {
            // Cached workspace selection lets the list load without waiting for HTTP discovery.
            async let workspaceRefresh: Void = refreshWorkspaces()
            await refreshSessions()
            await workspaceRefresh
        }
        guard !Task.isCancelled, isCurrentAuthentication(generation) else { return }
        if workspaceID == nil || selectedWorkspaceID != workspaceID {
            await refreshSessions()
        }
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
        await refreshContent()
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
        selectedSessionProjects = [:]
        projectCatalogGeneration = -1
        pendingTabs = [:]
        tabsByWorkspace = [:]
        startingTabs = []
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

    /// Owned by the visible list's SwiftUI task; no polling in details or the background.
    func refreshSessionsWhileVisible(interval: Duration = .seconds(10)) async {
        while !Task.isCancelled, account != nil {
            // Search owns the bridge while indexing; do not repeatedly invalidate its results.
            if !isSessionSearchActive {
                await refreshSessions(cancelWhenCallerCancels: true)
            }
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }

    func refreshSessions(restart: Bool = false, cancelWhenCallerCancels: Bool = false) async {
        guard !Task.isCancelled, account != nil, let workspaceID = selectedWorkspaceID else { return }
        let generation = authenticationGeneration
        if restart || sessionRefreshTask?.isCancelled == true ||
            (sessionRefreshTask != nil && sessionRefreshWorkspaceID != workspaceID) {
            cancelSessionRefresh()
        }
        let refreshTask: Task<[SessionSummary], Error>
        let ownsRequest = sessionRefreshTask == nil
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
            let loaded = try await withTaskCancellationHandler {
                try await refreshTask.value
            } onCancel: {
                // A disappearing list must not cancel a request started by another caller.
                if ownsRequest && cancelWhenCallerCancels { refreshTask.cancel() }
            }
            guard !Task.isCancelled, isCurrentSessionRefresh(
                generation, workspaceID: workspaceID, refreshGeneration: refreshGeneration
            ) else { return }
            // A list request can finish after a newer conversation update.
            // Merge only the monotonic message clock; keep fresh server fields.
            let known = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.lastMessageAt) })
            var merged = loaded
            var preservesNewerActivity = false
            for index in merged.indices {
                if let timestamp = known[merged[index].id] ?? nil, timestamp.isFinite,
                   timestamp > (merged[index].lastMessageAt ?? -.infinity) {
                    merged[index].lastMessageAt = timestamp
                    preservesNewerActivity = true
                }
            }
            if preservesNewerActivity {
                merged.sort { ($0.lastMessageAt ?? $0.lastActivityAt ?? 0) > ($1.lastMessageAt ?? $1.lastActivityAt ?? 0) }
            }
            sessions = merged
            sessionsByWorkspace[workspaceID] = merged
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
        } catch {
            // Bridge cancellation can surface as a WebKit error rather than CancellationError.
            guard !Task.isCancelled, !refreshTask.isCancelled, isCurrentSessionRefresh(
                generation, workspaceID: workspaceID, refreshGeneration: refreshGeneration
            ) else { return }
            switch error {
            case LodyClientError.signedOut:
                signOut()
            case LodyClientError.notConnected:
                currentStatusNote = StatusNote(tone: .info, text: "Session sync is not connected yet.")
            default:
                currentStatusNote = StatusNote(tone: .failure, text: "Could not refresh sessions.")
            }
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
            if let tabs = update.sessionTabs {
                let rootID = tabs.first?.id ?? sessionSummary(sessionID)?.parentSessionID ?? sessionID
                let root = sessions.first { $0.id == rootID }
                let projectedTabs = tabs.map { tab in
                    var tab = tab
                    tab.projectID = root?.projectID
                    tab.projectName = root?.projectName
                    tab.machineName = root?.machineName
                    return tab
                }
                if tabsByWorkspace[workspaceID]?[rootID] != projectedTabs {
                    tabsByWorkspace[workspaceID, default: [:]][rootID] = projectedTabs
                }
            }
            conversationCache[workspaceID, default: [:]][sessionID] = update.conversation
            invalidateSearchBody(sessionID: sessionID, workspaceID: workspaceID)
            if let activity = update.activity, let index = sessions.firstIndex(where: { $0.id == sessionID }),
               sessions[index].activity != activity {
                sessions[index].activity = activity
            }
            if let timestamp = update.lastMessageAt, timestamp.isFinite,
               let index = sessions.firstIndex(where: { $0.id == sessionID }),
               timestamp > (sessions[index].lastMessageAt ?? -.infinity) {
                sessions[index].lastMessageAt = timestamp
                sessions.sort { ($0.lastMessageAt ?? $0.lastActivityAt ?? 0) > ($1.lastMessageAt ?? $1.lastActivityAt ?? 0) }
                sessionsByWorkspace[workspaceID] = sessions
                persistSession()
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

    func pendingTextSend(sessionID: SessionSummary.ID) -> PendingTextSend? {
        guard let workspaceID = selectedWorkspaceID else { return nil }
        return client.pendingTextSend(sessionID: sessionID, workspaceID: workspaceID)
    }

    @discardableResult
    func send(_ text: String, attachments: [ComposerAttachment] = [], runConfig: RunConfigChoice? = nil,
              turnID: ConversationTurn.ID = UUID().uuidString.lowercased(),
              sessionID: SessionSummary.ID) async throws -> RunConfigChoice? {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let sentChoice = try await client.send(text, attachments: attachments, runConfig: runConfig, turnID: turnID,
                                               sessionID: sessionID, workspaceID: workspaceID)
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

    // Authorized targets live only for the current account/workspace generation.
    private var selectedSessionProjects: [String: SessionProject] = [:]
    private var projectCatalogGeneration: Int = -1

    func sessionProjects(templateSessionID: String, action: SessionProjectAction,
                         path: String? = nil, cursor: String? = nil) async throws -> SessionProjectResult {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = workspaceGeneration
        let auth = authenticationGeneration
        let result = try await client.sessionProjects(templateSessionID: templateSessionID, action: action,
            path: path, cursor: cursor, workspaceID: workspaceID)
        try Task.checkCancellation()
        guard generation == workspaceGeneration, isCurrentAuthentication(auth), selectedWorkspaceID == workspaceID else {
            throw CancellationError()
        }
        if projectCatalogGeneration != generation {
            selectedSessionProjects.removeAll()
            projectCatalogGeneration = generation
        }
        for project in (result.projects ?? []) + (result.project.map { [$0] } ?? []) {
            selectedSessionProjects[project.id] = project
        }
        return result
    }

    /// A new session starts from the project's most recent local session.
    func newSessionTemplate(projectID: String) -> SessionSummary? {
        guard projectID.hasPrefix("local:") else { return nil }
        return sessions.first { $0.projectID == projectID }
    }

    func mentionSessions(projectID: String, excluding sessionID: String? = nil) async throws -> [MentionSession] {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let result = try await client.mentionSessions(projectID: projectID, excluding: sessionID, workspaceID: workspaceID)
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else { throw LodyClientError.signedOut }
        return result
    }

    func mentionSkills(templateSessionID: String, agentConfigID: String? = nil, projectID: String? = nil) async throws -> [MentionSkill] {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let result = try await client.mentionSkills(templateSessionID: templateSessionID,
                                                    agentConfigID: agentConfigID, projectID: projectID, workspaceID: workspaceID)
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else { throw LodyClientError.signedOut }
        return result
    }

    func newSessionOptions(
        templateSessionID: SessionSummary.ID,
        agentConfigID: String? = nil, projectID: String? = nil
    ) async throws -> NewSessionOptions {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let options = try await client.newSessionOptions(
            templateSessionID: templateSessionID, agentConfigID: agentConfigID, projectID: projectID, workspaceID: workspaceID
        )
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else {
            throw CancellationError()
        }
        return options
    }

    func startSession(
        _ text: String, attachments: [ComposerAttachment] = [],
        agentConfigID: String? = nil,
        selections: [RunConfigChoice],
        projectID: String,
        templateSessionID: SessionSummary.ID
    ) async throws -> SessionSummary.ID {
        guard supportsSessionCreation, let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let template = sessions.first { $0.id == templateSessionID }
        guard template?.projectID == projectID || (projectCatalogGeneration == workspaceGeneration &&
            selectedSessionProjects[projectID]?.templateSessionID == templateSessionID)
        else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        defer { refreshPendingStarts(workspaceID: workspaceID, generation: generation) }
        let sessionID = try await client.startSession(
            text, attachments: attachments, agentConfigID: agentConfigID, selections: selections, projectID: projectID,
            templateSessionID: templateSessionID, workspaceID: workspaceID
        )
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else {
            throw CancellationError()
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sessions.contains(where: { $0.id == sessionID }) {
            sessions.insert(SessionSummary(
                id: sessionID, title: String((trimmed.isEmpty ? attachments.first?.fileName ?? "New session" : trimmed).prefix(50)), agentName: template?.agentName ?? "Agent",
                activity: .idle, preview: trimmed, projectID: projectID,
                projectName: selectedSessionProjects[projectID]?.name ?? template?.projectName, machineName: template?.machineName
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

    var supportsSessionMetadataEditing: Bool { client.supportsSessionMetadataEditing }

    var canCopySessionURL: Bool { selectedWorkspaceWebURL != nil }

    private var selectedWorkspaceWebURL: URL? {
        guard let workspace = workspaces.first(where: { $0.id == selectedWorkspaceID }),
              !workspace.slug.isEmpty else { return nil }
        return URL(string: LodyEndpoints.webOrigin)?.appendingPathComponent(workspace.slug)
    }

    func sessionURL(sessionID: String) -> URL? {
        selectedWorkspaceWebURL?
            .appendingPathComponent("sessions")
            .appendingPathComponent(sessionID)
    }

    func updateSessionMetadata(_ change: SessionMetadataChange, sessionID: String) async throws {
        try Task.checkCancellation()
        guard let workspaceID = selectedWorkspaceID, supportsSessionMetadataEditing else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let selection = workspaceGeneration
        let normalized: SessionMetadataChange
        switch change {
        case .pin, .tabClosed: normalized = change
        case .read(let timestamp):
            guard timestamp.isFinite else { throw LodyClientError.deliveryUnconfirmed }
            normalized = change
        case .rename(let title):
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.utf16.count <= 200 else { throw LodyClientError.deliveryUnconfirmed }
            normalized = .rename(title)
        }
        try await client.updateSessionMetadata(normalized, sessionID: sessionID, workspaceID: workspaceID)
        try Task.checkCancellation()
        guard isCurrentAuthentication(generation), workspaceGeneration == selection,
              selectedWorkspaceID == workspaceID else { throw CancellationError() }
        let interruptedRefresh = sessionRefreshTask != nil
        cancelSessionRefresh()
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            switch normalized {
            case .tabClosed: break
            case .pin(let value): sessions[index].isPinned = value
            case .rename(let title): sessions[index].title = title
            case .read(let timestamp):
                sessions[index].lastReadAt = max(sessions[index].lastReadAt ?? timestamp, timestamp)
            }
        }
        for rootID in Array((tabsByWorkspace[workspaceID] ?? [:]).keys) {
            guard let index = tabsByWorkspace[workspaceID]?[rootID]?.firstIndex(where: { $0.id == sessionID }) else { continue }
            switch normalized {
            case .tabClosed(let value): tabsByWorkspace[workspaceID]?[rootID]?[index].isTabClosed = value
            case .pin(let value): tabsByWorkspace[workspaceID]?[rootID]?[index].isPinned = value
            case .rename(let title): tabsByWorkspace[workspaceID]?[rootID]?[index].title = title
            case .read(let timestamp):
                let old = tabsByWorkspace[workspaceID]?[rootID]?[index].lastReadAt ?? timestamp
                tabsByWorkspace[workspaceID]?[rootID]?[index].lastReadAt = max(old, timestamp)
            }
        }
        sessionsByWorkspace[workspaceID] = sessions
        persistSession()
        if case .tabClosed = normalized { return }
        if case .read = normalized, !interruptedRefresh { return }
        await refreshSessions(restart: true)
    }

    func markSessionRead(sessionID: String, lastMessageAt: Double, workspaceGeneration: Int) async throws {
        guard self.workspaceGeneration == workspaceGeneration else { throw CancellationError() }
        if let session = sessions.first(where: { $0.id == sessionID }),
           let readAt = session.lastReadAt, readAt >= lastMessageAt { return }
        try await updateSessionMetadata(.read(lastMessageAt), sessionID: sessionID)
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

    var supportsQuestionResponses: Bool { client.supportsQuestionResponses }

    func respondToQuestion(_ request: ConversationQuestionRequest, answers: [String: QuestionAnswer]?,
                           sessionID: String, workspaceGeneration expectedGeneration: Int) async throws {
        guard workspaceGeneration == expectedGeneration, let workspaceID = selectedWorkspaceID else {
            throw CancellationError()
        }
        let generation = authenticationGeneration
        try Task.checkCancellation()
        try await client.respondToQuestion(request, answers: answers, sessionID: sessionID, workspaceID: workspaceID)
        try Task.checkCancellation()
        guard isCurrentAuthentication(generation), workspaceGeneration == expectedGeneration else {
            throw CancellationError()
        }
        conversationCache[workspaceID]?[sessionID]?.questions?.removeAll { $0.id == request.id }
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
