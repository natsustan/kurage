import SwiftUI
import MarkdownView

struct ConversationView: View {
    let sessionID: SessionSummary.ID
    let title: String
    let model: AppModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var observedWorkspaceID: String?
    @State private var observedSessionID: String?
    @State private var refreshID = 0
    @State private var conversation: Conversation?
    @State private var draft = ""
    @State private var isSending = false
    @State private var scrollRequestID = 0
    @State private var isLoading = true
    @State private var banner: String?
    @State private var connectionStatus: String?

    private var displayedConversation: Conversation? {
        if observedWorkspaceID == model.selectedWorkspaceID, observedSessionID == sessionID {
            return conversation ?? model.cachedConversation(sessionID: sessionID)
        }
        return model.cachedConversation(sessionID: sessionID)
    }

    var body: some View {
        ConversationLayout(
            turns: displayedConversation?.turns ?? [],
            isLoading: isLoading,
            scrollRequestID: scrollRequestID,
            onRefresh: { refreshID += 1 }
        ) {
            ConversationFooter(
                permission: displayedConversation?.permission,
                draft: $draft,
                isSending: isSending,
                isSessionBusy: !model.supportsTextSendingWhileRunning &&
                    model.sessions.first(where: { $0.id == sessionID })?.activity == .running,
                banner: banner,
                connectionStatus: connectionStatus,
                supportsTextSending: model.supportsTextSending,
                supportsPermissionResponses: model.supportsPermissionResponses,
                onSend: sendDraft,
                onDecision: respond
            )
        }
        .id(ConversationIdentity(workspaceID: model.selectedWorkspaceID, sessionID: sessionID))
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.sessions.first(where: { $0.id == sessionID })?.activity == .running {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Agent running")
                }
            }
        }
        .task(id: ObservationKey(workspaceID: model.selectedWorkspaceID, sessionID: sessionID,
                                 active: scenePhase == .active, refreshID: refreshID)) {
            guard scenePhase == .active else { return }
            await observe()
        }
    }

    private struct ConversationIdentity: Hashable {
        let workspaceID: String?
        let sessionID: String
    }

    private struct ObservationKey: Equatable {
        let workspaceID: String?
        let sessionID: String
        let active: Bool
        let refreshID: Int
    }

    private func observe() async {
        observedWorkspaceID = model.selectedWorkspaceID
        observedSessionID = sessionID
        conversation = model.cachedConversation(sessionID: sessionID)
        isLoading = conversation == nil
        connectionStatus = "Connecting…"
        var retryDelay = 1
        while !Task.isCancelled {
            do {
                try await model.observeConversation(sessionID: sessionID) { update in
                    conversation = update.conversation
                    isLoading = false
                    connectionStatus = update.syncState == .live ? nil : "Reconnecting…"
                    if update.syncState == .live { retryDelay = 1 }
                }
                return
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                connectionStatus = "Connection interrupted. Reconnecting…"
                do { try await Task.sleep(for: .seconds(retryDelay)) }
                catch { return }
                retryDelay = min(retryDelay * 2, 30)
            }
        }
    }

    private func sendDraft() {
        guard !isSending else { return }
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        scrollRequestID += 1
        banner = nil
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await model.send(text, sessionID: sessionID)
                if let latest = try? await model.conversation(sessionID: sessionID) {
                    conversation = latest
                }
            } catch LodyClientError.deliveryUnconfirmed {
                draft = text
                banner = "Send could not be confirmed. Retry to resume the same message."
            } catch LodyClientError.sessionBusy {
                draft = text
                banner = "Wait for the current reply before sending."
            } catch is CancellationError {
                return
            } catch {
                draft = text
                banner = "Could not confirm send. Retry to resume the same message."
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

struct ConversationEmptyState: View {
    let isLoading: Bool

    var body: some View {
        if isLoading {
            ConversationLoadingPlaceholder()
        } else {
            ContentUnavailableView(
                "No messages yet",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Pull down to refresh this conversation.")
            )
        }
    }
}

private struct ConversationLoadingPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Spacer(minLength: 60)
                RoundedRectangle(cornerRadius: 20)
                    .frame(width: 210, height: 56)
            }
            VStack(alignment: .leading, spacing: 12) {
                Capsule().frame(width: 260, height: 15)
                Capsule().frame(maxWidth: .infinity).frame(height: 15)
                Capsule().frame(width: 175, height: 15)
            }
        }
        .foregroundStyle(Color.primary.opacity(0.06))
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading conversation")
    }
}

struct TurnRow: View, Equatable {
    let author: TurnAuthor
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if author == .user {
                Spacer(minLength: 52)
                Text(text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityHint("Your message")
            } else {
                MarkdownView(text)
                    .tint(.primary)
                    .tint(Color(uiColor: .secondaryLabel), for: .inlineCodeBlock)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: author == .user ? .trailing : .leading)
    }
}

private struct ConversationFooter: View {
    let permission: PermissionPrompt?
    @Binding var draft: String
    let isSending: Bool
    let isSessionBusy: Bool
    let banner: String?
    let connectionStatus: String?
    let supportsTextSending: Bool
    let supportsPermissionResponses: Bool
    let onSend: () -> Void
    let onDecision: (PermissionDecision, PermissionPrompt.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let connectionStatus {
                Text(connectionStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if isSending {
                Text("Sending…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let banner {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let permission, supportsPermissionResponses {
                PermissionCard(permission: permission, onDecision: onDecision)
            }
            if supportsTextSending {
                FollowUpComposer(draft: $draft, isSending: isSending,
                                 isSessionBusy: isSessionBusy, onSend: onSend)
            } else {
                Label("Read-only conversation", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

private struct PermissionCard: View {
    let permission: PermissionPrompt
    let onDecision: (PermissionDecision, PermissionPrompt.ID) -> Void
    @State private var showsDecision = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(permission.title)
                .font(.headline)
            Text(permission.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Review request", systemImage: "hand.raised") {
                showsDecision = true
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("permission-review")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .confirmationDialog(permission.title, isPresented: $showsDecision, titleVisibility: .visible) {
            Button("Allow") { onDecision(.allow, permission.id) }
                .accessibilityIdentifier("permission-allow")
            Button("Deny", role: .destructive) { onDecision(.deny, permission.id) }
                .accessibilityIdentifier("permission-deny")
        } message: {
            Text(permission.detail)
        }
    }
}

private struct FollowUpComposer: View {
    @Binding var draft: String
    let isSending: Bool
    let isSessionBusy: Bool
    let onSend: () -> Void
    @FocusState private var isFocused: Bool

    private var editableDraft: Binding<String> {
        Binding(
            get: { draft },
            set: { if !isSending { draft = $0 } }
        )
    }

    private var canSend: Bool {
        !isSending && !isSessionBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Send a follow-up", text: editableDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .fixedSize(horizontal: false, vertical: true)
                .submitLabel(.send)
                .focused($isFocused)
                .padding(.vertical, 9)
                .accessibilityIdentifier("follow-up-field")
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(canSend ? Color.white : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Color.accentColor : Color.primary.opacity(0.08), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("send-follow-up")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 60)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("follow-up-composer")
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
