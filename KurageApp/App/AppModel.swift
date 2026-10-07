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
    @ObservationIgnored private let quickActionDefaults: UserDefaults
    @ObservationIgnored private var quickActionOptionsLoads: [QuickActionOptionsKey: QuickActionOptionsLoad] = [:]
    private struct QuickActionOptionsKey: Hashable {
        let workspaceID: String
        let authenticationGeneration: Int
        let workspaceGeneration: Int
        let rootID: String
        let agentConfigID: String?
        let refresh: Bool
    }
    private struct QuickActionOptionsLoad {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<NewSessionOptions, Error>]
    }
    private(set) var quickActionPreferenceRevision = 0
    private(set) var defaultModelsRevision = 0
    let notifications: NotificationModel
    private(set) var notificationNavigation: NotificationNavigation?
    private(set) var notificationOpenGeneration = 0
    private var notificationRoutingGeneration = 0
    private var tabsByWorkspace: [String: [String: [SessionSummary]]] = [:]
    private var activeTabsByWorkspace: [WorkspaceSummary.ID: [SessionSummary.ID: SessionSummary.ID]] = [:]
    private var pendingTabs: [String: [String: SessionTabStart]] = [:]
    private var outgoingByWorkspace: [String: [String: OutgoingMessage]] = [:]
    private var outgoingStartsByWorkspace: [String: [String: OutgoingSessionStart]] = [:]
    private var activeMessageSends: Set<String> = []
    private var imagePreviewScopes: [String: UUID] = [:]
    private var imagePreviews = SessionImagePreviewCache()
    private var supersededMessages: [String: [String: Set<String>]] = [:]
    private var rejectedTurnIDsByWorkspace: [String: [String: Set<String>]] = [:]
    var supportsSessionTabs: Bool { client.supportsSessionTabs }

    func sessionSummary(_ id: String) -> SessionSummary? {
        if let root = sessionIndex[id] { return root }
        guard let workspaceID = selectedWorkspaceID else { return nil }
        return tabsByWorkspace[workspaceID]?.values.lazy.flatMap { $0 }.first { $0.id == id }
            ?? outgoingStartsByWorkspace[workspaceID]?[id]?.summary
    }

    func sessionTabs(rootID: String) -> [SessionSummary] {
        guard let workspaceID = selectedWorkspaceID else { return [] }
        var tabs = tabsByWorkspace[workspaceID]?[rootID] ?? sessionSummary(rootID).map { [$0] } ?? []
        let starts = (outgoingStartsByWorkspace[workspaceID] ?? [:]).values
            .filter { $0.summary.parentSessionID == rootID }
            .sorted { $0.stagedAt < $1.stagedAt }
        for start in starts where !tabs.contains(where: { $0.id == start.summary.id }) {
            tabs.append(start.summary)
        }
        return tabs
    }

    func pendingSessionTab(rootID: String) -> SessionTabStart? {
        selectedWorkspaceID.flatMap { pendingTabs[$0]?[rootID] }
    }

    /// The tab a detail reopens on. It lives here rather than in the detail's
    /// transient state so returning from the list resumes the tab the user left
    /// on, like the desktop viewer's restored tab. A remembered tab is kept even
    /// when the projection does not list it yet: the tab bar drops back to the
    /// root once a loaded projection proves the tab is gone.
    func activeSessionTab(rootID: String) -> SessionSummary.ID {
        guard let workspaceID = selectedWorkspaceID else { return rootID }
        return activeTabsByWorkspace[workspaceID]?[rootID] ?? rootID
    }

    func setActiveSessionTab(_ tabID: SessionSummary.ID, rootID: String) {
        guard let workspaceID = selectedWorkspaceID else { return }
        activeTabsByWorkspace[workspaceID, default: [:]][rootID] = tabID
    }

    func newSessionOptions(templateSessionID: SessionSummary.ID, agentConfigID: String? = nil,
                           projectID: String? = nil, isTab: Bool = false, refresh: Bool = false) async throws -> NewSessionOptions {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let selection = workspaceGeneration
        let result = try await client.newSessionOptions(templateSessionID: templateSessionID, agentConfigID: agentConfigID,
                                                        projectID: projectID, isTab: isTab, refresh: refresh, workspaceID: workspaceID)
        try Task.checkCancellation()
        guard isCurrentAuthentication(generation), workspaceGeneration == selection else { throw CancellationError() }
        return result
    }

    /// Share the initial read and stale-cache refresh; each profile applies its own preferences afterward.
    func quickActionOptions(rootID: String, agentConfigID: String?, refresh: Bool = false) async throws -> NewSessionOptions {
        try Task.checkCancellation()
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let key = QuickActionOptionsKey(workspaceID: workspaceID, authenticationGeneration: authenticationGeneration,
            workspaceGeneration: workspaceGeneration, rootID: rootID, agentConfigID: agentConfigID, refresh: refresh)
        let waiterID = UUID()
        let options = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NewSessionOptions, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if quickActionOptionsLoads[key] != nil {
                    quickActionOptionsLoads[key]?.waiters[waiterID] = continuation
                    return
                }
                let loadID = UUID()
                let task = Task<Void, Never> { [client, weak self] in
                    let result: Result<NewSessionOptions, Error>
                    do {
                        var loaded = try await client.newSessionOptions(templateSessionID: rootID, agentConfigID: agentConfigID,
                            projectID: nil, isTab: true, refresh: refresh, workspaceID: workspaceID)
                        try Task.checkCancellation()
                        if !refresh, loaded.needsRefresh == true {
                            guard let self else { throw CancellationError() }
                            // A default-agent read and an explicit selection can resolve to the same agent.
                            loaded = try await self.quickActionOptions(rootID: rootID,
                                agentConfigID: loaded.agentConfigID.isEmpty ? nil : loaded.agentConfigID, refresh: true)
                        }
                        try Task.checkCancellation()
                        result = .success(loaded)
                    } catch {
                        result = .failure(error)
                    }
                    self?.finishQuickActionOptionsLoad(result, key: key, loadID: loadID)
                }
                quickActionOptionsLoads[key] = QuickActionOptionsLoad(id: loadID, task: task, waiters: [waiterID: continuation])
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelQuickActionOptionsWaiter(waiterID, key: key) }
        }
        try Task.checkCancellation()
        guard isCurrentAuthentication(key.authenticationGeneration), workspaceGeneration == key.workspaceGeneration else {
            throw CancellationError()
        }
        return options
    }

    private func cancelQuickActionOptionsWaiter(_ waiterID: UUID, key: QuickActionOptionsKey) {
        guard let waiter = quickActionOptionsLoads[key]?.waiters.removeValue(forKey: waiterID) else { return }
        waiter.resume(throwing: CancellationError())
        if quickActionOptionsLoads[key]?.waiters.isEmpty == true {
            quickActionOptionsLoads.removeValue(forKey: key)?.task.cancel()
        }
    }

    private func finishQuickActionOptionsLoad(_ result: Result<NewSessionOptions, Error>, key: QuickActionOptionsKey, loadID: UUID) {
        guard quickActionOptionsLoads[key]?.id == loadID,
              let load = quickActionOptionsLoads.removeValue(forKey: key) else { return }
        let current = isCurrentAuthentication(key.authenticationGeneration) && workspaceGeneration == key.workspaceGeneration
        for waiter in load.waiters.values { waiter.resume(with: current ? result : .failure(CancellationError())) }
    }

    private func cancelQuickActionOptionsLoads() {
        let loads = quickActionOptionsLoads.values
        quickActionOptionsLoads = [:]
        for load in loads {
            load.task.cancel()
            for waiter in load.waiters.values { waiter.resume(throwing: CancellationError()) }
        }
    }

    private var sessionsByWorkspace: [String: [SessionSummary]] = [:]
    private var isRestoringAccount = false
    private var pendingStartsByWorkspace: [WorkspaceSummary.ID: [PendingSessionStart]] = [:]
    var pendingSessionStarts: [PendingSessionStart] {
        guard let workspaceID = selectedWorkspaceID else { return [] }
        var pending = pendingStartsByWorkspace[workspaceID] ?? []
        for start in (outgoingStartsByWorkspace[workspaceID] ?? [:]).values
            where !start.isConfirmed && start.summary.parentSessionID == nil && !pending.contains(where: { $0.id == start.summary.id }) {
            pending.append(start.pending)
        }
        return pending
    }

    private(set) var account: Account?
    private(set) var workspaces: [WorkspaceSummary] = []
    private(set) var workspaceGeneration = 0
    private(set) var selectedWorkspaceID: WorkspaceSummary.ID? {
        didSet {
            if oldValue != selectedWorkspaceID {
                workspaceGeneration += 1
                cancelQuickActionOptionsLoads()
            }
        }
    }
    // Views resolve the same session several times per body; the index keeps
    // `sessionSummary` off a linear scan of the whole list. `didSet` covers
    // element mutations as well as whole-array assignments, so it cannot go stale.
    private(set) var sessions: [SessionSummary] = [] {
        didSet {
            sessionIndex = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
    private var sessionIndex: [String: SessionSummary] = [:]
    private(set) var archivedSessions: [ArchivedSessionSummary] = []
    private(set) var isRefreshingSessions = false
    private(set) var isRefreshingWorkspaces = false
    var workspaceLoadStatusNote: StatusNote? { workspaceStatusNote }
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
    private var authenticationGeneration = 0 {
        didSet { cancelQuickActionOptionsLoads() }
    }
    private var workspaceRefreshGeneration = 0
    private var sessionRefreshGeneration = 0
    private var sessionRefreshTask: Task<[SessionSummary], Error>?
    private var sessionRefreshWorkspaceID: WorkspaceSummary.ID?
    private var archiveRefreshGeneration = 0
    private var conversationCache: [WorkspaceSummary.ID: [SessionSummary.ID: Conversation]] = [:]
    private struct FilePreviewCacheEntry {
        let file: ConversationFileChange
        let preview: ConversationFilePreview
    }
    private struct FilePreviewKey: Hashable {
        let accountID: String?
        let email: String
        let workspaceID: String
        let sessionID: String
        let turnID: String
        let path: String
    }
    private var filePreviews: [FilePreviewKey: FilePreviewCacheEntry] = [:]
    var supportsHistoricalFilePreviews: Bool { client.supportsHistoricalFilePreviews }

    func filePreview(sessionID: String, turnID: String, file: ConversationFileChange,
                     workspaceID: String) async throws -> ConversationFilePreview {
        try Task.checkCancellation()
        guard selectedWorkspaceID == workspaceID, let account else { throw CancellationError() }
        let authentication = authenticationGeneration
        let workspace = workspaceGeneration
        let key = FilePreviewKey(accountID: account.id, email: account.email,
                                 workspaceID: workspaceID, sessionID: sessionID, turnID: turnID, path: file.path)
        if let conversation = conversationCache[workspaceID]?[sessionID] {
            guard conversation.fileChanges?.first(where: { $0.id == turnID })?.files.first(where: { $0.path == file.path }) == file else {
                throw CancellationError()
            }
        }
        // Without checkpoint identity, unchanged counts cannot prove that the
        // historical text is still the same. Refetch these previews on reopen.
        if file.previewRevision != nil, file.previewFinished == true,
           let cached = filePreviews[key], cached.file == file { return cached.preview }
        let preview = try await client.filePreview(sessionID: sessionID, turnID: turnID, path: file.path, workspaceID: workspaceID)
        try Task.checkCancellation()
        guard isCurrentAuthentication(authentication), self.account == account, workspaceGeneration == workspace,
              selectedWorkspaceID == workspaceID else { throw CancellationError() }
        if let conversation = conversationCache[workspaceID]?[sessionID] {
            guard conversation.fileChanges?.first(where: { $0.id == turnID })?.files.first(where: { $0.path == file.path }) == file else {
                throw CancellationError()
            }
        }
        if preview.status == .ready, file.previewRevision != nil, file.previewFinished == true {
            func bytes(_ preview: ConversationFilePreview) -> Int {
                guard let edit = preview.edit else { return 0 }
                return edit.oldText.utf8.count + edit.newText.utf8.count
            }
            // Larger snapshots must not turn the item-count cache into an unbounded text cache.
            if filePreviews.count >= 16 || filePreviews.values.reduce(bytes(preview), { $0 + bytes($1.preview) }) > 32 * 1024 * 1024 {
                filePreviews.removeAll()
            }
            filePreviews[key] = FilePreviewCacheEntry(file: file, preview: preview)
        }
        return preview
    }
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
    /// New subscriptions interrupt queued search reads; their first update resumes indexing.
    private var conversationObservationCount = 0
    private(set) var isIndexingSessionSearch = false

    var hasIncompleteSessionSearch: Bool {
        guard let workspaceID = selectedWorkspaceID else { return false }
        return failedSearchBodies[workspaceID]?.isEmpty == false
    }

    init(client: any LodyClient, notifications: NotificationModel? = nil, quickActionDefaults: UserDefaults = .standard) {
        self.client = client
        self.quickActionDefaults = quickActionDefaults
        self.notifications = notifications ?? NotificationModel(service: FixturePushNotificationService())
        account = client.account
        if let cache = client.cachedSession, cache.account == account {
            workspaces = cache.workspaces
            selectedWorkspaceID = cache.selectedWorkspaceID
            sessionsByWorkspace = cache.sessionsByWorkspace
            rejectedTurnIDsByWorkspace = cache.rejectedTurnIDsByWorkspace
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

    var quickActionMachines: [QuickActionMachine] {
        var seen: Set<String> = []
        return sessions.compactMap { session in
            guard session.parentSessionID == nil,
                  let machineID = QuickActionMachine.machineID(projectID: session.projectID),
                  seen.insert(machineID).inserted else { return nil }
            return QuickActionMachine(id: machineID, name: session.machineName ?? machineID,
                                      templateSessionID: session.id)
        }
    }

    func supportsQuickActions(rootID: String) -> Bool {
        supportsSessionTabs && supportsSessionCreation && sessionIndex[rootID] != nil &&
            QuickActionMachine.machineID(projectID: sessionIndex[rootID]?.projectID) != nil
    }

    func quickActionBlockingFailure(rootID: String) -> QuickActionFailure? {
        guard supportsQuickActions(rootID: rootID), let projectID = sessionIndex[rootID]?.projectID else {
            return .unavailable
        }
        let roots = sessions.filter { $0.projectID == projectID }
        if roots.contains(where: { $0.isRunningInList }) ||
            roots.contains(where: { sessionTabs(rootID: $0.id).contains { $0.activity == .running } }) {
            return .busy
        }
        if roots.contains(where: { pendingSessionTab(rootID: $0.id) != nil }) ||
            pendingSessionStarts.contains(where: { $0.projectID == projectID }) {
            return .pending
        }
        return nil
    }

    private func quickActionPreferenceKey(rootID: String) -> String? {
        guard let account, let workspaceID = selectedWorkspaceID,
              let machineID = QuickActionMachine.machineID(projectID: sessionIndex[rootID]?.projectID) else {
            return nil
        }
        return QuickActionPreference.storageKey(account: account, workspaceID: workspaceID, machineID: machineID)
    }

    func quickActionPreference(rootID: String, profile: QuickActionProfile) -> QuickActionPreference? {
        _ = quickActionPreferenceRevision
        guard let key = quickActionPreferenceKey(rootID: rootID), let data = quickActionDefaults.data(forKey: key) else { return nil }
        return QuickActionPreferences.decode(data)?[profile]
    }

    private func defaultModelsKey(sessionID: String) -> String? {
        guard let account, let workspaceID = selectedWorkspaceID,
              let machineID = QuickActionMachine.machineID(projectID: sessionSummary(sessionID)?.projectID) else { return nil }
        return DefaultModel.storageKey(account: account, workspaceID: workspaceID, machineID: machineID)
    }

    func defaultModels(sessionID: String) -> [DefaultModel] {
        _ = defaultModelsRevision
        guard let key = defaultModelsKey(sessionID: sessionID), let data = quickActionDefaults.data(forKey: key),
              let models = try? JSONDecoder().decode([DefaultModel].self, from: data) else { return [] }
        return models
    }

    func saveDefaultModels(_ models: [DefaultModel], sessionID: String, workspaceGeneration: Int) {
        guard self.workspaceGeneration == workspaceGeneration, models.count <= DefaultModel.limit,
              Set(models.map(\.id)).count == models.count,
              let key = defaultModelsKey(sessionID: sessionID),
              let data = try? JSONEncoder().encode(models) else { return }
        quickActionDefaults.set(data, forKey: key)
        defaultModelsRevision += 1
    }

    func saveQuickActionPreference(_ preference: QuickActionPreference?, rootID: String,
                                   profile: QuickActionProfile, workspaceGeneration: Int) {
        guard self.workspaceGeneration == workspaceGeneration, let key = quickActionPreferenceKey(rootID: rootID) else { return }
        var preferences = quickActionDefaults.data(forKey: key).flatMap(QuickActionPreferences.decode) ?? .init()
        preferences[profile] = preference
        if preferences.review != nil || preferences.git != nil {
            guard let data = try? JSONEncoder().encode(preferences) else { return }
            quickActionDefaults.set(data, forKey: key)
        } else {
            quickActionDefaults.removeObject(forKey: key)
        }
        quickActionPreferenceRevision += 1
    }

    func quickActionAvailability(rootID: String) async throws -> QuickActionAvailability {
        if let failure = quickActionBlockingFailure(rootID: rootID) { throw failure }
        guard let projectID = sessionIndex[rootID]?.projectID else { throw QuickActionFailure.unavailable }
        let result = try await projectGit(templateSessionID: rootID, projectID: projectID)
        guard sessionIndex[rootID]?.projectID == projectID else { throw CancellationError() }
        if let failure = quickActionBlockingFailure(rootID: rootID) { throw failure }
        guard result.failure == nil, let state = result.state else { throw QuickActionFailure.gitUnavailable }
        return QuickActionAvailability(state: state)
    }

    func stageQuickAction(_ action: QuickAction, rootID: String, options: NewSessionOptions,
                          runConfig: NewSessionRunConfig?, workspaceGeneration: Int) async throws -> String {
        try Task.checkCancellation()
        guard self.workspaceGeneration == workspaceGeneration, isApplicationActive else { throw CancellationError() }
        let availability = try await quickActionAvailability(rootID: rootID)
        try Task.checkCancellation()
        guard self.workspaceGeneration == workspaceGeneration, isApplicationActive else { throw CancellationError() }
        guard availability.allows(action) else { throw QuickActionFailure.stateChanged }
        if let failure = quickActionBlockingFailure(rootID: rootID) { throw failure }
        guard let root = sessionIndex[rootID] else { throw QuickActionFailure.unavailable }
        return try stageSessionStart(action.prompt, composerText: action.prompt, mentions: .init(), attachments: [],
            agentConfigID: options.agentConfigID.isEmpty ? nil : options.agentConfigID,
            selections: runConfig?.selections ?? [], projectID: root.projectID ?? "", projectName: root.projectName ?? "Project",
            templateSessionID: rootID, parentSessionID: rootID, title: String(localized: action.title),
            focusesComposerOnStart: false)
    }
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
            async let workspaceRefresh: Bool = refreshWorkspaces()
            await refreshSessions()
            _ = await workspaceRefresh
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
        notifications.identify(restored?.id)
        guard account != nil else { return }
        await refreshContent()
    }

    func connect(open: @escaping @MainActor (URL) -> Void) {
        guard signInTask == nil, !isSignedIn else { return }
        authenticationGeneration += 1
        let generation = authenticationGeneration
        isSigningIn = true
        currentStatusNote = nil
        deviceAuthorization = nil
        signInTask = Task {
            defer {
                if generation == authenticationGeneration {
                    signInTask = nil
                    isSigningIn = false
                }
            }
            do {
                let authorization = try await client.beginDeviceAuthorization()
                try Task.checkCancellation()
                guard generation == authenticationGeneration else { return }
                deviceAuthorization = authorization
                if client.requiresExternalAuthorization {
                    open(authorization.verificationURL)
                }
                try await client.finishDeviceAuthorization(authorization)
                try Task.checkCancellation()
                guard generation == authenticationGeneration else { return }
                account = client.account
                notifications.identify(account?.id)
                deviceAuthorization = nil
                await refreshWorkspaces()
                await refreshSessions()
            } catch is CancellationError {
                if generation == authenticationGeneration { deviceAuthorization = nil }
            } catch {
                guard !Task.isCancelled, generation == authenticationGeneration else { return }
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
        guard signInTask != nil, !isSignedIn else { return }
        signInTask?.cancel()
        signInTask = nil
        authenticationGeneration += 1
        isSigningIn = false
        deviceAuthorization = nil
        currentStatusNote = nil
        client.signOut()
    }

    func signOut() {
        notifications.signOut()
        notificationNavigation = nil
        signInTask?.cancel()
        signInTask = nil
        isSigningIn = false
        deviceAuthorization = nil
        authenticationGeneration += 1
        workspaceRefreshGeneration += 1
        isRefreshingWorkspaces = false
        cancelSessionRefresh()
        client.signOut()
        pendingStartsByWorkspace = [:]
        pendingTabs = [:]
        outgoingByWorkspace = [:]
        outgoingStartsByWorkspace = [:]
        activeMessageSends = []
        imagePreviewScopes = [:]
        imagePreviews = SessionImagePreviewCache()
        supersededMessages = [:]
        rejectedTurnIDsByWorkspace = [:]
        tabsByWorkspace = [:]
        activeTabsByWorkspace = [:]
        archiveOperations = [:]
        activeArchiveOperations = [:]
        account = nil
        workspaces = []
        workspaceStatusNote = nil
        selectedWorkspaceID = nil
        sessions = []
        clearArchivedSessions()
        conversationCache = [:]
        filePreviews = [:]
        stopSessionSearch()
        searchBodies = [:]
        failedSearchBodies = [:]
        freshSearchBodies = [:]
        dirtySearchBodies = [:]
        sessionsByWorkspace = [:]
        currentStatusNote = nil
    }

    /// Reports success only when this request commits the current account's workspace catalog.
    @discardableResult
    func refreshWorkspaces() async -> Bool {
        guard !Task.isCancelled, account != nil else { return false }
        let generation = authenticationGeneration
        workspaceRefreshGeneration += 1
        let refreshGeneration = workspaceRefreshGeneration
        isRefreshingWorkspaces = true
        workspaceStatusNote = nil
        defer {
            if refreshGeneration == workspaceRefreshGeneration { isRefreshingWorkspaces = false }
        }
        do {
            let loaded = try await client.workspaces()
            guard !Task.isCancelled, isCurrentAuthentication(generation),
                  refreshGeneration == workspaceRefreshGeneration else { return false }
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
            tabsByWorkspace = tabsByWorkspace.filter { workspaceIDs.contains($0.key) }
            activeTabsByWorkspace = activeTabsByWorkspace.filter { workspaceIDs.contains($0.key) }
            pendingTabs = pendingTabs.filter { workspaceIDs.contains($0.key) }
            outgoingByWorkspace = outgoingByWorkspace.filter { workspaceIDs.contains($0.key) }
            outgoingStartsByWorkspace = outgoingStartsByWorkspace.filter { workspaceIDs.contains($0.key) }
            imagePreviewScopes = imagePreviewScopes.filter { workspaceIDs.contains($0.key) }
            imagePreviews.retainWorkspaces(workspaceIDs)
            supersededMessages = supersededMessages.filter { workspaceIDs.contains($0.key) }
            rejectedTurnIDsByWorkspace = rejectedTurnIDsByWorkspace.filter { workspaceIDs.contains($0.key) }
            searchBodies = searchBodies.filter { workspaceIDs.contains($0.key) }
            failedSearchBodies = failedSearchBodies.filter { workspaceIDs.contains($0.key) }
            freshSearchBodies = freshSearchBodies.filter { workspaceIDs.contains($0.key) }
            dirtySearchBodies = dirtySearchBodies.filter { workspaceIDs.contains($0.key) }
            persistSession()
            return true
        } catch LodyClientError.signedOut {
            guard !Task.isCancelled, isCurrentAuthentication(generation),
                  refreshGeneration == workspaceRefreshGeneration else { return false }
            signOut()
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled, isCurrentAuthentication(generation),
                  refreshGeneration == workspaceRefreshGeneration else { return false }
            workspaceStatusNote = StatusNote(tone: .failure, text: "Could not load workspaces.")
        }
        return false
    }

    func openPendingNotification() async {
        guard isApplicationActive, let click = notifications.pendingClick,
              let userID = notifications.userID, account?.id == userID, click.userID == userID else { return }
        notificationRoutingGeneration += 1
        let operation = notificationRoutingGeneration
        let generation = authenticationGeneration
        func isCurrent() -> Bool {
            !Task.isCancelled && isApplicationActive && notificationRoutingGeneration == operation &&
                isCurrentAuthentication(generation) && account?.id == userID &&
                notifications.pendingClick?.id == click.id && notifications.userID == userID
        }
        do {
            let workspacesRefreshed = await refreshWorkspaces()
            guard isCurrent() else { return }
            guard workspacesRefreshed else { throw LodyClientError.notConnected }
            let matches = workspaces.filter { $0.id == click.route.workspace || $0.slug == click.route.workspace }
            guard matches.count == 1, let workspace = matches.first else {
                notifications.routingError = "You no longer have access to this workspace."
                notifications.acknowledge(click.id)
                return
            }
            let selection = workspaceGeneration + (selectedWorkspaceID != workspace.id ? 1 : 0)
            if selectedWorkspaceID != workspace.id { commitWorkspaceSelection(workspace.id) }
            let refreshed = await refreshSessions(cancelWhenCallerCancels: true)
            guard isCurrent() else { return }
            guard selectedWorkspaceID == workspace.id, workspaceGeneration == selection else {
                notifications.acknowledge(click.id)
                return
            }
            guard refreshed else { throw LodyClientError.unreachable }
            let destination = try await client.notificationDestination(sessionID: click.route.sessionID, workspaceID: workspace.id)
            guard isCurrent() else { return }
            guard workspaceGeneration == selection, selectedWorkspaceID == workspace.id else {
                notifications.acknowledge(click.id)
                return
            }
            guard let destination, destination.sessionID == click.route.sessionID,
                  sessions.contains(where: { $0.id == destination.rootSessionID }) else {
                notifications.routingError = "This conversation is no longer available."
                notifications.acknowledge(click.id)
                return
            }
            if destination.isTabClosed {
                try await updateSessionMetadata(.tabClosed(false), sessionID: destination.sessionID)
                guard isCurrent(), workspaceGeneration == selection else { return }
            }
            setActiveSessionTab(destination.sessionID, rootID: destination.rootSessionID)
            notificationNavigation = NotificationNavigation(clickID: click.id, workspaceID: workspace.id,
                rootSessionID: destination.rootSessionID, sessionID: destination.sessionID)
            notificationOpenGeneration += 1
            notifications.routingError = nil
            notifications.acknowledge(click.id)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent() else { return }
            notifications.routingError = "Could not load this conversation. Try again when connected."
        }
    }

    func consumeNotificationNavigation(_ clickID: String) {
        if notificationNavigation?.clickID == clickID { notificationNavigation = nil }
    }

    func selectWorkspace(_ workspaceID: WorkspaceSummary.ID) async {
        guard workspaces.contains(where: { $0.id == workspaceID }),
              selectedWorkspaceID != workspaceID else { return }
        // A manual selection supersedes a click even while its workspace request is pending.
        notificationRoutingGeneration += 1
        if let click = notifications.pendingClick { notifications.acknowledge(click.id) }
        notifications.routingError = nil
        notificationNavigation = nil
        commitWorkspaceSelection(workspaceID)
        await refreshSessions()
    }

    private func commitWorkspaceSelection(_ workspaceID: WorkspaceSummary.ID) {
        cancelSessionRefresh()
        cancelSessionSearchIndex()
        selectedWorkspaceID = workspaceID
        sessions = sessionsByWorkspace[workspaceID] ?? []
        clearArchivedSessions()
        persistSession()
        currentStatusNote = nil
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

    @discardableResult
    func refreshSessions(restart: Bool = false, cancelWhenCallerCancels: Bool = false) async -> Bool {
        guard !Task.isCancelled, account != nil, let workspaceID = selectedWorkspaceID else { return false }
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
            ) else { return false }
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
            return true
        } catch is CancellationError {
            return false
        } catch {
            // Bridge cancellation can surface as a WebKit error rather than CancellationError.
            guard !Task.isCancelled, !refreshTask.isCancelled, isCurrentSessionRefresh(
                generation, workspaceID: workspaceID, refreshGeneration: refreshGeneration
            ) else { return false }
            switch error {
            case LodyClientError.signedOut:
                signOut()
            case LodyClientError.notConnected:
                currentStatusNote = StatusNote(tone: .info, text: "Session sync is not connected yet.")
            default:
                currentStatusNote = StatusNote(tone: .failure, text: "Could not refresh sessions.")
            }
            return false
        }
    }

    func conversation(sessionID: SessionSummary.ID) async throws -> Conversation {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = authenticationGeneration
        let loaded = try await client.conversation(sessionID: sessionID, workspaceID: workspaceID)
        guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else { throw LodyClientError.signedOut }
        let conversation = storeConversation(loaded, workspaceID: workspaceID)
        invalidateSearchBody(sessionID: sessionID, workspaceID: workspaceID)
        return conversation
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
            Task { await notifications.refresh() }
            scheduleSessionSearchIndex()
        } else {
            cancelSessionSearchIndex()
        }
    }

    func observeConversation(
        sessionID: String,
        rootSessionID: String? = nil,
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
        let updates = try await client.observeConversation(sessionID: sessionID,
            rootSessionID: rootSessionID ?? sessionSummary(sessionID)?.parentSessionID, workspaceID: workspaceID)
        var receivedFirstUpdate = false
        for try await update in updates {
            try Task.checkCancellation()
            guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else {
                throw CancellationError()
            }
            guard update.conversation.sessionID == sessionID else { throw LodyClientError.notConnected }
            if let tabs = update.sessionTabs {
                let rootID = tabs.first?.id ?? sessionSummary(sessionID)?.parentSessionID ?? sessionID
                let root = sessionSummary(rootID)
                let projectedTabs = tabs.map { tab in
                    var tab = tab
                    tab.projectID = root?.projectID
                    tab.projectName = root?.projectName
                    tab.machineName = root?.machineName
                    return tab
                }
                // An empty projection means the observer could not resolve this
                // session or its root (the root is archived elsewhere, say), not
                // that the tabs are gone. Keep the last known list: writing it
                // empty blanks the tab bar and drops the user back to Main.
                if !projectedTabs.isEmpty, tabsByWorkspace[workspaceID]?[rootID] != projectedTabs {
                    tabsByWorkspace[workspaceID, default: [:]][rootID] = projectedTabs
                }
                if let main = projectedTabs.first, let index = sessions.firstIndex(where: { $0.id == rootID }) {
                    let hasRunningTabs = projectedTabs.contains { $0.id != rootID && $0.activity == .running }
                    if sessions[index].activity != main.activity || sessions[index].hasRunningTabs != hasRunningTabs {
                        sessions[index].activity = main.activity
                        sessions[index].hasRunningTabs = hasRunningTabs
                        sessionsByWorkspace[workspaceID] = sessions
                        persistSession()
                    }
                }
                for tab in projectedTabs where outgoingStartsByWorkspace[workspaceID]?[tab.id]?.isConfirmed == true &&
                    outgoingByWorkspace[workspaceID]?[tab.id] == nil {
                    outgoingStartsByWorkspace[workspaceID]?[tab.id] = nil
                }
                if !projectedTabs.isEmpty,
                   let activeID = activeTabsByWorkspace[workspaceID]?[rootID],
                   !sessionTabs(rootID: rootID).contains(where: { $0.id == activeID && $0.isTabClosed != true }) {
                    activeTabsByWorkspace[workspaceID, default: [:]][rootID] = rootID
                }
            }
            var update = update
            update.conversation = storeConversation(update.conversation, workspaceID: workspaceID)
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
            if !receivedFirstUpdate {
                receivedFirstUpdate = true
                scheduleSessionSearchIndex()
            }
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
        try Task.checkCancellation()
        if let scope = imagePreviewScopes[workspaceID], image.localPreviewScopeID == scope,
           let data = variant == .original ? image.localOriginalData : image.localPreviewData { return data }
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
        return conversationCache[workspaceID]?[sessionID].map { imagePreviews.applying(to: $0, workspaceID: workspaceID) }
    }

    func pendingTextSend(sessionID: SessionSummary.ID) -> PendingTextSend? {
        guard let workspaceID = selectedWorkspaceID else { return nil }
        return client.pendingTextSend(sessionID: sessionID, workspaceID: workspaceID)
    }

    func outgoingMessage(sessionID: String) -> OutgoingMessage? {
        guard let workspaceID = selectedWorkspaceID else { return nil }
        return outgoingByWorkspace[workspaceID]?[sessionID]
    }

    func isSessionStartPending(sessionID: String) -> Bool {
        guard let workspaceID = selectedWorkspaceID else { return false }
        return outgoingStartsByWorkspace[workspaceID]?[sessionID]?.isConfirmed == false
    }

    func shouldFocusSessionStartComposer(sessionID: String) -> Bool {
        guard let workspaceID = selectedWorkspaceID,
              let start = outgoingStartsByWorkspace[workspaceID]?[sessionID] else { return false }
        return !start.isConfirmed && start.focusesComposerOnStart
    }

    /// Reserve both protocol IDs and show the first turn before any upload or sync.
    func stageSessionStart(_ text: String, composerText: String, mentions: ComposerMentionState,
                           attachments: [ComposerAttachment], agentConfigID: String?, selections: [RunConfigChoice],
                           projectID: String, projectName: String, templateSessionID: String,
                           parentSessionID: String? = nil, title: String? = nil,
                           focusesComposerOnStart: Bool = true) throws -> String {
        guard supportsSessionCreation, let workspaceID = selectedWorkspaceID,
              let template = sessionSummary(templateSessionID) else { throw LodyClientError.notConnected }
        if let parentSessionID {
            guard supportsSessionTabs, sessionIndex[parentSessionID] != nil else { throw LodyClientError.sessionMissing }
            if let pending = pendingTabs[workspaceID]?[parentSessionID] { throw LodyClientError.previousSendPending(pending.text) }
        } else {
            guard template.projectID == projectID || !sessions.contains(where: { $0.projectID == projectID }) else {
                throw LodyClientError.notConnected
            }
            if let pending = (pendingSessionStarts + client.pendingSessionStarts(workspaceID: workspaceID))
                .first(where: { $0.projectID == projectID }) {
                throw LodyClientError.previousSendPending(pending.text)
            }
        }
        let request = SessionTabStart(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                      attachments: attachments, selections: selections, agentConfigID: agentConfigID, title: title)
        try stageOutgoingMessage(request.text, composerText: composerText, mentions: mentions,
                                 attachments: attachments, runConfig: nil, sessionID: request.sessionID, turnID: request.turnID)
        let summary = SessionSummary(id: request.sessionID,
            title: title ?? String((request.text.isEmpty ? attachments.first?.fileName ?? "New session" : request.text).prefix(50)),
            agentName: agentConfigID ?? template.agentName, activity: .idle, preview: request.text,
            projectID: projectID, projectName: projectName, machineName: template.machineName,
            parentSessionID: parentSessionID)
        outgoingStartsByWorkspace[workspaceID, default: [:]][request.sessionID] = OutgoingSessionStart(
            request: request, summary: summary, templateSessionID: templateSessionID,
            focusesComposerOnStart: focusesComposerOnStart)
        if let parentSessionID { pendingTabs[workspaceID, default: [:]][parentSessionID] = request }
        return request.sessionID
    }

    /// Recovery can reopen without loading an agent or finding an active template.
    func restoreSessionStart(_ pending: PendingSessionStart, projectName: String, parentSessionID: String? = nil) throws -> String {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        if outgoingStartsByWorkspace[workspaceID]?[pending.id] != nil { return pending.id }
        let request: SessionTabStart
        if let parentSessionID, let tab = pendingTabs[workspaceID]?[parentSessionID] {
            request = tab
        } else {
            guard let turnID = pending.turnID,
                  client.pendingSessionStarts(workspaceID: workspaceID).contains(pending) else { throw LodyClientError.sessionMissing }
            request = SessionTabStart(sessionID: pending.id, turnID: turnID, text: pending.text, attachments: pending.attachments)
        }
        let template = sessionSummary(pending.templateSessionID)
        let summary = SessionSummary(id: request.sessionID, title: String(pending.displayText.prefix(50)),
            agentName: request.agentConfigID ?? template?.agentName ?? "Agent", activity: .idle, preview: request.text,
            projectID: pending.projectID, projectName: projectName, machineName: template?.machineName,
            parentSessionID: parentSessionID)
        if imagePreviewScopes[workspaceID] == nil { imagePreviewScopes[workspaceID] = UUID() }
        outgoingByWorkspace[workspaceID, default: [:]][request.sessionID] = OutgoingMessage(
            id: request.turnID, text: request.text, composerText: request.text, mentions: .init(),
            attachments: request.attachments, runConfig: nil, previewScopeID: imagePreviewScopes[workspaceID], delivery: .unconfirmed)
        outgoingStartsByWorkspace[workspaceID, default: [:]][request.sessionID] = OutgoingSessionStart(
            request: request, summary: summary, templateSessionID: pending.templateSessionID)
        return request.sessionID
    }

    func stageOutgoingMessage(_ text: String, composerText: String, mentions: ComposerMentionState,
                              attachments: [ComposerAttachment], runConfig: RunConfigChoice?,
                              sessionID: String, turnID: String = UUID().uuidString.lowercased()) throws {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { throw LodyClientError.emptyMessage }
        guard outgoingByWorkspace[workspaceID]?[sessionID] == nil,
              client.pendingTextSend(sessionID: sessionID, workspaceID: workspaceID) == nil else {
            throw LodyClientError.previousSendPending(outgoingMessage(sessionID: sessionID)?.text ?? "")
        }
        if imagePreviewScopes[workspaceID] == nil { imagePreviewScopes[workspaceID] = UUID() }
        outgoingByWorkspace[workspaceID, default: [:]][sessionID] = OutgoingMessage(
            id: turnID, text: text, composerText: composerText, mentions: mentions,
            attachments: attachments, runConfig: runConfig, previewScopeID: imagePreviewScopes[workspaceID]
        )
    }

    func restoreOutgoingMessage(sessionID: String) {
        guard let workspaceID = selectedWorkspaceID, outgoingByWorkspace[workspaceID]?[sessionID] == nil,
              let pending = client.pendingTextSend(sessionID: sessionID, workspaceID: workspaceID) else { return }
        if imagePreviewScopes[workspaceID] == nil { imagePreviewScopes[workspaceID] = UUID() }
        outgoingByWorkspace[workspaceID, default: [:]][sessionID] = OutgoingMessage(
            id: pending.turnID, text: pending.text, composerText: pending.text, mentions: ComposerMentionState(),
            attachments: pending.attachments, runConfig: nil, previewScopeID: imagePreviewScopes[workspaceID], delivery: .unconfirmed
        )
    }

    func retryOutgoingMessage(sessionID: String) -> Bool {
        guard let workspaceID = selectedWorkspaceID, let message = outgoingByWorkspace[workspaceID]?[sessionID],
              message.canRetry, message.delivery != .sending, message.delivery != .sent else { return false }
        outgoingByWorkspace[workspaceID]?[sessionID]?.delivery = .sending
        return true
    }

    /// Only a definitely rejected message can be edited or removed. An
    /// unconfirmed write must first be reconciled using its original turn ID.
    func takeFailedOutgoingMessage(sessionID: String) -> OutgoingMessage? {
        guard let workspaceID = selectedWorkspaceID, let message = outgoingByWorkspace[workspaceID]?[sessionID],
              case .failed = message.delivery,
              client.pendingTextSend(sessionID: sessionID, workspaceID: workspaceID) == nil else { return nil }
        outgoingByWorkspace[workspaceID]?[sessionID] = nil
        if let start = outgoingStartsByWorkspace[workspaceID]?[sessionID], !start.isConfirmed {
            outgoingStartsByWorkspace[workspaceID]?[sessionID] = nil
            if let parentID = start.summary.parentSessionID { pendingTabs[workspaceID]?[parentID] = nil }
        }
        if !message.canRetry && !message.isDeliveryRejected {
            supersededMessages[workspaceID, default: [:]][sessionID, default: []].insert(message.id)
            if let cached = conversationCache[workspaceID]?[sessionID] {
                _ = storeConversation(cached, workspaceID: workspaceID)
            }
        }
        return message
    }

    func displayedTurns(_ turns: [ConversationTurn], sessionID: String) -> [ConversationTurn] {
        let turns = selectedWorkspaceID.map { workspaceID in
            let previews = imagePreviews.applying(to: Conversation(sessionID: sessionID, turns: turns), workspaceID: workspaceID)
            return applyingDeliveryRejections(previews.turns, sessionID: sessionID, workspaceID: workspaceID)
        } ?? turns
        guard let outgoing = outgoingMessage(sessionID: sessionID) else { return turns }
        if turns.contains(where: { $0.id == outgoing.id }) {
            // Seeing history alone does not confirm that the daemon accepted
            // the metadata dispatch; keep delivery state until send confirms.
            return turns.map { $0.id == outgoing.id ? outgoing.turn : $0 }
        }
        return turns + [outgoing.turn]
    }

    @discardableResult
    func deliverOutgoingMessage(sessionID: String, workspaceID: String? = nil,
                                turnID: String? = nil) async throws -> RunConfigChoice? {
        guard let workspaceID = workspaceID ?? selectedWorkspaceID,
              let message = outgoingByWorkspace[workspaceID]?[sessionID], message.delivery == .sending,
              turnID == nil || turnID == message.id else {
            throw LodyClientError.notConnected
        }
        let generation = authenticationGeneration
        let operationKey = "\(generation):\(workspaceID):\(sessionID):\(message.id)"
        guard activeMessageSends.insert(operationKey).inserted else { throw LodyClientError.deliveryUnconfirmed }
        defer { activeMessageSends.remove(operationKey) }
        let choice: RunConfigChoice?
        let start = outgoingStartsByWorkspace[workspaceID]?[sessionID].flatMap { $0.isConfirmed ? nil : $0 }
        do {
            if let start {
                try await deliverSessionStart(start, workspaceID: workspaceID, generation: generation)
                choice = nil
            } else {
                choice = try await client.send(message.text, attachments: message.attachments,
                    runConfig: message.runConfig, turnID: message.id, sessionID: sessionID, workspaceID: workspaceID)
            }
        } catch {
            guard isCurrentAuthentication(generation),
                  outgoingByWorkspace[workspaceID]?[sessionID]?.id == message.id else { throw CancellationError() }
            if start == nil, error as? LodyClientError == .sendNotDelivered ||
                outgoingByWorkspace[workspaceID]?[sessionID]?.isDeliveryRejected == true {
                rejectOutgoingMessage(turnID: message.id, sessionID: sessionID, workspaceID: workspaceID)
                throw LodyClientError.sendNotDelivered
            }
            // The machine may confirm through synchronization after the RPC
            // times out, including while this send is still unwinding.
            if start == nil, conversationCache[workspaceID]?[sessionID]?.turns.contains(where: {
                $0.id == message.id && $0.author == .user && $0.isDeliveryConfirmed
            }) == true {
                outgoingByWorkspace[workspaceID]?[sessionID]?.delivery = .sent
                if let cached = conversationCache[workspaceID]?[sessionID] {
                    _ = storeConversation(cached, workspaceID: workspaceID)
                }
                return message.runConfig
            }
            let hasPendingStart = start.map { start in
                if let parentID = start.summary.parentSessionID { return pendingTabs[workspaceID]?[parentID] != nil }
                return client.pendingSessionStarts(workspaceID: workspaceID).contains { $0.id == sessionID }
            } ?? false
            if hasPendingStart || client.pendingTextSend(sessionID: sessionID, workspaceID: workspaceID) != nil {
                outgoingByWorkspace[workspaceID]?[sessionID]?.delivery = .unconfirmed
            } else {
                let reason: String
                switch error {
                case LodyClientError.sessionCreationRejected:
                    reason = "The session was not created. Edit to review its settings."
                case LodyClientError.sessionBusy:
                    reason = "Wait for the current reply, then retry."
                case LodyClientError.sendSuperseded:
                    reason = "A newer message took precedence. Edit to send again."
                    outgoingByWorkspace[workspaceID]?[sessionID]?.canRetry = false
                case is CancellationError:
                    reason = "Send interrupted. Retry when connected."
                default:
                    reason = "Could not send. Retry or edit this message."
                }
                outgoingByWorkspace[workspaceID]?[sessionID]?.delivery = .failed(reason)
            }
            throw error
        }
        guard isCurrentAuthentication(generation),
              outgoingByWorkspace[workspaceID]?[sessionID]?.id == message.id else { throw CancellationError() }
        if outgoingByWorkspace[workspaceID]?[sessionID]?.isDeliveryRejected == true {
            throw LodyClientError.sendNotDelivered
        }
        outgoingByWorkspace[workspaceID]?[sessionID]?.delivery = .sent
        if let cached = conversationCache[workspaceID]?[sessionID] {
            _ = storeConversation(cached, workspaceID: workspaceID)
        }
        if start != nil {
            // The visible conversation subscribes when confirmation changes.
            // Neither its first snapshot nor list refresh delays the first bubble.
            Task {
                guard isCurrentAuthentication(generation), selectedWorkspaceID == workspaceID else { return }
                await refreshSessions(restart: true)
            }
            return choice
        }
        // Refreshing the list or waiting for a stream echo does not keep the
        // message in Sending, and navigation never discards its local content.
        if let conversation = try? await client.conversation(sessionID: sessionID, workspaceID: workspaceID),
           isCurrentAuthentication(generation) {
            _ = storeConversation(conversation, workspaceID: workspaceID)
        }
        guard isCurrentAuthentication(generation) else { throw CancellationError() }
        if selectedWorkspaceID == workspaceID {
            if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                var session = sessions.remove(at: index)
                session.preview = message.text
                sessions.insert(session, at: 0)
                sessionsByWorkspace[workspaceID] = sessions
                persistSession()
            }
            await refreshSessions(restart: true)
        }
        return choice
    }

    private func deliverSessionStart(_ start: OutgoingSessionStart, workspaceID: String, generation: Int) async throws {
        let request = start.request
        defer { refreshPendingStarts(workspaceID: workspaceID, generation: generation) }
        if let parentID = start.summary.parentSessionID {
            do {
                try await client.startSessionTab(request, parentSessionID: parentID, workspaceID: workspaceID)
            } catch LodyClientError.sessionCreationRejected {
                if isCurrentAuthentication(generation) { pendingTabs[workspaceID]?[parentID] = nil }
                throw LodyClientError.sessionCreationRejected
            }
        } else if client.pendingSessionStarts(workspaceID: workspaceID).contains(where: { $0.id == request.sessionID }) {
            _ = try await client.retrySessionStart(sessionID: request.sessionID, workspaceID: workspaceID)
        } else {
            _ = try await client.startSession(request.text, attachments: request.attachments, agentConfigID: request.agentConfigID,
                selections: request.selections, projectID: start.summary.projectID ?? "", templateSessionID: start.templateSessionID,
                sessionID: request.sessionID, turnID: request.turnID, workspaceID: workspaceID)
        }
        guard isCurrentAuthentication(generation) else { throw CancellationError() }
        try Task.checkCancellation()
        outgoingStartsByWorkspace[workspaceID]?[request.sessionID]?.isConfirmed = true
        if let parentID = start.summary.parentSessionID {
            pendingTabs[workspaceID]?[parentID] = nil
        } else {
            var summaries = selectedWorkspaceID == workspaceID ? sessions : sessionsByWorkspace[workspaceID] ?? []
            if !summaries.contains(where: { $0.id == request.sessionID }) { summaries.insert(start.summary, at: 0) }
            sessionsByWorkspace[workspaceID] = summaries
            if selectedWorkspaceID == workspaceID {
                sessions = summaries
                persistSession()
            }
        }
    }

    @discardableResult
    private func storeConversation(_ value: Conversation, workspaceID: String) -> Conversation {
        let sessionID = value.sessionID
        var conversation = value.removingLocalImageData()
        rememberRejectedTurns(Set(conversation.turns.filter { $0.author == .user && $0.isDeliveryRejected }.map(\.id)),
                              sessionID: sessionID, workspaceID: workspaceID)
        conversation.turns = applyingDeliveryRejections(conversation.turns, sessionID: sessionID, workspaceID: workspaceID)
        if let ids = supersededMessages[workspaceID]?[sessionID] {
            for index in conversation.turns.indices where ids.contains(conversation.turns[index].id) &&
                !conversation.turns[index].isDeliveryRejected {
                conversation.turns[index].delivery = .superseded
            }
        }
        if let message = outgoingByWorkspace[workspaceID]?[sessionID],
           let index = conversation.turns.firstIndex(where: { $0.id == message.id }) {
            imagePreviews.store(message.preservingPreviews(in: conversation.turns[index]),
                                sessionID: sessionID, workspaceID: workspaceID)
            let accepted = conversation.turns[index].author == .user &&
                conversation.turns[index].isDeliveryConfirmed &&
                outgoingStartsByWorkspace[workspaceID]?[sessionID] == nil
            if conversation.turns[index].author == .user && conversation.turns[index].isDeliveryRejected {
                rejectOutgoingMessage(turnID: message.id, sessionID: sessionID, workspaceID: workspaceID)
            } else if message.delivery == .sent || (message.delivery != .sending && accepted) {
                client.finishTextSend(turnID: message.id, sessionID: sessionID, workspaceID: workspaceID)
                outgoingByWorkspace[workspaceID]?[sessionID] = nil
                if let start = outgoingStartsByWorkspace[workspaceID]?[sessionID], start.isConfirmed,
                   start.summary.parentSessionID == nil ||
                    tabsByWorkspace[workspaceID]?[start.summary.parentSessionID ?? ""]?.contains(where: { $0.id == sessionID }) == true {
                    outgoingStartsByWorkspace[workspaceID]?[sessionID] = nil
                }
            }
        }
        conversationCache[workspaceID, default: [:]][sessionID] = conversation
        filePreviews = filePreviews.filter { key, entry in
            key.workspaceID != workspaceID || key.sessionID != sessionID ||
                conversation.fileChanges?.first(where: { $0.id == key.turnID })?.files.first(where: { $0.path == key.path }) == entry.file
        }
        return imagePreviews.applying(to: conversation, workspaceID: workspaceID)
    }

    private func rejectOutgoingMessage(turnID: String, sessionID: String, workspaceID: String) {
        guard outgoingByWorkspace[workspaceID]?[sessionID]?.id == turnID else { return }
        rememberRejectedTurns([turnID], sessionID: sessionID, workspaceID: workspaceID)
        client.finishTextSend(turnID: turnID, sessionID: sessionID, workspaceID: workspaceID)
        outgoingByWorkspace[workspaceID]?[sessionID]?.delivery = .failed("Not delivered. Edit to send again.")
        outgoingByWorkspace[workspaceID]?[sessionID]?.canRetry = false
        outgoingByWorkspace[workspaceID]?[sessionID]?.isDeliveryRejected = true
    }

    private func rememberRejectedTurns(_ turnIDs: Set<String>, sessionID: String, workspaceID: String) {
        let previous = rejectedTurnIDsByWorkspace[workspaceID]?[sessionID] ?? []
        guard !turnIDs.isSubset(of: previous) else { return }
        rejectedTurnIDsByWorkspace[workspaceID, default: [:]][sessionID] = previous.union(turnIDs)
        persistSession()
    }

    private func applyingDeliveryRejections(_ turns: [ConversationTurn], sessionID: String,
                                           workspaceID: String) -> [ConversationTurn] {
        guard let ids = rejectedTurnIDsByWorkspace[workspaceID]?[sessionID], !ids.isEmpty else { return turns }
        return turns.map { turn in
            guard turn.author == .user, ids.contains(turn.id) else { return turn }
            var turn = turn
            turn.isDeliveryRejected = true
            turn.isDeliveryConfirmed = false
            turn.delivery = .notDelivered
            return turn
        }
    }

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
        return result
    }

    var supportsProjectGitReading: Bool { client.supportsProjectGitReading }

    func projectGit(templateSessionID: String, projectID: String) async throws -> ProjectGitResult {
        guard let workspaceID = selectedWorkspaceID else { throw LodyClientError.notConnected }
        let generation = workspaceGeneration
        let auth = authenticationGeneration
        let result = try await client.projectGit(templateSessionID: templateSessionID, projectID: projectID,
                                                 workspaceID: workspaceID)
        try Task.checkCancellation()
        guard generation == workspaceGeneration, isCurrentAuthentication(auth), selectedWorkspaceID == workspaceID else {
            throw CancellationError()
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

    private func refreshPendingStarts(workspaceID: WorkspaceSummary.ID, generation: Int) {
        guard isCurrentAuthentication(generation) else { return }
        pendingStartsByWorkspace[workspaceID] = client.pendingSessionStarts(workspaceID: workspaceID)
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
            applyMetadataChange(normalized, to: &sessions[index])
        }
        for rootID in Array((tabsByWorkspace[workspaceID] ?? [:]).keys) {
            guard var tabs = tabsByWorkspace[workspaceID]?[rootID],
                  let index = tabs.firstIndex(where: { $0.id == sessionID }) else { continue }
            applyMetadataChange(normalized, to: &tabs[index])
            tabsByWorkspace[workspaceID]?[rootID] = tabs
        }
        sessionsByWorkspace[workspaceID] = sessions
        persistSession()
        if case .tabClosed = normalized { return }
        if case .read = normalized, !interruptedRefresh { return }
        await refreshSessions(restart: true)
    }

    // The list's root summaries never carry isTabClosed — only tabs see that write.
    private func applyMetadataChange(_ change: SessionMetadataChange, to summary: inout SessionSummary) {
        switch change {
        case .tabClosed(let value): summary.isTabClosed = value
        case .pin(let value): summary.isPinned = value
        case .rename(let title): summary.title = title
        case .read(let timestamp): summary.lastReadAt = max(summary.lastReadAt ?? timestamp, timestamp)
        }
    }

    func markSessionRead(sessionID: String, lastMessageAt: Double, workspaceGeneration: Int) async throws {
        guard self.workspaceGeneration == workspaceGeneration else { throw CancellationError() }
        // Tabs live outside `sessions`; resolve through the summary so entering a
        // tab does not rewrite a receipt it already has.
        if let session = sessionSummary(sessionID),
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
        if var workspaceTabs = tabsByWorkspace[workspaceID] {
            for rootID in Array(workspaceTabs.keys) {
                guard let tabs = workspaceTabs[rootID],
                      tabs.contains(where: { archivedIDs.contains($0.id) }) else { continue }
                let kept = tabs.filter { !archivedIDs.contains($0.id) }
                workspaceTabs[rootID] = kept.isEmpty ? nil : kept
            }
            tabsByWorkspace[workspaceID] = workspaceTabs.isEmpty ? nil : workspaceTabs
        }
        pendingTabs[workspaceID]?.removeValue(forKey: sessionID)
        imagePreviews.removeSessions(archivedIDs, workspaceID: workspaceID)
        for id in archivedIDs {
            outgoingByWorkspace[workspaceID]?.removeValue(forKey: id)
            outgoingStartsByWorkspace[workspaceID]?.removeValue(forKey: id)
            supersededMessages[workspaceID]?.removeValue(forKey: id)
            conversationCache[workspaceID]?.removeValue(forKey: id)
            filePreviews = filePreviews.filter { $0.key.workspaceID != workspaceID || $0.key.sessionID != id }
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
            tabsByWorkspace[workspaceID]?.removeValue(forKey: sessionID)
            pendingTabs[workspaceID]?.removeValue(forKey: sessionID)
            rejectedTurnIDsByWorkspace[workspaceID]?.removeValue(forKey: sessionID)
            persistSession()
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
            sessionsByWorkspace: sessionsByWorkspace,
            rejectedTurnIDsByWorkspace: rejectedTurnIDsByWorkspace
        ))
    }

    @discardableResult
    private func scheduleSessionSearchIndex() -> Task<Void, Never>? {
        guard isApplicationActive, isSessionSearchActive, supportsConversations,
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
