import SwiftUI

struct ArchivedSessionsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Archived sessions")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 56)

                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background {
                                Circle().strokeBorder(Color(.separator), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("close-archived-sessions")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)

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
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .refreshable { await model.refreshArchivedSessions() }
        }
        .background(Color(.systemBackground))
        .task(id: model.selectedWorkspaceID) { await model.refreshArchivedSessions() }
    }

    private func archivedRow(_ session: ArchivedSessionSummary) -> some View {
        let isBusy = model.archiveBusySessionIDs.contains(session.id)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body)
                    .lineLimit(2)
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
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!session.canRestore || isBusy)
            .accessibilityLabel("Restore")
            .accessibilityIdentifier("restore-\(session.id)")
        }
        .padding(.vertical, 14)
        .opacity(isBusy ? 0.45 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("archived-session-\(session.id)")
    }
}
