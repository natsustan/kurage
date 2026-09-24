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
        ConversationTranscript(turns: displayedConversation?.turns ?? [], isLoading: isLoading)
            .refreshable { refreshID += 1 }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ConversationFooter(
                    permission: displayedConversation?.permission,
                    draft: $draft,
                    isSending: isSending,
                    banner: banner,
                    connectionStatus: connectionStatus,
                    supportsActions: model.supportsConversationActions,
                    onSend: sendDraft,
                    onDecision: respond
                )
            }
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
    let isLoading: Bool
    @State private var followsOutput = true
    @State private var isUserScrolling = false
    @State private var isNearBottom = true

    private enum Anchor: Hashable { case bottom }

    var body: some View {
        Group {
            if turns.isEmpty {
                if isLoading {
                    ConversationLoadingPlaceholder()
                } else {
                    ContentUnavailableView(
                        "No messages yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Pull down to refresh this conversation.")
                    )
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            ForEach(turns) { turn in
                                TurnRow(author: turn.author, text: turn.text)
                                    .equatable()
                                    .id(turn.id)
                            }
                            Color.clear.frame(height: 1).id(Anchor.bottom)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .scrollDismissesKeyboard(.interactively)
                    .task {
                        guard let latestID = turns.last?.id else { return }
                        await Task.yield()
                        proxy.scrollTo(latestID, anchor: .bottom)
                    }
                    .onScrollPhaseChange { _, phase in
                        let wasUserScrolling = isUserScrolling
                        isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                        if wasUserScrolling || isUserScrolling { followsOutput = isNearBottom }
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.containerSize.height >=
                            geometry.contentSize.height + geometry.contentInsets.bottom - 60
                    } action: { _, nearBottom in
                        isNearBottom = nearBottom
                        if isUserScrolling { followsOutput = nearBottom }
                    }
                    .onChange(of: turns.last) { _, _ in
                        guard followsOutput, !isUserScrolling else { return }
                        proxy.scrollTo(Anchor.bottom, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
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

private struct TurnRow: View, Equatable {
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
    let banner: String?
    let connectionStatus: String?
    let supportsActions: Bool
    let onSend: () -> Void
    let onDecision: (PermissionDecision, PermissionPrompt.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let connectionStatus {
                Text(connectionStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let banner {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let permission, supportsActions {
                PermissionCard(permission: permission, onDecision: onDecision)
            }
            if supportsActions {
                FollowUpComposer(draft: $draft, isSending: isSending, onSend: onSend)
            } else {
                Label("Read-only conversation", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
    let onSend: () -> Void
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Send a follow-up", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .submitLabel(.send)
                .focused($isFocused)
                .accessibilityIdentifier("follow-up-field")
            Button {
                isFocused = false
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(!canSend)
            .buttonStyle(.glassProminent)
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
