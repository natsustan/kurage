import AppKit
import SwiftUI
import KurageCore

struct MacSidebar: View {
    let model: AppModel
    @Bindable var window: MacWindowState
    @State private var recoveryError: String?
    @State private var groups: [ProjectGroup] = []
    @State private var pinnedSessions: [SessionSummary] = []
    @State private var projectTemplates: [SessionSummary] = []
    @State private var sessionAction: MacSessionActionRequest?
    @Environment(\.colorScheme) private var colorScheme

    private struct ProjectGroup: Identifiable {
        let id: String
        let name: String
        let sessions: [SessionSummary]

        var unassigned: Bool { id == "unassigned" }
    }

    private var canStartSession: Bool {
        model.supportsSessionCreation && !projectTemplates.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if let template = projectTemplates.first {
                    window.newSession = NewSessionDestination(template: template, isTab: false)
                }
            } label: {
                // 16pt symbol slot and 6pt gap, matching the project header.
                HStack(spacing: MacSidebarMetrics.iconSpacing) {
                    MacSidebarSymbol(systemName: "square.and.pencil")
                    Text("New session")
                        .lineLimit(1)
                }
            }
            .buttonStyle(MacSidebarButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
            .focusEffectDisabled()
            .disabled(!canStartSession)
            .opacity(canStartSession ? 1 : 0.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, MacSidebarMetrics.controlInset)
            .accessibilityIdentifier("new-session")
            Button {
                window.showsSessionSearch.toggle()
            } label: {
                HStack(spacing: MacSidebarMetrics.iconSpacing) {
                    MacSidebarSymbol(systemName: "magnifyingglass")
                        .accessibilityHidden(true)
                    Text("Search sessions")
                        .lineLimit(1)
                }
            }
            .buttonStyle(MacSidebarButtonStyle())
            .keyboardShortcut("f", modifiers: .command)
            .focusEffectDisabled()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, MacSidebarMetrics.controlInset)
            .accessibilityIdentifier("session-search")
            if !model.pendingSessionStarts.isEmpty {
                Menu("Pending sessions", systemImage: "arrow.clockwise.circle") {
                    ForEach(model.pendingSessionStarts) { pending in
                        Button(String(pending.displayText.prefix(50))) {
                            do {
                                try window.openPendingStart(pending, model: model)
                                recoveryError = nil
                            } catch { recoveryError = "Could not reopen the pending session." }
                        }
                        .accessibilityIdentifier("pending-session-\(pending.id)")
                    }
                }
                .accessibilityIdentifier("pending-sessions")
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            if let recoveryError { Text(recoveryError).font(.caption).foregroundStyle(.red).padding(12) }
            List(selection: $window.selectedRootID) {
                if !pinnedSessions.isEmpty {
                    MacPinnedHeader()
                        .selectionDisabled()
                    ForEach(pinnedSessions) { session in
                        sessionRow(session)
                    }
                }
                ForEach(groups) { group in
                    let collapsed = window.collapsedProjectIDs.contains(group.id)
                    let template = projectTemplates.first { $0.projectID == group.id }
                    // A section header flattens its buttons into one accessibility element,
                    // so the collapse target and the new-session button would share a hit target.
                    MacProjectHeader(
                        name: group.name,
                        projectID: group.id,
                        collapsed: collapsed,
                        canToggle: true,
                        canCreate: model.supportsSessionCreation && template != nil,
                        unassigned: group.unassigned,
                        onToggle: { toggleProject(group.id) },
                        onNewSession: {
                            if let template {
                                window.newSession = NewSessionDestination(template: template, isTab: false)
                            }
                        }
                    )
                    .selectionDisabled()
                    if !collapsed {
                        ForEach(group.sessions) { session in
                            sessionRow(session)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            // The source list paints the system sidebar material over the column fill.
            .scrollContentBackground(.hidden)
            .background {
                MacChrome.sidebar(colorScheme)
                MacSidebarScrollFill(color: MacChrome.sidebar(dark: colorScheme == .dark))
            }
            // Sidebar lists add their own leading margin. Zero it so folder icons
            // share the New Session icon's inset instead of sitting further right.
            .contentMargins(.leading, 0, for: .scrollContent)
            // Keep a scrolling title inside the list. The footer plate covers anything that still overlaps it.
            .clipped()
            .modifier(MacSessionActionPresenter(model: model, request: $sessionAction, onArchived: { id in
                if window.selectedRootID == id { window.selectedRootID = nil }
            }))
            if let note = model.statusNote {
                Text(note.text).font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
        .navigationTitle("Kurage")
        .onChange(of: model.sessions, initial: true) { _, _ in updateGroups() }
    }

    private func updateGroups() {
        let sessions = model.sessions
        projectTemplates = NewSessionDestination.projectTemplates(in: sessions)
        // Pinned roots move into the top group and leave their project, matching iOS.
        pinnedSessions = sessions.filter { $0.isPinned == true }
        var order: [String] = []
        var grouped: [String: [SessionSummary]] = [:]
        var names: [String: String] = [:]
        for session in sessions {
            let key = session.projectID ?? "unassigned"
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
                names[key] = session.projectName ?? "Sessions"
            }
            if session.isPinned != true {
                grouped[key, default: []].append(session)
            }
        }
        groups = order.compactMap { key in
            let values = grouped[key] ?? []
            // Keep a local project header when every session is pinned, so New session stays available.
            let canCreate = key != "unassigned"
                && model.supportsSessionCreation
                && projectTemplates.contains { $0.projectID == key }
            if values.isEmpty && !canCreate { return nil }
            return ProjectGroup(id: key, name: names[key] ?? "Sessions", sessions: values)
        }
    }

    private func sessionRow(_ session: SessionSummary) -> some View {
        let template = projectTemplates.first { $0.projectID == session.projectID }
        return MacSessionRow(session: session)
            .listRowInsets(EdgeInsets(
                top: 1,
                leading: MacSidebarMetrics.rowLeading + MacSidebarMetrics.titleInset,
                bottom: 1,
                trailing: MacSidebarMetrics.rowTrailing
            ))
            .tag(session.id)
            .accessibilityIdentifier("session-\(session.id)")
            .contextMenu {
                if model.supportsSessionMetadataEditing {
                    Button(
                        session.isPinned == true ? "Unpin" : "Pin",
                        systemImage: session.isPinned == true ? "pin.slash" : "pin"
                    ) {
                        sessionAction = MacSessionActionRequest(session: session, action: .pin)
                    }
                    Button("Rename session", systemImage: "pencil") {
                        sessionAction = MacSessionActionRequest(session: session, action: .rename)
                    }
                }
                Button("Copy Session URL", systemImage: "link") {
                    sessionAction = MacSessionActionRequest(session: session, action: .copyURL)
                }
                .disabled(model.sessionURL(sessionID: session.id) == nil)
                if let template, model.supportsSessionCreation {
                    Button("New session in project") {
                        window.newSession = NewSessionDestination(template: template, isTab: false)
                    }
                }
                if let url = model.sessionURL(sessionID: session.id) {
                    Link("Open in Lody", destination: url)
                }
                if model.supportsSessionArchiving {
                    Divider()
                    Button("Archive", systemImage: "archivebox", role: .destructive) {
                        sessionAction = MacSessionActionRequest(session: session, action: .archive)
                    }
                }
            }
    }

    private func toggleProject(_ id: String) {
        withAnimation(.snappy) {
            var collapsed = window.collapsedProjectIDs
            if collapsed.contains(id) {
                collapsed.remove(id)
            } else {
                collapsed.insert(id)
            }
            window.collapsedProjectIDs = collapsed
        }
    }
}

private enum MacSidebarMetrics {
    static let iconWidth: CGFloat = 16
    static let iconSpacing: CGFloat = 6
    /// Shared left edge of the New Session icon, the search icon, and folder glyphs.
    /// Matches the workspace menu's 20pt sidebar inset.
    static let controlInset: CGFloat = 20
    /// The sidebar list keeps a leading margin that `contentMargins` does not
    /// remove. This inset puts the folder icon on `controlInset`.
    static let rowLeading: CGFloat = 2.5
    static let rowTrailing: CGFloat = 10
    /// Session titles share the project name's left edge, past the folder icon.
    static var titleInset: CGFloat { iconWidth + iconSpacing }
}

private struct MacSidebarSymbol: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .frame(width: MacSidebarMetrics.iconWidth, height: MacSidebarMetrics.iconWidth)
    }
}

private struct MacSidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

private struct MacProjectHeader: View {
    let name: String
    let projectID: String
    let collapsed: Bool
    let canToggle: Bool
    let canCreate: Bool
    let unassigned: Bool
    let onToggle: () -> Void
    let onNewSession: () -> Void

    var body: some View {
        HStack(spacing: MacSidebarMetrics.iconSpacing) {
            Button(action: onToggle) {
                HStack(spacing: MacSidebarMetrics.iconSpacing) {
                    projectIcon
                        .accessibilityHidden(true)
                    Text(name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MacSidebarButtonStyle())
            .disabled(!canToggle)
            .focusEffectDisabled()
            .accessibilityIdentifier("project-header-\(projectID)")
            .accessibilityLabel(name)
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            .accessibilityHint("Collapses or expands this project's sessions")
            .accessibilityAddTraits(.isHeader)
            // The name button hugs its label. A flexible hit target would
            // cover the pencil, so a click in the row center opens a session.
            Spacer(minLength: 0)
                .contentShape(Rectangle())
                .onTapGesture { if canToggle { onToggle() } }
            if canCreate {
                Button(action: onNewSession) {
                    Image("pencil-square")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MacSidebarButtonStyle())
                .focusEffectDisabled()
                .help("New session in \(name)")
                .accessibilityLabel("New session in \(name)")
                .accessibilityIdentifier("new-session-\(projectID)")
            }
        }
        .foregroundStyle(.secondary)
        .textCase(nil)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .accessibilityElement(children: .contain)
        .listRowInsets(EdgeInsets(top: 4, leading: MacSidebarMetrics.rowLeading, bottom: 2, trailing: MacSidebarMetrics.rowTrailing))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder private var projectIcon: some View {
        if unassigned {
            Image(systemName: collapsed ? "bubble.left" : "bubble.left.fill")
                .font(.system(size: 14))
                .frame(width: MacSidebarMetrics.iconWidth, height: MacSidebarMetrics.iconWidth)
        } else {
            Image(collapsed ? "folder-closed" : "folder-open")
                .resizable()
                .scaledToFit()
                .frame(width: MacSidebarMetrics.iconWidth, height: MacSidebarMetrics.iconWidth)
        }
    }
}

private struct MacPinnedHeader: View {
    var body: some View {
        HStack(spacing: MacSidebarMetrics.iconSpacing) {
            Image(systemName: "pin")
                .font(.system(size: 13, weight: .medium))
                .frame(width: MacSidebarMetrics.iconWidth, height: MacSidebarMetrics.iconWidth)
                .accessibilityHidden(true)
            Text("Pinned")
                .font(.body.weight(.medium))
                .lineLimit(1)
                .accessibilityIdentifier("pinned-header")
                .accessibilityAddTraits(.isHeader)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .accessibilityElement(children: .contain)
        .listRowInsets(EdgeInsets(
            top: 4,
            leading: MacSidebarMetrics.rowLeading,
            bottom: 2,
            trailing: MacSidebarMetrics.rowTrailing
        ))
        .listRowSeparator(.hidden)
    }
}

/// Paints the sidebar list's scroll view. Its own background sits above the SwiftUI fill.
private struct MacSidebarScrollFill: NSViewRepresentable {
    var color: NSColor

    func makeNSView(context: Context) -> MacSidebarScrollFillView {
        let view = MacSidebarScrollFillView()
        view.color = color
        return view
    }

    func updateNSView(_ view: MacSidebarScrollFillView, context: Context) {
        view.color = color
    }
}

private final class MacSidebarScrollFillView: NSView {
    var color = NSColor.clear { didSet { apply() } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    override func layout() {
        super.layout()
        apply()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply()
    }

    private func apply() {
        guard let scroll = nearestScrollView() else { return }
        scroll.drawsBackground = true
        scroll.backgroundColor = color
        if let table = scroll.documentView as? NSTableView {
            table.backgroundColor = color
        }
        // A source list keeps a visual-effect backdrop in front of backgroundColor.
        for subview in scroll.subviews where subview is NSVisualEffectView {
            subview.isHidden = true
        }
    }

    private func nearestScrollView() -> NSScrollView? {
        var view: NSView? = superview
        while let current = view {
            if let scroll = current as? NSScrollView { return scroll }
            if let scroll = current.subviews.compactMap({ $0 as? NSScrollView }).first { return scroll }
            if current is NSSplitView { return nil }
            view = current.superview
        }
        return nil
    }
}

private struct MacSessionRow: View {
    let session: SessionSummary

    var body: some View {
        Text(session.title)
            .lineLimit(1)
            .fontWeight(session.isUnread ? .semibold : .regular)
            .accessibilityValue(session.isUnread ? "Unread" : "Read")
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}
