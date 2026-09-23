import SwiftUI

struct SessionListView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            SessionList(sessions: model.sessions, statusNote: model.statusNote)
                .navigationTitle("Kurage")
                .navigationSubtitle(model.workspaceLabel)
                .navigationDestination(for: SessionSummary.ID.self) { sessionID in
                    ConversationView(
                        sessionID: sessionID,
                        title: model.sessions.first { $0.id == sessionID }?.title ?? "Session",
                        model: model
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign out", action: model.signOut)
                            .accessibilityIdentifier("sign-out-button")
                    }
                }
        }
    }
}

private struct SessionList: View {
    let sessions: [SessionSummary]
    let statusNote: StatusNote?

    var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No sessions",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(statusNote?.text ?? "Nothing is running.")
                )
            } else {
                ForEach(sessions) { session in
                    NavigationLink(value: session.id) {
                        SessionRow(
                            title: session.title,
                            agentName: session.agentName,
                            activity: session.activity,
                            preview: session.preview
                        )
                    }
                    .accessibilityIdentifier("session-\(session.id)")
                }
            }
        }
    }
}

private struct SessionRow: View {
    let title: String
    let agentName: String
    let activity: SessionActivity
    let preview: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            HStack(spacing: 6) {
                SessionActivityMark(activity: activity)
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        switch activity {
        case .running:
            "\(agentName) · Running"
        case .idle:
            "\(agentName) · Idle"
        }
    }
}

private struct SessionActivityMark: View {
    let activity: SessionActivity

    var body: some View {
        Circle()
            .fill(activity == .running ? Color.green : Color.secondary)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
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
