import SwiftUI

struct ConversationView: View {
    let sessionID: SessionSummary.ID
    let title: String
    let model: AppModel

    @State private var conversation: Conversation?
    @State private var draft = ""
    @State private var isSending = false
    @State private var banner: String?

    var body: some View {
        VStack(spacing: 0) {
            ConversationTranscript(turns: conversation?.turns ?? [])
            ConversationFooter(
                permission: conversation?.permission,
                draft: $draft,
                isSending: isSending,
                banner: banner,
                onSend: sendDraft,
                onDecision: respond
            )
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: sessionID) {
            await load()
        }
    }

    private func load() async {
        do {
            conversation = try await model.conversation(sessionID: sessionID)
            banner = nil
        } catch {
            banner = "Could not open this conversation."
        }
    }

    private func sendDraft() {
        let text = draft
        Task {
            isSending = true
            defer { isSending = false }
            do {
                try await model.send(text, sessionID: sessionID)
                draft = ""
                conversation = try await model.conversation(sessionID: sessionID)
                banner = nil
            } catch LodyClientError.emptyMessage {
                banner = nil
            } catch {
                banner = "Could not send."
            }
        }
    }

    private func respond(_ decision: PermissionDecision, requestID: PermissionPrompt.ID) {
        Task {
            do {
                try await model.respond(decision, requestID: requestID, sessionID: sessionID)
                conversation = try await model.conversation(sessionID: sessionID)
                banner = nil
            } catch {
                banner = "Could not save the permission."
            }
        }
    }
}

private struct ConversationTranscript: View {
    let turns: [ConversationTurn]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(turns) { turn in
                        TurnRow(author: turn.author, text: turn.text)
                            .id(turn.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .onChange(of: turns.last?.id) {
                guard let id = turns.last?.id else { return }
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }
}

private struct TurnRow: View {
    let author: TurnAuthor
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(author == .user ? "You" : "Agent")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ConversationFooter: View {
    let permission: PermissionPrompt?
    @Binding var draft: String
    let isSending: Bool
    let banner: String?
    let onSend: () -> Void
    let onDecision: (PermissionDecision, PermissionPrompt.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let banner {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let permission {
                PermissionCard(permission: permission, onDecision: onDecision)
            }
            FollowUpComposer(draft: $draft, isSending: isSending, onSend: onSend)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

private struct PermissionCard: View {
    let permission: PermissionPrompt
    let onDecision: (PermissionDecision, PermissionPrompt.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(permission.title)
                .font(.headline)
            Text(permission.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("Deny") {
                    onDecision(.deny, permission.id)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("permission-deny")

                Button("Allow") {
                    onDecision(.allow, permission.id)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("permission-allow")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct FollowUpComposer: View {
    @Binding var draft: String
    let isSending: Bool
    let onSend: () -> Void

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Send a follow-up", text: $draft)
                .textFieldStyle(.plain)
                .frame(minHeight: 36)
                .accessibilityIdentifier("follow-up-field")
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("send-follow-up")
        }
    }
}

#Preview("Permission") {
    ConversationPreview(sessionID: "session-tests", title: "fix flaky tests")
}

#Preview("Idle") {
    ConversationPreview(sessionID: "session-pr", title: "review the PR")
}

private struct ConversationPreview: View {
    let sessionID: SessionSummary.ID
    let title: String
    @State private var model = AppModel(client: FixtureLodyClient(startsSignedIn: true))

    var body: some View {
        NavigationStack {
            ConversationView(sessionID: sessionID, title: title, model: model)
        }
        .task { await model.adoptExistingAccount() }
    }
}
