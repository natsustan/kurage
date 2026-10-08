import SwiftUI
import KurageCore

struct MacSidebar: View {
    let model: AppModel
    @Bindable var window: MacWindowState
    @State private var groups: [ProjectGroup] = []

    private struct ProjectGroup: Identifiable {
        let id: String
        let name: String
        let sessions: [SessionSummary]
    }

    var body: some View {
        VStack(spacing: 0) {
            Menu {
                ForEach(model.workspaces) { workspace in
                    Button(workspace.name) { Task { await model.selectWorkspace(workspace.id) } }
                }
            } label: {
                Label(model.workspaceLabel, systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .accessibilityIdentifier("workspace-menu")
            List(selection: $window.selectedRootID) {
                ForEach(groups) { group in
                    Section(group.name) {
                        ForEach(group.sessions) { session in
                            MacSessionRow(session: session)
                                .tag(session.id)
                                .accessibilityIdentifier("session-\(session.id)")
                                .contextMenu {
                                    if session.projectID != nil, model.supportsSessionCreation {
                                        Button("New session in project") {
                                            let template = model.newSessionTemplate(projectID: session.projectID!) ?? session
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
            .searchable(text: $window.search, prompt: "Search sessions")
            if let note = model.statusNote {
                Text(note.text).font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
        .navigationTitle("Kurage")
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(groups) { group in
                        if let first = group.sessions.first, let projectID = first.projectID {
                            Button(group.name) {
                                window.newSession = NewSessionDestination(
                                    template: model.newSessionTemplate(projectID: projectID) ?? first, isTab: false)
                            }
                        }
                    }
                } label: { Label("New session", systemImage: "square.and.pencil") }
                .disabled(!model.supportsSessionCreation)
                .accessibilityIdentifier("new-session")
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refreshContent() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        .onChange(of: model.sessions, initial: true) { _, _ in updateGroups() }
        .onChange(of: window.search) { _, _ in updateGroups() }
    }

    private func updateGroups() {
        let query = window.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessions = model.sessions.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.preview.localizedCaseInsensitiveContains(query)
                || ($0.projectName?.localizedCaseInsensitiveContains(query) == true)
        }
        var order: [String] = []
        var grouped: [String: [SessionSummary]] = [:]
        for session in sessions {
            let key = session.projectID ?? "unassigned"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(session)
        }
        groups = order.map { key in
            let values = grouped[key] ?? []
            return ProjectGroup(id: key, name: values.first?.projectName ?? "Sessions", sessions: values)
        }
    }
}

private struct MacSessionRow: View {
    let session: SessionSummary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.isRunningInList ? "circle.dotted" : "bubble.left")
                .foregroundStyle(session.isUnread ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title).lineLimit(1).fontWeight(session.isUnread ? .semibold : .regular)
                Text(session.agentName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
