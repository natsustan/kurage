import SwiftUI

struct SessionListView: View {
    let model: AppModel
    @AppStorage("sessionListMode") private var listMode: SessionListMode = .byProject
    @State private var archiveFailed = false
    @State private var archivingSessionID: SessionSummary.ID?
    @State private var searchQuery = ""
    @State private var showArchivedSessions = false
    @State private var path = NavigationPath()

    private var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            SessionList(
                sessions: model.sessions,
                mode: listMode,
                supportsConversations: model.supportsConversations,
                canArchive: model.supportsSessionArchiving,
                archivingSessionID: archivingSessionID,
                isRefreshing: model.isRefreshingSessions && !model.hasCachedSessions,
                isIndexingSearch: model.isIndexingSessionSearch,
                statusNote: model.statusNote,
                searchQuery: $searchQuery,
                query: searchQuery,
                searchBody: { model.sessionSearchBody(sessionID: $0) },
                onOpen: { path.append($0) },
                onArchive: { session in Task { await archive(session) } }
            )
            .task(id: isSearchActive) {
                if isSearchActive {
                    await model.indexSessionsForSearch()
                } else {
                    model.stopSessionSearch()
                }
            }
            .navigationTitle("Kurage")
            .navigationSubtitle(model.workspaceLabel)
            .refreshable { await model.refreshContent() }
            .navigationDestination(for: SessionSummary.ID.self) { sessionID in
                ConversationView(
                    sessionID: sessionID,
                    title: model.sessions.first { $0.id == sessionID }?.title ?? "Session",
                    model: model
                )
            }
            .toolbar {
                if model.workspaces.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
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
                            Label("Workspace", systemImage: "square.stack")
                        }
                        .accessibilityIdentifier("workspace-picker")
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
                        Divider()
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            model.signOut()
                        }
                        .accessibilityIdentifier("sign-out-button")
                    } label: {
                        Image(systemName: "ellipsis")
                            .accessibilityLabel("More options")
                    }
                    .accessibilityIdentifier("more-options")
                }
            }
        }
        .alert("Could not archive this session.", isPresented: $archiveFailed) {
            Button("OK", role: .cancel) {}
        }
        .sheet(isPresented: $showArchivedSessions) {
            ArchivedSessionsView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(36)
        }
    }

    private func archive(_ session: SessionSummary) async {
        guard archivingSessionID == nil else { return }
        archivingSessionID = session.id
        defer { archivingSessionID = nil }
        do {
            try await model.archiveSession(sessionID: session.id)
        } catch is CancellationError {
            return
        } catch {
            archiveFailed = true
        }
    }
}

private enum SessionListMode: String, Hashable {
    case byProject
    case byTime
}

private struct SessionList: View {
    let sessions: [SessionSummary]
    let mode: SessionListMode
    let supportsConversations: Bool
    let canArchive: Bool
    let archivingSessionID: SessionSummary.ID?
    let isRefreshing: Bool
    let isIndexingSearch: Bool
    let statusNote: StatusNote?
    @Binding var searchQuery: String
    let query: String
    let searchBody: (SessionSummary.ID) -> String
    let onOpen: (SessionSummary.ID) -> Void
    let onArchive: (SessionSummary) -> Void
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
        Group {
            if sessions.isEmpty {
                emptyState(
                    loading: isRefreshing,
                    title: "No sessions",
                    systemImage: "bubble.left.and.bubble.right",
                    description: statusNote?.text ?? "No sessions in this workspace."
                )
            } else if !trimmedQuery.isEmpty && visibleSessions.isEmpty {
                emptyState(
                    loading: isIndexingSearch,
                    title: "No matching sessions",
                    systemImage: "magnifyingglass",
                    description: "No title or message matches.",
                    loadingTitle: "Searching messages…"
                )
            } else {
                SessionBrowser(
                    rows: rows,
                    canArchive: canArchive,
                    opensSessions: supportsConversations,
                    bottomContentInset: Self.floatingSearchClearance,
                    onOpen: onOpen,
                    onToggleProject: toggleProject,
                    onArchive: onArchive
                )
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The list fills the screen, including the home-indicator area. The search field
        // keeps its own safe-area padding so it floats above that area.
        .overlay(alignment: .bottom) {
            SessionSearchField(query: $searchQuery, isIndexing: isIndexingSearch && !trimmedQuery.isEmpty)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .safeAreaPadding(.bottom)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
    }

    /// Capsule height plus the gap under it, so the last row can scroll clear of the floating field.
    private static let floatingSearchClearance: CGFloat = 72

    private var rows: [SessionBrowserRow] {
        var rows: [SessionBrowserRow] = []
        if let statusNote {
            rows.append(.note(text: statusNote.text, failure: statusNote.tone == .failure))
        }
        if !supportsConversations {
            rows.append(.banner("Only the session list is available. Conversations are not supported yet."))
        }
        rows.append(.title(mode == .byProject ? "Projects" : "Recent"))
        if mode == .byProject {
            for group in SessionProjectGroup.make(from: visibleSessions) {
                let collapsed = trimmedQuery.isEmpty && collapsedProjectIDs.contains(group.id)
                rows.append(.project(
                    id: group.id,
                    name: group.name,
                    collapsed: collapsed,
                    unassigned: group.id == SessionProjectGroup.unassignedID
                ))
                if !collapsed {
                    rows.append(contentsOf: sessionRows(group.sessions))
                }
            }
        } else {
            rows.append(contentsOf: sessionRows(visibleSessions))
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
        Group {
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
    case project(id: String, name: String, collapsed: Bool, unassigned: Bool)
    case session(SessionSummary, snippet: String?, dimmed: Bool)

    var id: String {
        switch self {
        case .note: "note"
        case .banner: "banner"
        case .title: "title"
        case let .project(id, _, _, _): "project-\(id)"
        case let .session(session, _, _): "session-\(session.id)"
        }
    }
}

private struct SessionBrowser: UIViewControllerRepresentable {
    var rows: [SessionBrowserRow]
    var canArchive: Bool
    var opensSessions: Bool
    var bottomContentInset: CGFloat
    var onOpen: (SessionSummary.ID) -> Void
    var onToggleProject: (String) -> Void
    var onArchive: (SessionSummary) -> Void

    func makeUIViewController(context: Context) -> SessionBrowserController {
        SessionBrowserController()
    }

    func updateUIViewController(_ controller: SessionBrowserController, context: Context) {
        controller.loadViewIfNeeded()
        controller.onOpen = onOpen
        controller.onToggleProject = onToggleProject
        controller.onArchive = onArchive
        controller.bottomContentInset = bottomContentInset
        controller.render(rows: rows, canArchive: canArchive, opensSessions: opensSessions)
    }
}

/// UITableView swipe actions, matching FlowDown's conversation list.
/// `completion(false)` closes the swipe and leaves the row's height alone.
/// The confirmation is presented by this controller, not by rebuilding the list.
private final class SessionBrowserController: UIViewController, UITableViewDelegate {
    var onOpen: ((SessionSummary.ID) -> Void)?
    var onToggleProject: ((String) -> Void)?
    var onArchive: ((SessionSummary) -> Void)?
    private var canArchive = false
    private var opensSessions = false
    var bottomContentInset: CGFloat = 0 {
        didSet { applyBottomContentInset() }
    }
    private var rows: [String: SessionBrowserRow] = [:]
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var dataSource: UITableViewDiffableDataSource<Int, String>!

    override func loadView() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        tableView.keyboardDismissMode = .interactive
        // The list fills the home-indicator area. Hide the pocket that would paint a
        // system background over the rows scrolling through it.
        tableView.bottomEdgeEffect.isHidden = true
        tableView.delegate = self
        tableView.register(SessionBrowserCell.self, forCellReuseIdentifier: "row")
        dataSource = UITableViewDiffableDataSource(tableView: tableView) { [weak self] tableView, indexPath, itemID in
            let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! SessionBrowserCell
            cell.configure(self?.rows[itemID])
            return cell
        }
        dataSource.defaultRowAnimation = .fade
        view = tableView
        applyBottomContentInset()
    }

    private func applyBottomContentInset() {
        guard tableView.contentInset.bottom != bottomContentInset else { return }
        tableView.contentInset.bottom = bottomContentInset
        tableView.verticalScrollIndicatorInsets.bottom = bottomContentInset
    }

    func render(rows: [SessionBrowserRow], canArchive: Bool, opensSessions: Bool) {
        self.canArchive = canArchive
        self.opensSessions = opensSessions
        self.rows = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let hadRows = !dataSource.snapshot().itemIdentifiers.isEmpty
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(rows.map(\.id), toSection: 0)
        // FlowDown fades the removed row and lets the rows below close the gap.
        // Reconfiguring every row in the same update cancels that and snaps the list.
        dataSource.apply(snapshot, animatingDifferences: hadRows)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let visible = tableView.indexPathsForVisibleRows ?? []
            let visibleIDs = visible.compactMap { dataSource.itemIdentifier(for: $0) }
            guard !visibleIDs.isEmpty else { return }
            var refresh = dataSource.snapshot()
            let current = Set(refresh.itemIdentifiers)
            let stable = visibleIDs.filter { current.contains($0) }
            guard !stable.isEmpty else { return }
            refresh.reconfigureItems(stable)
            dataSource.apply(refresh, animatingDifferences: true)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id] else { return }
        switch row {
        case let .session(session, _, _):
            if opensSessions { onOpen?(session.id) }
        case let .project(id, _, _, _):
            onToggleProject?(id)
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
                self?.confirmArchive(session)
            }
        }
        action.image = UIImage(systemName: "archivebox")
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func confirmArchive(_ session: SessionSummary) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "Archive \"\(session.title)\"?",
            message: "This removes the task from the remote task list.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .destructive) { [weak self] _ in
            self?.onArchive?(session)
        })
        present(alert, animated: true) {
            Self.identifyConfirmButton(in: alert.view)
        }
    }

    private static func identifyConfirmButton(in view: UIView) {
        if view.accessibilityLabel == "OK" {
            view.accessibilityIdentifier = "archive-confirm"
        }
        view.subviews.forEach(identifyConfirmButton)
    }
}

private final class SessionBrowserCell: UITableViewCell {
    private let icon = UIImageView()
    private let leadingSlot = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let snippetLabel = UILabel()
    private let textStack = UIStackView()
    private let rowStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        spinner.hidesWhenStopped = true
        spinner.isAccessibilityElement = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        leadingSlot.addSubview(spinner)
        leadingSlot.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.numberOfLines = 1
        snippetLabel.font = .preferredFont(forTextStyle: .subheadline)
        snippetLabel.textColor = .secondaryLabel
        snippetLabel.numberOfLines = 1
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(snippetLabel)
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.addArrangedSubview(leadingSlot)
        rowStack.addArrangedSubview(icon)
        rowStack.addArrangedSubview(textStack)
        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            leadingSlot.widthAnchor.constraint(equalToConstant: 20),
            leadingSlot.heightAnchor.constraint(equalToConstant: 20),
            spinner.centerXAnchor.constraint(equalTo: leadingSlot.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: leadingSlot.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 18),
            rowStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            rowStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(_ row: SessionBrowserRow?) {
        accessoryType = .none
        accessibilityHint = nil
        accessibilityValue = nil
        spinner.stopAnimating()
        leadingSlot.isHidden = true
        icon.isHidden = true
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
        case let .project(id, name, collapsed, unassigned):
            titleLabel.text = name
            titleLabel.font = .preferredFont(forTextStyle: .headline)
            icon.isHidden = false
            if unassigned {
                icon.image = UIImage(systemName: collapsed ? "bubble.left" : "bubble.left.fill")
                icon.tintColor = .label
            } else {
                icon.image = UIImage(named: collapsed ? "folder-closed" : "folder-open")?.withRenderingMode(.alwaysTemplate)
                icon.tintColor = .label
            }
            rowStack.directionalLayoutMargins.top = 18
            rowStack.directionalLayoutMargins.bottom = 8
            accessibilityIdentifier = "project-header-\(id)"
            accessibilityLabel = name
            accessibilityValue = collapsed ? "Collapsed" : "Expanded"
            accessibilityHint = "Collapses or expands this project's sessions"
        case let .session(session, snippet, dimmed):
            titleLabel.text = session.title
            if let snippet {
                snippetLabel.text = snippet
                snippetLabel.isHidden = false
            }
            leadingSlot.isHidden = false
            if session.activity == .running {
                spinner.startAnimating()
            }
            accessibilityIdentifier = "session-\(session.id)"
            contentView.alpha = dimmed ? 0.45 : 1
            accessibilityLabel = snippet.map { "\(session.title). \($0)" } ?? session.title
            accessibilityValue = session.activity == .running ? "Running" : "Idle"
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
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search chats", text: $query)
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
