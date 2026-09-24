import SwiftUI

struct SessionListView: View {
    let model: AppModel
    @AppStorage("sessionListMode") private var listMode: SessionListMode = .byProject

    var body: some View {
        NavigationStack {
            SessionList(
                sessions: model.sessions,
                mode: listMode,
                supportsConversations: model.supportsConversations,
                isRefreshing: model.isRefreshingSessions && !model.hasCachedSessions,
                statusNote: model.statusNote
            )
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
        .preferredColorScheme(.light)
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
    let isRefreshing: Bool
    let statusNote: StatusNote?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let statusNote {
                    Label(statusNote.text, systemImage: statusNote.tone == .failure ? "exclamationmark.circle" : "info.circle")
                        .foregroundStyle(statusNote.tone == .failure ? Color.red : Color.secondary)
                        .padding(.bottom, 16)
                }

                if !supportsConversations {
                    Text("Only the session list is available. Conversations are not supported yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 16)
                }

                if sessions.isEmpty {
                    if isRefreshing {
                        ProgressView("Loading sessions…")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ContentUnavailableView(
                            "No sessions",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text(statusNote?.text ?? "No sessions in this workspace.")
                        )
                        .frame(maxWidth: .infinity)
                    }
                } else if mode == .byProject {
                    Text("Projects")
                        .font(.title3.weight(.semibold))
                        .padding(.bottom, 18)
                    ForEach(SessionProjectGroup.make(from: sessions)) { group in
                        projectGroup(group)
                    }
                } else {
                    Text("Recent")
                        .font(.title3.weight(.semibold))
                        .padding(.bottom, 18)
                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color.white)
    }

    private func projectGroup(_ group: SessionProjectGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: group.id == "unassigned" ? "bubble.left" : "folder")
                    .frame(width: 24, alignment: .leading)
                Text(group.name)
            }
            .font(.headline)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ForEach(group.sessions) { session in
                sessionRow(session)
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionSummary) -> some View {
        if supportsConversations {
            NavigationLink(value: session.id) {
                sessionLabel(session)
            }
            .buttonStyle(.plain)
        } else {
            sessionLabel(session)
        }
    }

    private func sessionLabel(_ session: SessionSummary) -> some View {
        HStack(spacing: 8) {
            if session.activity == .running {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: 20, height: 20)
            }
            Text(session.title)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.title)
        .accessibilityValue(session.activity == .running ? Text("Running") : Text("Idle"))
        .accessibilityIdentifier("session-\(session.id)")
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
