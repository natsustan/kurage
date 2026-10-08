import SwiftUI
import KurageCore

struct MacSidebar: View {
    let model: AppModel
    @Bindable var window: MacWindowState
    @State private var recoveryError: String?
    @State private var groups: [ProjectGroup] = []
    @State private var visibleGroups: [ProjectGroup] = []
    @State private var projectTemplates: [SessionSummary] = []
    @State private var collapsedProjectIDs: Set<String> = []

    private struct ProjectGroup: Identifiable {
        let id: String
        let name: String
        let sessions: [SessionSummary]

        var unassigned: Bool { id == "unassigned" }
    }

    private var trimmedSearch: String {
        window.search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if let template = projectTemplates.first {
                    window.newSession = NewSessionDestination(template: template, isTab: false)
                }
            } label: {
                Label("New Session", systemImage: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .focusEffectDisabled()
            .disabled(!model.supportsSessionCreation || projectTemplates.isEmpty)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, MacSidebarMetrics.controlInset)
            .accessibilityIdentifier("new-session")
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search sessions", text: $window.search)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("session-search")
                if !window.search.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { window.search = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("clear-session-search")
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
                ForEach(visibleGroups) { group in
                    let collapsed = trimmedSearch.isEmpty && collapsedProjectIDs.contains(group.id)
                    let template = projectTemplates.first { $0.projectID == group.id }
                    // A section header flattens its buttons into one accessibility element,
                    // so the collapse target and the new-session button would share a hit target.
                    MacProjectHeader(
                        name: group.name,
                        projectID: group.id,
                        collapsed: collapsed,
                        canToggle: trimmedSearch.isEmpty,
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
                            MacSessionRow(session: session)
                                .listRowInsets(EdgeInsets(
                                    top: 1,
                                    leading: MacSidebarMetrics.rowLeading + MacSidebarMetrics.titleInset,
                                    bottom: 1,
                                    trailing: MacSidebarMetrics.rowTrailing
                                ))
                                .tag(session.id)
                                .accessibilityIdentifier("session-\(session.id)")
                                .contextMenu {
                                    if let template, model.supportsSessionCreation {
                                        Button("New session in project") {
                                            window.newSession = NewSessionDestination(template: template, isTab: false)
                                        }
                                    }
                                    if let url = model.sessionURL(sessionID: session.id) { Link("Open in Lody", destination: url) }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            // Sidebar lists add their own leading margin. Zero it so folder icons
            // share the New Session icon's inset instead of sitting further right.
            .contentMargins(.leading, 0, for: .scrollContent)
            if let note = model.statusNote {
                Text(note.text).font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
        .navigationTitle("Kurage")
        .onChange(of: model.sessions, initial: true) { _, _ in updateGroups() }
        .onChange(of: window.search) { _, _ in filterGroups() }
    }

    private func updateGroups() {
        projectTemplates = NewSessionDestination.projectTemplates(in: model.sessions)
        var order: [String] = []
        var grouped: [String: [SessionSummary]] = [:]
        for session in model.sessions {
            let key = session.projectID ?? "unassigned"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(session)
        }
        groups = order.map { key in
            let values = grouped[key] ?? []
            return ProjectGroup(id: key, name: values.first?.projectName ?? "Sessions", sessions: values)
        }
        filterGroups()
    }

    private func toggleProject(_ id: String) {
        guard trimmedSearch.isEmpty else { return }
        withAnimation(.snappy) {
            if collapsedProjectIDs.contains(id) {
                collapsedProjectIDs.remove(id)
            } else {
                collapsedProjectIDs.insert(id)
            }
        }
    }

    private func filterGroups() {
        let query = window.search.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleGroups = groups.compactMap { group in
            let sessions = group.sessions.filter {
                query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                    || $0.preview.localizedCaseInsensitiveContains(query)
                    || ($0.projectName?.localizedCaseInsensitiveContains(query) == true)
            }
            return sessions.isEmpty ? nil : ProjectGroup(id: group.id, name: group.name, sessions: sessions)
        }
    }
}

private enum MacSidebarMetrics {
    static let iconWidth: CGFloat = 16
    static let iconSpacing: CGFloat = 6
    /// New Session's inset from the sidebar edge.
    static let controlInset: CGFloat = 16
    /// The sidebar list keeps a leading margin that `contentMargins` does not
    /// remove. This inset puts the folder icon on the New Session icon.
    static let rowLeading: CGFloat = 2.5
    static let rowTrailing: CGFloat = 10
    /// Session titles share the project name's left edge, past the folder icon.
    static var titleInset: CGFloat { iconWidth + iconSpacing }
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
        .font(.subheadline.weight(.semibold))
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

private struct MacSessionRow: View {
    let session: SessionSummary

    var body: some View {
        Text(session.title)
            .lineLimit(1)
            .fontWeight(session.isUnread ? .semibold : .regular)
            .accessibilityValue(session.isUnread ? "Unread" : "Read")
            .padding(.vertical, 3)
    }
}
