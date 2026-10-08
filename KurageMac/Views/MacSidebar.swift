import SwiftUI
import KurageCore

struct MacSidebar: View {
    let model: AppModel
    @Bindable var window: MacWindowState
    @State private var recoveryError: String?
    @State private var groups: [ProjectGroup] = []
    @State private var visibleGroups: [ProjectGroup] = []
    @State private var projectTemplates: [SessionSummary] = []

    private struct ProjectGroup: Identifiable {
        let id: String
        let name: String
        let sessions: [SessionSummary]
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
            .padding(.horizontal, 16)
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
                    Section(group.name) {
                        ForEach(group.sessions) { session in
                            MacSessionRow(session: session)
                                .tag(session.id)
                                .accessibilityIdentifier("session-\(session.id)")
                                .contextMenu {
                                    if let template = projectTemplates.first(where: { $0.projectID == session.projectID }),
                                       model.supportsSessionCreation {
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
