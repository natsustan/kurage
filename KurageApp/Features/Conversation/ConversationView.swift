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
    @State private var isCancelling = false
    @State private var scrollRequestID = 0
    @State private var isLoading = true
    @State private var banner: String?
    @State private var connectionStatus: String?
    @State private var previousPendingText: String?
    @State private var previousPendingWorkspaceID: String?
    @State private var runConfigState = ConversationRunConfigState()
    @State private var previewImage: ConversationImage?

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
            loadImage: { image, variant in
                try await model.loadSessionImage(image, conversationSessionID: sessionID, variant: variant)
            },
            onPreviewImage: { previewImage = $0 },
            onRefresh: { refreshID += 1 }
        ) {
            ConversationFooter(
                permission: displayedConversation?.permission,
                draft: $draft,
                isSending: isSending,
                isCancelling: isCancelling,
                isSessionRunning: model.sessions.first(where: { $0.id == sessionID })?.activity == .running,
                banner: banner,
                supportsTextSending: model.supportsTextSending,
                supportsSessionCancellation: model.supportsSessionCancellation,
                supportsPermissionResponses: model.supportsPermissionResponses,
                runConfig: runConfigState.displayed,
                onSend: sendDraft,
                onCancel: cancelSession,
                onChooseRunConfig: chooseRunConfig,
                canRetryPrevious: previousPendingText != nil &&
                    previousPendingWorkspaceID == model.selectedWorkspaceID,
                onRetryPrevious: retryPreviousSend,
                onDecision: respond
            )
        }
        .id(ConversationIdentity(workspaceID: model.selectedWorkspaceID, sessionID: sessionID))
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $previewImage) { image in
            ConversationImagePreview(image: image) { image, variant in
                try await model.loadSessionImage(image, conversationSessionID: sessionID, variant: variant)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                ConversationNavigationTitle(title: title, connectionStatus: connectionStatus)
            }
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
                    runConfigState.receive(update.runConfig)
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
                connectionStatus = "Reconnecting…"
                do { try await Task.sleep(for: .seconds(retryDelay)) }
                catch { return }
                retryDelay = min(retryDelay * 2, 30)
            }
        }
    }

    private func sendDraft() {
        guard !isSending, !isCancelling,
              model.sessions.first(where: { $0.id == sessionID })?.activity != .running else { return }
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let choice = runConfigState.choice
        draft = ""
        scrollRequestID += 1
        banner = nil
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let sentChoice = try await model.send(text, runConfig: choice, sessionID: sessionID)
                previousPendingText = nil
                previousPendingWorkspaceID = nil
                runConfigState.didSend(sentChoice)
                if let latest = try? await model.conversation(sessionID: sessionID) {
                    conversation = latest
                }
            } catch LodyClientError.deliveryUnconfirmed {
                draft = text
                banner = "Send could not be confirmed. Retry to resume the same message."
            } catch LodyClientError.previousSendPending(let previousText) {
                draft = text
                previousPendingText = previousText
                previousPendingWorkspaceID = model.selectedWorkspaceID
                banner = "An earlier send is unconfirmed. Retry it before sending different text."
            } catch LodyClientError.sendSuperseded {
                draft = text
                previousPendingText = nil
                previousPendingWorkspaceID = nil
                banner = "A newer message took precedence. Send again to create a new message."
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

    private func chooseRunConfig(_ value: String) {
        runConfigState.choose(value)
    }

    private func cancelSession() {
        guard !isSending, !isCancelling, model.supportsSessionCancellation,
              model.sessions.first(where: { $0.id == sessionID })?.activity == .running else { return }
        isCancelling = true
        banner = nil
        Task {
            defer { isCancelling = false }
            do {
                try await model.cancelSession(sessionID: sessionID)
            } catch is CancellationError {
                return
            } catch {
                banner = "Could not stop the current reply. Try again."
            }
        }
    }

    private func retryPreviousSend() {
        guard !isSending, let text = previousPendingText,
              previousPendingWorkspaceID == model.selectedWorkspaceID else { return }
        isSending = true
        banner = nil
        Task {
            defer { isSending = false }
            do {
                try await model.send(text, sessionID: sessionID)
                previousPendingText = nil
                previousPendingWorkspaceID = nil
                banner = "Earlier message confirmed. Review your draft before sending."
                if let latest = try? await model.conversation(sessionID: sessionID) {
                    conversation = latest
                }
            } catch LodyClientError.sendSuperseded {
                previousPendingText = nil
                previousPendingWorkspaceID = nil
                banner = "Earlier message was replaced. You can send your draft as a new message."
            } catch is CancellationError {
                return
            } catch {
                banner = "Earlier send is still unconfirmed. Retry it before sending different text."
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

private struct ConversationNavigationTitle: View {
    let title: String
    let connectionStatus: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Text(connectionStatus ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .opacity(connectionStatus == nil ? 0 : 1)
                .accessibilityHidden(connectionStatus == nil)
                .accessibilityIdentifier("conversation-connection-status")
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

struct TurnRow: View {
    let turn: ConversationTurn
    let loadImage: @MainActor (ConversationImage, SessionImageVariant) async throws -> Data
    let onPreviewImage: (ConversationImage) -> Void

    var body: some View {
        let alignment: HorizontalAlignment = turn.author == .user ? .trailing : .leading
        VStack(alignment: alignment, spacing: 8) {
            ForEach(conversationBlocks(author: turn.author, content: turn.content)) { block in
                switch block {
                case .text(_, let text):
                    messageText(text)
                case .images(_, let images):
                    ConversationImageGroup(
                        images: images,
                        alignment: alignment,
                        loadImage: loadImage,
                        onPreview: onPreviewImage
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: turn.author == .user ? .trailing : .leading)
    }

    @ViewBuilder
    private func messageText(_ text: String) -> some View {
        if turn.author == .user {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 52)
                Text(text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityHint("Your message")
            }
        } else {
            MarkdownView(text)
                .tint(.primary)
                .tint(Color(uiColor: .secondaryLabel), for: .inlineCodeBlock)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ConversationFooter: View {
    let permission: PermissionPrompt?
    @Binding var draft: String
    let isSending: Bool
    let isCancelling: Bool
    let isSessionRunning: Bool
    let banner: String?
    let supportsTextSending: Bool
    let supportsSessionCancellation: Bool
    let supportsPermissionResponses: Bool
    let runConfig: SessionRunConfig?
    let onSend: () -> Void
    let onCancel: () -> Void
    let onChooseRunConfig: (String) -> Void
    let canRetryPrevious: Bool
    let onRetryPrevious: () -> Void
    let onDecision: (PermissionDecision, PermissionPrompt.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            if canRetryPrevious {
                Button("Retry earlier message", action: onRetryPrevious)
                    .font(.footnote)
                    .disabled(isSending)
            }
            if let permission, supportsPermissionResponses {
                PermissionCard(permission: permission, onDecision: onDecision)
            }
            if supportsTextSending || supportsSessionCancellation && isSessionRunning {
                FollowUpComposer(draft: $draft, isSending: isSending, isCancelling: isCancelling,
                                 isSessionRunning: isSessionRunning,
                                 supportsSessionCancellation: supportsSessionCancellation,
                                 runConfig: runConfig,
                                 onSend: onSend, onCancel: onCancel,
                                 onChooseRunConfig: onChooseRunConfig)
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
    let isCancelling: Bool
    let isSessionRunning: Bool
    let supportsSessionCancellation: Bool
    let runConfig: SessionRunConfig?
    let onSend: () -> Void
    let onCancel: () -> Void
    let onChooseRunConfig: (String) -> Void
    @FocusState private var isFocused: Bool

    private var editableDraft: Binding<String> {
        Binding(
            get: { draft },
            set: { if !isSending { draft = $0 } }
        )
    }

    private var canSend: Bool {
        !isSending && !isCancelling && !isSessionRunning &&
            !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputRow
            if isFocused, let runConfig, runConfig.summary != nil {
                RunConfigRow(runConfig: runConfig, onChoose: onChooseRunConfig)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.snappy(duration: 0.2), value: isFocused)
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 60)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("follow-up-composer")
    }

    private var inputRow: some View {
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
                if isSessionRunning { onCancel() } else { onSend() }
            } label: {
                Image(systemName: isSessionRunning ? "stop.fill" : "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(canSend || isSessionRunning ? Color.white : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(canSend || isSessionRunning ? Color.accentColor : Color.primary.opacity(0.08), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .disabled(isSessionRunning ? !supportsSessionCancellation || isSending || isCancelling : !canSend)
            .buttonStyle(.plain)
            .accessibilityLabel(isSessionRunning ? "Stop reply" : "Send")
            .accessibilityIdentifier(isSessionRunning ? "pause-session" : "send-follow-up")
        }
    }
}

private extension SessionRunConfig {
    var summary: String? {
        let parts = [model?.label, reasoning?.label].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var accessibilitySummary: String {
        [model.map { "Model \($0.label)" }, reasoning.map { "reasoning \($0.label)" }]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// Shows the next turn's model and reasoning. Only the value the agent can
/// change without switching models (reasoning when available) is editable.
private struct RunConfigRow: View {
    let runConfig: SessionRunConfig
    let onChoose: (String) -> Void

    var body: some View {
        Group {
            if let editable = runConfig.editable {
                Menu {
                    let title = editable.kind == .reasoning ? "Reasoning" : "Model"
                    Section(title) {
                        Picker(title, selection: selection(for: editable)) {
                            ForEach(editable.options) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                } label: {
                    summary(icon: editable.kind == .reasoning ? "gauge.with.dots.needle.50percent" : "cpu",
                            showsChevron: true)
                }
                .menuOrder(.fixed)
                .tint(.secondary)
                .accessibilityLabel(runConfig.accessibilitySummary)
                .accessibilityHint("Applies to your next message")
                .accessibilityIdentifier("run-config-menu")
            } else {
                summary(icon: "cpu", showsChevron: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(runConfig.accessibilitySummary)
                    .accessibilityIdentifier("run-config-summary")
            }
        }
        .frame(minHeight: 36)
    }

    private func selection(for editable: SessionRunConfig.Editable) -> Binding<String> {
        Binding(
            get: { (editable.kind == .reasoning ? runConfig.reasoning : runConfig.model)?.value ?? "" },
            set: onChoose
        )
    }

    private func summary(icon: String, showsChevron: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(runConfig.summary ?? "")
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .contentShape(.rect)
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

/// Separates the synchronized configuration from a choice for the next new turn.
struct ConversationRunConfigState {
    private(set) var config: SessionRunConfig?
    private(set) var choice: RunConfigChoice?

    var displayed: SessionRunConfig? { config?.applying(choice) }

    mutating func receive(_ config: SessionRunConfig?) {
        self.config = config
        // Drop a choice the agent no longer offers in the same place.
        if let choice, config?.choosing(choice.value) != choice {
            self.choice = nil
        }
    }

    mutating func choose(_ value: String) {
        guard let selected = config?.choosing(value) else { return }
        let current = config?.editable?.kind == .reasoning ? config?.reasoning : config?.model
        choice = current?.value == value ? nil : selected
    }

    mutating func didSend(_ sentChoice: RunConfigChoice?) {
        config = config?.applying(sentChoice)
        // A retry can send an older choice. Keep any unused selection for the next turn.
        if choice == sentChoice { choice = nil }
    }
}
