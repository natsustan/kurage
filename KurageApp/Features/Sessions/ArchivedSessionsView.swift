import SwiftUI

struct ArchivedSessionsView: View {
    let model: AppModel
    @State private var pendingDelete: ArchivedSessionSummary?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let archiveStatusNote = model.archiveStatusNote {
                    Label(
                        archiveStatusNote.text,
                        systemImage: archiveStatusNote.tone == .failure ? "exclamationmark.circle" : "info.circle"
                    )
                    .foregroundStyle(archiveStatusNote.tone == .failure ? Color.red : Color.secondary)
                    .padding(.bottom, 16)
                }

                if model.archivedSessions.isEmpty {
                    if model.isRefreshingArchivedSessions {
                        ProgressView("Loading archived sessions…")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ContentUnavailableView(
                            "No archived sessions",
                            systemImage: "archivebox",
                            description: Text("Sessions you archive show up here, newest first.")
                        )
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(model.archivedSessions) { session in
                        archivedRow(session)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Archived sessions")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshArchivedSessions() }
        .task(id: model.selectedWorkspaceID) { await model.refreshArchivedSessions() }
        .confirmationDialog(
            pendingDelete.map { "Delete \"\($0.title)\"?" } ?? "Delete this archived session?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { session in
            Button("Delete Session", role: .destructive) {
                Task { await model.deleteArchivedSession(session.id) }
            }
            .accessibilityIdentifier("confirm-delete-archived-session")
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently deletes the archived session.")
        }
        .accessibilityIdentifier("archived-sessions-screen")
    }

    private func archivedRow(_ session: ArchivedSessionSummary) -> some View {
        let isBusy = model.archiveBusySessionIDs.contains(session.id)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(session.lastActivityAt, format: .relative(presentation: .named))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !session.canRestore {
                    Text("Re-add this local project to restore its conversations.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await model.restoreArchivedSession(session.id) }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!session.canRestore || isBusy)
            .accessibilityIdentifier("restore-\(session.id)")

            Button(role: .destructive) {
                pendingDelete = session
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBusy)
            .accessibilityIdentifier("delete-\(session.id)")
        }
        .padding(.vertical, 14)
        .opacity(isBusy ? 0.45 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("archived-session-\(session.id)")
    }
}
