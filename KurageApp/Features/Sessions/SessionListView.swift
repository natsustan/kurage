import SwiftUI

struct SessionNavigation {
    enum Route: Hashable {
        case conversation(SessionSummary.ID)
        case newSession(NewSessionRoute)
    }

    var selection: Route?
    var stagedSessionID: SessionSummary.ID?
    var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    var selectedSessionID: SessionSummary.ID? {
        if case .conversation(let id) = selection { return id }
        return stagedSessionID
    }

    mutating func open(_ route: Route) {
        if selection != route {
            selection = route
            stagedSessionID = nil
        }
        preferredCompactColumn = .detail
    }
}

struct SessionListView: View {
    let model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.displayScale) private var displayScale
    @State private var navigation = SessionNavigation()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var drafts = ConversationDraftStore()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility,
                            preferredCompactColumn: $navigation.preferredCompactColumn) {
            SessionSidebarView(
                model: model,
                selectedSessionID: navigation.selectedSessionID,
                isCompactWindow: horizontalSizeClass == .compact,
                isDetailPresented: navigation.preferredCompactColumn == .detail,
                onOpen: { id in
                    if navigation.selectedSessionID == id {
                        navigation.preferredCompactColumn = .detail
                    } else {
                        navigation.open(.conversation(id))
                    }
                },
                onNewSession: startNewSession,
                onOpenPending: { navigation.open(.newSession($0)) },
                onToggleSidebar: toggleSidebar
            )
            .overlay(alignment: .trailing) {
                if horizontalSizeClass != .compact {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1 / displayScale)
                        .ignoresSafeArea(.container, edges: .vertical)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 400)
        } detail: {
            SessionDetailView(route: navigation.selection, model: model, drafts: drafts,
                onStaged: { id in
                    if id == nil, let discardedID = navigation.stagedSessionID {
                        drafts.removeRoots([discardedID], workspaceGeneration: model.workspaceGeneration)
                    }
                    navigation.stagedSessionID = id
                },
                onArchived: { route in
                    guard navigation.selection == route else { return }
                    navigation = SessionNavigation()
                })
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar(removing: horizontalSizeClass == .compact ? nil : .sidebarToggle)
                .toolbar {
                    if horizontalSizeClass != .compact && columnVisibility == .detailOnly {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Show sidebar", systemImage: "sidebar.left", action: toggleSidebar)
                                .accessibilityIdentifier("toggle-session-sidebar")
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.sessions.map(\.id)) { previousIDs, ids in
            drafts.removeRoots(Set(previousIDs).subtracting(ids), workspaceGeneration: model.workspaceGeneration)
            guard let id = navigation.selectedSessionID,
                  !ids.contains(id), !model.isSessionStartPending(sessionID: id) else { return }
            navigation = SessionNavigation()
        }
    }

    private func toggleSidebar() {
        withAnimation {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    private func startNewSession(projectID: String) {
        guard let template = model.newSessionTemplate(projectID: projectID) else { return }
        navigation.open(.newSession(NewSessionRoute(
            projectID: projectID,
            projectName: template.projectName ?? "Project",
            templateSessionID: template.id,
            workspaceGeneration: model.workspaceGeneration
        )))
    }
}

private struct SessionDetailView: View {
    let route: SessionNavigation.Route?
    let model: AppModel
    let drafts: ConversationDraftStore
    let onStaged: (SessionSummary.ID?) -> Void
    let onArchived: (SessionNavigation.Route) -> Void

    var body: some View {
        switch route {
        case .conversation(let id):
            ConversationView(sessionID: id, title: model.sessionSummary(id)?.title ?? "Session",
                             model: model, draftStore: drafts, onArchived: { onArchived(.conversation(id)) })
        case .newSession(let newSession):
            NewSessionView(route: newSession, model: model, draftStore: drafts,
                           onArchived: { onArchived(.newSession(newSession)) }, onStaged: onStaged)
                .id(newSession.id)
        case nil:
            ContentUnavailableView("Select a session", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Choose a conversation or start a new chat."))
                .accessibilityIdentifier("session-detail-empty")
        }
    }
}

private struct SessionSidebarView: View {
    let model: AppModel
    let selectedSessionID: SessionSummary.ID?
    let isCompactWindow: Bool
    let isDetailPresented: Bool
    let onOpen: (SessionSummary.ID) -> Void
    let onNewSession: (String) -> Void
    let onOpenPending: (NewSessionRoute) -> Void
    let onToggleSidebar: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("sessionListMode") private var listMode: SessionListMode = .byProject
    @State private var actionRequest: SessionActionRequest?
    @State private var searchQuery = ""
    @State private var showArchivedSessions = false
    @State private var isVisible = false
    @FocusState private var isSearchFocused: Bool

    private var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private struct RefreshContext: Equatable {
        let isVisible: Bool
        let workspaceGeneration: Int
    }

    private var refreshContext: RefreshContext {
        RefreshContext(
            isVisible: scenePhase == .active && isVisible && !showArchivedSessions
                && (!isCompactWindow || !isDetailPresented),
            workspaceGeneration: model.workspaceGeneration
        )
    }

    var body: some View {
        SessionList(
            sessions: model.sessions,
            canEdit: model.supportsSessionMetadataEditing,
            canCopyURL: model.canCopySessionURL,
            onAction: { session, action in actionRequest = SessionActionRequest(session: session, action: action) },
            mode: listMode,
            keepsListHeight: !isCompactWindow && !isSearchFocused,
            selectedSessionID: isCompactWindow ? nil : selectedSessionID,
            supportsConversations: model.supportsConversations,
            canArchive: model.supportsSessionArchiving,
            archivingSessionID: model.archivingSessionID,
            isRefreshing: model.isRefreshingSessions && !model.hasCachedSessions,
            isIndexingSearch: model.isIndexingSessionSearch,
            hasIncompleteSearch: model.hasIncompleteSessionSearch,
            onRetrySearch: { Task { await model.indexSessionsForSearch() } },
            statusNote: model.statusNote,
            searchQuery: $searchQuery,
            isSearchFocused: $isSearchFocused,
            query: searchQuery,
            searchBody: { model.sessionSearchBody(sessionID: $0) },
            canCreateSession: { model.supportsSessionCreation && model.newSessionTemplate(projectID: $0) != nil },
            onOpen: onOpen,
            onChat: {
                if let template = model.sessions.first(where: { $0.projectID?.hasPrefix("local:") == true }),
                   let projectID = template.projectID { onNewSession(projectID) }
            },
            canChat: model.supportsSessionCreation && model.sessions.contains { $0.projectID?.hasPrefix("local:") == true },
            onNewSession: onNewSession
        )
        .task(id: isSearchActive) {
            if isSearchActive {
                await model.indexSessionsForSearch()
            } else {
                model.stopSessionSearch()
            }
        }
        .navigationTitle("Kurage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: isCompactWindow ? nil : .sidebarToggle)
        .refreshable { await model.refreshContent() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("Kurage")
                        .font(.headline)
                    Text(model.workspaceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
            if !model.pendingSessionStarts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(model.pendingSessionStarts) { pending in
                            Button(String(pending.displayText.prefix(50))) {
                                onOpenPending(NewSessionRoute(
                                    projectID: pending.projectID,
                                    projectName: model.sessions.first { $0.projectID == pending.projectID }?.projectName ?? "Project",
                                    templateSessionID: pending.templateSessionID,
                                    workspaceGeneration: model.workspaceGeneration
                                ))
                            }
                        }
                    } label: {
                        Label("Unconfirmed starts", systemImage: "arrow.clockwise.circle")
                    }
                    .accessibilityIdentifier("pending-session-starts")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if let email = model.account?.email {
                        Label(email, systemImage: "person.crop.circle")
                        Divider()
                    }
                    if model.workspaces.count > 1 {
                        Menu {
                            ForEach(model.workspaces) { workspace in
                                Button {
                                    Task { await model.selectWorkspace(workspace.id) }
                                } label: {
                                    if workspace.id == model.selectedWorkspaceID {
                                        Label(workspace.name, systemImage: "checkmark")
                                    } else {
                                        Text(workspace.name)
                                    }
                                }
                            }
                        } label: {
                            Label("Workspace · \(model.workspaceLabel)", systemImage: "square.stack")
                        }
                    }
                    Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        model.signOut()
                    }
                    .accessibilityIdentifier("sign-out-button")
                } label: {
                    AccountAvatar(account: model.account)
                }
                .accessibilityIdentifier("account-menu")
            }
            if !isCompactWindow {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hide sidebar", systemImage: "sidebar.left", action: onToggleSidebar)
                        .accessibilityIdentifier("toggle-session-sidebar")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("List view", selection: $listMode) {
                        Label("By Project", systemImage: "folder").tag(SessionListMode.byProject)
                        Label("By Time", systemImage: "clock.arrow.circlepath").tag(SessionListMode.byTime)
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Archived sessions", systemImage: "archivebox") {
                        showArchivedSessions = true
                    }
                    .accessibilityIdentifier("archived-sessions")
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("More options")
                }
                .accessibilityIdentifier("more-options")
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: refreshContext) {
            guard refreshContext.isVisible else { return }
            await model.refreshSessionsWhileVisible()
        }
        .modifier(SessionActionPresenter(model: model, request: $actionRequest))
        .sheet(isPresented: $showArchivedSessions) {
            ArchivedSessionsView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(36)
        }
    }
}

private struct AccountAvatar: View {
    let account: Account?

    private var initial: String {
        let name = account?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = account?.email.split(separator: "@", maxSplits: 1).first.map(String.init)
        return String((name?.isEmpty == false ? name : fallback)?.prefix(1) ?? "?").uppercased()
    }

    var body: some View {
        Group {
            if let image = account?.image, let url = URL(string: image) {
                AsyncImage(url: url) { phase in
                    if let loadedImage = phase.image {
                        loadedImage
                            .resizable()
                            .scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 34, height: 34)
        .background(.quaternary, in: Circle())
        .clipShape(Circle())
        .accessibilityLabel("Account")
    }

    private var fallback: some View {
        Text(initial)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum SessionListMode: String, Hashable {
    case byProject
    case byTime
}

private struct SessionList: View {
    let sessions: [SessionSummary]
    let canEdit: Bool
    let canCopyURL: Bool
    let onAction: (SessionSummary, SessionAction) -> Void
    let mode: SessionListMode
    let keepsListHeight: Bool
    let selectedSessionID: SessionSummary.ID?
    let supportsConversations: Bool
    let canArchive: Bool
    let archivingSessionID: SessionSummary.ID?
    let isRefreshing: Bool
    let isIndexingSearch: Bool
    let hasIncompleteSearch: Bool
    let onRetrySearch: () -> Void
    let statusNote: StatusNote?
    @Binding var searchQuery: String
    @FocusState.Binding var isSearchFocused: Bool
    let query: String
    let searchBody: (SessionSummary.ID) -> String
    let canCreateSession: (String) -> Bool
    let onOpen: (SessionSummary.ID) -> Void
    let onChat: () -> Void
    let canChat: Bool
    let onNewSession: (String) -> Void
    @State private var collapsedProjectIDs: Set<String> = []

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleSessions: [SessionSummary] {
        guard !trimmedQuery.isEmpty else { return sessions }
        return sessions.filter { session in
            SessionSearch.result(title: session.title, body: searchBody(session.id), query: trimmedQuery) != nil
        }
    }

    var body: some View {
        let visible = visibleSessions
        // Keep the search overlay alive when results switch to an empty state.
        ZStack(alignment: .top) {
            if sessions.isEmpty {
                emptyState(
                    loading: isRefreshing,
                    title: "No sessions",
                    systemImage: "bubble.left.and.bubble.right",
                    description: statusNote?.text ?? "No sessions in this workspace."
                )
            } else if !trimmedQuery.isEmpty && visible.isEmpty {
                emptyState(
                    loading: isIndexingSearch,
                    title: "No matching sessions",
                    systemImage: "magnifyingglass",
                    description: hasIncompleteSearch ? "Some messages could not be searched." : "No title or message matches.",
                    loadingTitle: "Searching messages…"
                )
            } else {
                SessionBrowser(
                    rows: rows(for: visible),
                    canEdit: canEdit,
                    canCopyURL: canCopyURL,
                    onAction: onAction,
                    canArchive: canArchive,
                    opensSessions: supportsConversations,
                    selectedSessionID: selectedSessionID,
                    bottomContentInset: Self.floatingSearchClearance + (hasIncompleteSearch && !trimmedQuery.isEmpty ? 44 : 0),
                    onOpen: onOpen,
                    onToggleProject: toggleProject,
                    onNewSession: onNewSession
                )
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The list fills the screen, including the home-indicator area. The search field
        // keeps its own safe-area padding so it floats above that area.
        .overlay(alignment: .bottom) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    SessionSearchField(query: $searchQuery, isIndexing: isIndexingSearch && !trimmedQuery.isEmpty,
                                       isFocused: $isSearchFocused)
                    Button(action: onChat) {
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(!canChat)
                    .accessibilityLabel("New chat")
                    .accessibilityIdentifier("new-chat")
                }
            }
                .overlay(alignment: .top) {
                    if hasIncompleteSearch && !trimmedQuery.isEmpty {
                        Button("Search incomplete. Retry", action: onRetrySearch)
                            .font(.footnote)
                            .buttonStyle(.borderedProminent)
                            .disabled(isIndexingSearch)
                            .accessibilityIdentifier("retry-session-search")
                            .offset(y: -44)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .safeAreaPadding(.bottom)
        }
        // Only the detail column avoids the keyboard during detail input, so the list
        // and floating search stay in place; sidebar search still avoids the keyboard.
        // Both regions are ignored together so the list still reaches the screen edge.
        .ignoresSafeArea(keepsListHeight ? [.container, .keyboard] : .container, edges: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
    }

    /// Capsule height plus the gap under it, so the last row can scroll clear of the floating field.
    private static let floatingSearchClearance: CGFloat = 72

    private func rows(for visible: [SessionSummary]) -> [SessionBrowserRow] {
        var rows: [SessionBrowserRow] = []
        if let statusNote {
            rows.append(.note(text: statusNote.text, failure: statusNote.tone == .failure))
        }
        if !supportsConversations {
            rows.append(.banner("Only the session list is available. Conversations are not supported yet."))
        }
        var pinned: [SessionSummary] = []
        var unpinned: [SessionSummary] = []
        for session in visible {
            if session.isPinned == true {
                pinned.append(session)
            } else {
                unpinned.append(session)
            }
        }
        if !pinned.isEmpty {
            rows.append(.title("Pinned"))
            rows.append(contentsOf: sessionRows(pinned))
        }
        if mode == .byProject || !unpinned.isEmpty {
            rows.append(.title(mode == .byProject ? "Projects" : "Recent"))
        }
        if mode == .byProject {
            // Keep local project headers available for New session even when all
            // their sessions have moved into Pinned.
            for group in SessionProjectGroup.make(from: visible) {
                let groupSessions = group.sessions.filter { $0.isPinned != true }
                guard !groupSessions.isEmpty || canCreateSession(group.id) else { continue }
                let collapsed = trimmedQuery.isEmpty && collapsedProjectIDs.contains(group.id)
                rows.append(.project(
                    id: group.id,
                    name: group.name,
                    collapsed: collapsed,
                    unassigned: group.id == SessionProjectGroup.unassignedID,
                    canCreate: canCreateSession(group.id)
                ))
                if !collapsed {
                    rows.append(contentsOf: sessionRows(groupSessions))
                }
            }
        } else {
            rows.append(contentsOf: sessionRows(unpinned))
        }
        return rows
    }

    private func sessionRows(_ sessions: [SessionSummary]) -> [SessionBrowserRow] {
        sessions.map { session in
            let snippet = trimmedQuery.isEmpty
                ? nil
                : SessionSearch.result(title: session.title, body: searchBody(session.id), query: trimmedQuery)?.snippet
            return .session(session, snippet: snippet, dimmed: archivingSessionID == session.id)
        }
    }

    private func toggleProject(_ id: String) {
        withAnimation(.snappy) {
            if collapsedProjectIDs.contains(id) {
                collapsedProjectIDs.remove(id)
            } else {
                collapsedProjectIDs.insert(id)
            }
        }
    }

    private func emptyState(
        loading: Bool,
        title: String,
        systemImage: String,
        description: String,
        loadingTitle: String = "Loading sessions…"
    ) -> some View {
        ScrollView {
            if loading {
                ProgressView(loadingTitle)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private enum SessionBrowserRow: Hashable {
    case note(text: String, failure: Bool)
    case banner(String)
    case title(String)
    case project(id: String, name: String, collapsed: Bool, unassigned: Bool, canCreate: Bool)
    case session(SessionSummary, snippet: String?, dimmed: Bool)

    var id: String {
        switch self {
        case .note: "note"
        case .banner: "banner"
        case .title(let title): "title-\(title)"
        case let .project(id, _, _, _, _): "project-\(id)"
        case let .session(session, _, _): "session-\(session.id)"
        }
    }
}

private struct SessionBrowser: UIViewControllerRepresentable {
    var rows: [SessionBrowserRow]
    var canEdit: Bool
    var canCopyURL: Bool
    var onAction: (SessionSummary, SessionAction) -> Void
    var canArchive: Bool
    var opensSessions: Bool
    var selectedSessionID: SessionSummary.ID?
    var bottomContentInset: CGFloat
    var onOpen: (SessionSummary.ID) -> Void
    var onToggleProject: (String) -> Void
    var onNewSession: (String) -> Void

    func makeUIViewController(context: Context) -> SessionBrowserController {
        SessionBrowserController()
    }

    func updateUIViewController(_ controller: SessionBrowserController, context: Context) {
        controller.loadViewIfNeeded()
        controller.canEdit = canEdit
        controller.canCopyURL = canCopyURL
        controller.onAction = onAction
        controller.onOpen = onOpen
        controller.onToggleProject = onToggleProject
        controller.onNewSession = onNewSession
        controller.bottomContentInset = bottomContentInset
        controller.refreshAction = context.environment.refresh
        controller.render(rows: rows, canArchive: canArchive, opensSessions: opensSessions,
                          selectedSessionID: selectedSessionID)
    }

    static func dismantleUIViewController(_ controller: SessionBrowserController, coordinator: ()) {
        controller.cancelRefresh()
    }
}

/// UITableView swipe actions, matching FlowDown's conversation list.
/// `completion(false)` closes the swipe and leaves the row's height alone.
private final class SessionBrowserController: UIViewController, UITableViewDelegate {
    var canEdit = false
    var canCopyURL = false
    var onAction: ((SessionSummary, SessionAction) -> Void)?
    var refreshAction: RefreshAction?
    private var refreshTask: Task<Void, Never>?
    var onOpen: ((SessionSummary.ID) -> Void)?
    var onToggleProject: ((String) -> Void)?
    var onNewSession: ((String) -> Void)?
    private var canArchive = false
    private var opensSessions = false
    private var selectedSessionID: SessionSummary.ID?
    var bottomContentInset: CGFloat = 0 {
        didSet { applyBottomContentInset() }
    }
    private var rows: [String: SessionBrowserRow] = [:]
    private var orderedRowIDs: [String] = []
    private var projectHeaders: [String: SessionBrowserRow] = [:]
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var dataSource: UITableViewDiffableDataSource<String, String>!

    override func loadView() {
        tableView.accessibilityIdentifier = "session-browser"
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 52
        tableView.keyboardDismissMode = .interactive
        // The list fills the home-indicator area. Hide the pocket that would paint a
        // system background over the rows scrolling through it.
        tableView.bottomEdgeEffect.isHidden = true
        tableView.delegate = self
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        tableView.alwaysBounceVertical = true
        tableView.register(SessionBrowserCell.self, forCellReuseIdentifier: "row")
        tableView.register(SessionProjectHeader.self, forHeaderFooterViewReuseIdentifier: "project")
        dataSource = UITableViewDiffableDataSource(tableView: tableView) { [weak self] tableView, indexPath, itemID in
            let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! SessionBrowserCell
            cell.configure(self?.rows[itemID], isCurrent: itemID == self?.selectedSessionID.map { "session-\($0)" })
            return cell
        }
        dataSource.defaultRowAnimation = .fade
        view = tableView
        applyBottomContentInset()
    }

    @objc private func refresh() {
        guard refreshTask == nil, let refreshAction else {
            if refreshTask == nil { tableView.refreshControl?.endRefreshing() }
            return
        }
        refreshTask = Task { [weak self] in
            await refreshAction()
            self?.tableView.refreshControl?.endRefreshing()
            self?.refreshTask = nil
        }
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        tableView.refreshControl?.endRefreshing()
    }

    private func applyBottomContentInset() {
        guard tableView.contentInset.bottom != bottomContentInset else { return }
        tableView.contentInset.bottom = bottomContentInset
        tableView.verticalScrollIndicatorInsets.bottom = bottomContentInset
    }

    func render(rows: [SessionBrowserRow], canArchive: Bool, opensSessions: Bool,
                selectedSessionID: SessionSummary.ID?) {
        self.canArchive = canArchive
        self.opensSessions = opensSessions
        let previousRows = self.rows
        let previousSelection = self.selectedSessionID
        self.selectedSessionID = selectedSessionID
        let nextRows = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let nextIDs = rows.map(\.id)
        guard orderedRowIDs != nextIDs || previousRows != nextRows || previousSelection != selectedSessionID else { return }
        orderedRowIDs = nextIDs
        let previousSnapshot = dataSource.snapshot()
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        var sectionID = "sessions"
        snapshot.appendSections([sectionID])
        var nextHeaders: [String: SessionBrowserRow] = [:]
        for row in rows {
            if case .project = row {
                // Plain-table section headers pin natively until the next project
                // pushes them away, including their collapse and creation controls.
                sectionID = row.id
                snapshot.appendSections([sectionID])
                nextHeaders[sectionID] = row
            } else {
                snapshot.appendItems([row.id], toSection: sectionID)
            }
        }
        self.rows = nextRows
        projectHeaders = nextHeaders
        // Update only changed, retained rows. One snapshot preserves swipe deletion
        // animations without a second animated pass over every visible cell.
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { id in
            previousRows[id] != nil && (previousRows[id] != nextRows[id]
                || (previousSelection != selectedSessionID &&
                    (id == previousSelection.map { "session-\($0)" } || id == selectedSessionID.map { "session-\($0)" })))
        })
        snapshot.reloadSections(snapshot.sectionIdentifiers.filter { id in
            nextHeaders[id] != nil && previousRows[id] != nil &&
                previousRows[id] != nextHeaders[id]
        })
        let interacting = tableView.isDragging || tableView.isDecelerating ||
            tableView.refreshControl?.isRefreshing == true
        dataSource.apply(snapshot, animatingDifferences: !previousSnapshot.itemIdentifiers.isEmpty && !interacting)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sectionID = dataSource.snapshot().sectionIdentifiers[section]
        guard let row = projectHeaders[sectionID],
              let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "project") as? SessionProjectHeader
        else { return nil }
        header.configure(row)
        header.onToggleProject = { [weak self] id in self?.onToggleProject?(id) }
        header.onNewSession = { [weak self] id in self?.onNewSession?(id) }
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let sectionID = dataSource.snapshot().sectionIdentifiers[section]
        return projectHeaders[sectionID] == nil ? 0 : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        0
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id] else { return }
        switch row {
        case let .session(session, _, _):
            if opensSessions { onOpen?(session.id) }
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard canArchive,
              let id = dataSource.itemIdentifier(for: indexPath),
              case let .session(session, _, _) = rows[id]
        else { return nil }
        let action = UIContextualAction(style: .destructive, title: "Archive") { [weak self] _, _, completion in
            completion(false)
            Task { @MainActor in
                self?.onAction?(session, .archive)
            }
        }
        action.image = UIImage(systemName: "archivebox")
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath),
              case let .session(session, _, dimmed) = rows[id], !dimmed else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions: [UIAction] = []
            if canEdit {
                actions.append(UIAction(title: session.isPinned == true ? "Unpin" : "Pin",
                                        image: UIImage(systemName: session.isPinned == true ? "pin.slash" : "pin")) { [weak self] _ in
                    self?.onAction?(session, .pin)
                })
                actions.append(UIAction(title: "Rename session", image: UIImage(systemName: "pencil")) { [weak self] _ in
                    self?.onAction?(session, .rename)
                })
            }
            actions.append(UIAction(title: "Copy Session URL", image: UIImage(systemName: "link"),
                                    attributes: canCopyURL ? [] : .disabled) { [weak self] _ in
                self?.onAction?(session, .copyURL)
            })
            if canArchive {
                actions.append(UIAction(title: "Archive", image: UIImage(systemName: "archivebox"), attributes: .destructive) { [weak self] _ in
                    self?.onAction?(session, .archive)
                })
            }
            return UIMenu(children: actions)
        }
    }
}

/// Keeps the new-session glyph with the title. Taps still cover the full row
/// height in this column; that target is not part of the button bounds, so it
/// cannot increase the project row height.
private final class ProjectNewSessionButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let row = superview else { return super.point(inside: point, with: event) }
        let rowPoint = convert(point, to: row)
        guard row.bounds.contains(rowPoint) else { return false }
        let column = convert(bounds, to: row)
        return (column.minX...column.maxX).contains(rowPoint.x)
    }
}

private final class SessionProjectHeader: UITableViewHeaderFooterView {
    private let toggleButton = UIButton(type: .custom)
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let newSessionButton = ProjectNewSessionButton(configuration: .plain())
    private lazy var toggleTrailingToNewSession = toggleButton.trailingAnchor.constraint(
        equalTo: newSessionButton.leadingAnchor, constant: -8
    )
    private lazy var toggleTrailingToContent = toggleButton.trailingAnchor.constraint(
        equalTo: contentView.trailingAnchor, constant: -16
    )
    private var projectID: String?
    var onToggleProject: ((String) -> Void)?
    var onNewSession: ((String) -> Void)?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        var background = UIBackgroundConfiguration.clear()
        // Use concrete color components so UIKit keeps an opaque surface
        // instead of converting the semantic background into a pinned material.
        background.backgroundColor = UIColor { traits in
            UIColor(cgColor: UIColor.systemBackground.resolvedColor(with: traits).cgColor)
        }
        backgroundConfiguration = background
        isAccessibilityElement = false
        toggleButton.isAccessibilityElement = true
        toggleButton.accessibilityTraits.insert(.header)
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.addAction(UIAction { [weak self] _ in
            guard let self, let projectID else { return }
            onToggleProject?(projectID)
        }, for: .primaryActionTriggered)
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .label
        icon.isAccessibilityElement = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.isAccessibilityElement = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.addSubview(icon)
        toggleButton.addSubview(titleLabel)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "square.and.pencil")
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = .zero
        newSessionButton.configuration = configuration
        newSessionButton.translatesAutoresizingMaskIntoConstraints = false
        newSessionButton.addAction(UIAction { [weak self] _ in
            guard let self, let projectID else { return }
            onNewSession?(projectID)
        }, for: .primaryActionTriggered)
        contentView.addSubview(toggleButton)
        contentView.addSubview(newSessionButton)
        NSLayoutConstraint.activate([
            toggleButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            toggleButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            toggleButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            toggleTrailingToContent,
            icon.leadingAnchor.constraint(equalTo: toggleButton.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: toggleButton.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: toggleButton.topAnchor, constant: 13),
            titleLabel.bottomAnchor.constraint(equalTo: toggleButton.bottomAnchor, constant: -13),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            newSessionButton.widthAnchor.constraint(equalToConstant: 44),
            newSessionButton.heightAnchor.constraint(equalTo: titleLabel.heightAnchor),
            newSessionButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            newSessionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(_ row: SessionBrowserRow) {
        guard case let .project(id, name, collapsed, unassigned, canCreate) = row else { return }
        projectID = id
        titleLabel.text = name
        icon.image = unassigned
            ? UIImage(systemName: collapsed ? "bubble.left" : "bubble.left.fill")
            : UIImage(named: collapsed ? "folder-closed" : "folder-open")?.withRenderingMode(.alwaysTemplate)
        toggleButton.accessibilityIdentifier = "project-header-\(id)"
        toggleButton.accessibilityLabel = name
        toggleButton.accessibilityValue = collapsed ? "Collapsed" : "Expanded"
        toggleButton.accessibilityHint = "Collapses or expands this project's sessions"
        newSessionButton.isHidden = !canCreate
        accessibilityElements = canCreate ? [toggleButton, newSessionButton] : [toggleButton]
        toggleTrailingToNewSession.isActive = false
        toggleTrailingToContent.isActive = false
        (canCreate ? toggleTrailingToNewSession : toggleTrailingToContent).isActive = true
        newSessionButton.accessibilityLabel = "New session in \(name)"
        newSessionButton.accessibilityIdentifier = "new-session-\(id)"
    }
}

private final class SessionBrowserCell: UITableViewCell {
    private let currentBackground = UIView()
    private let leadingSlot = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let unreadDot = UIView()
    private let titleLabel = UILabel()
    private let snippetLabel = UILabel()
    private let textStack = UIStackView()
    private let rowStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        backgroundConfiguration = .clear()
        selectionStyle = .none
        focusStyle = .custom
        focusEffect = nil
        currentBackground.backgroundColor = .tertiarySystemFill
        currentBackground.isUserInteractionEnabled = false
        currentBackground.isAccessibilityElement = false
        currentBackground.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(currentBackground)
        spinner.hidesWhenStopped = true
        spinner.isAccessibilityElement = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        leadingSlot.addSubview(spinner)
        unreadDot.backgroundColor = .systemBlue
        unreadDot.layer.cornerRadius = 4
        unreadDot.isAccessibilityElement = false
        unreadDot.translatesAutoresizingMaskIntoConstraints = false
        leadingSlot.addSubview(unreadDot)
        leadingSlot.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        snippetLabel.font = .preferredFont(forTextStyle: .subheadline)
        snippetLabel.adjustsFontForContentSizeCategory = true
        snippetLabel.textColor = .secondaryLabel
        snippetLabel.numberOfLines = 1
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentHuggingPriority(.required, for: .vertical)
        textStack.setContentCompressionResistancePriority(.required, for: .vertical)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(snippetLabel)
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.addArrangedSubview(leadingSlot)
        rowStack.addArrangedSubview(textStack)
        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            currentBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            currentBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            currentBackground.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            currentBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),
            unreadDot.centerXAnchor.constraint(equalTo: leadingSlot.centerXAnchor),
            unreadDot.centerYAnchor.constraint(equalTo: leadingSlot.centerYAnchor),
            leadingSlot.widthAnchor.constraint(equalToConstant: 20),
            leadingSlot.heightAnchor.constraint(equalToConstant: 20),
            spinner.centerXAnchor.constraint(equalTo: leadingSlot.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: leadingSlot.centerYAnchor),
            rowStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        currentBackground.layer.cornerRadius = currentBackground.bounds.height / 2
    }

    func configure(_ row: SessionBrowserRow?, isCurrent: Bool = false) {
        currentBackground.isHidden = !isCurrent
        accessibilityTraits = isCurrent ? [.button, .selected] : []
        accessoryType = .none
        accessibilityHint = nil
        accessibilityValue = nil
        spinner.stopAnimating()
        unreadDot.isHidden = true
        leadingSlot.isHidden = true
        snippetLabel.isHidden = true
        titleLabel.textColor = .label
        titleLabel.font = .preferredFont(forTextStyle: .body)
        contentView.alpha = 1
        rowStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
        rowStack.isLayoutMarginsRelativeArrangement = true
        guard let row else {
            titleLabel.text = nil
            accessibilityIdentifier = nil
            return
        }
        accessibilityIdentifier = nil
        switch row {
        case let .note(text, failure):
            titleLabel.text = text
            titleLabel.font = .preferredFont(forTextStyle: .subheadline)
            titleLabel.textColor = failure ? .systemRed : .secondaryLabel
            accessibilityLabel = text
        case let .banner(text):
            titleLabel.text = text
            titleLabel.font = .preferredFont(forTextStyle: .footnote)
            titleLabel.textColor = .secondaryLabel
            accessibilityLabel = text
        case let .title(text):
            titleLabel.text = text
            titleLabel.font = UIFont.sessionTitle()
            rowStack.directionalLayoutMargins.top = 20
            rowStack.directionalLayoutMargins.bottom = 18
            accessibilityLabel = text
        case .project:
            // Projects are rendered as section headers, never as cells.
            break
        case let .session(session, snippet, dimmed):
            accessibilityTraits = isCurrent ? [.button, .selected] : [.button]
            titleLabel.text = session.title
            if let snippet {
                snippetLabel.text = snippet
                snippetLabel.isHidden = false
            }
            leadingSlot.isHidden = false
            unreadDot.isHidden = !session.isUnread || session.isRunningInList
            if session.isRunningInList {
                spinner.startAnimating()
            }
            accessibilityIdentifier = "session-\(session.id)"
            contentView.alpha = dimmed ? 0.45 : 1
            accessibilityLabel = snippet.map { "\(session.title). \($0)" } ?? session.title
            accessibilityValue = "\(session.isRunningInList ? "Running" : "Idle"), \(session.isUnread ? "Unread" : "Read")"
        }
    }
}

private extension UIFont {
    static func sessionTitle() -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .title3)
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

private struct SessionSearchField: View {
    @Binding var query: String
    let isIndexing: Bool
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search chats", text: $query)
                .fontWeight(.medium)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .accessibilityIdentifier("session-search")
            if isIndexing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching messages")
            }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("session-search-clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .glassEffect(.regular, in: .capsule)
    }
}

private extension View {
    func sessionListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

#Preview("Sessions") {
    SessionListPreview()
}

private struct SessionListPreview: View {
    @State private var model = AppModel(client: FixtureLodyClient(startsSignedIn: true))

    var body: some View {
        SessionListView(model: model)
            .task { await model.adoptExistingAccount() }
    }
}
