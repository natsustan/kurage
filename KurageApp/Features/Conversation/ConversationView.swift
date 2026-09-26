import SwiftUI
import MarkdownView

struct ConversationView: View {
    let sessionID: SessionSummary.ID
    let title: String
    let model: AppModel

    var body: some View {
        ConversationContent(sessionID: sessionID, title: title, model: model,
                            workspaceGeneration: model.workspaceGeneration)
            .id(ConversationScope(sessionID: sessionID, workspaceGeneration: model.workspaceGeneration))
    }
}

private struct ConversationScope: Hashable {
    let sessionID: String
    let workspaceGeneration: Int
}

// Scope the owner of all transient state, not just its layout subtree.
private struct ConversationContent: View {
    let sessionID: SessionSummary.ID
    let title: String
    let model: AppModel
    let workspaceGeneration: Int

    private var isCurrentWorkspace: Bool { model.workspaceGeneration == workspaceGeneration }
    private var session: SessionSummary? { model.sessions.first { $0.id == sessionID } }

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
    @State private var contextWindowUsage: ContextWindowUsage?
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
                supportsTextSendingWhileRunning: model.supportsTextSendingWhileRunning,
                supportsSessionCancellation: model.supportsSessionCancellation,
                supportsPermissionResponses: model.supportsPermissionResponses,
                runConfig: runConfigState.displayed,
                contextWindowUsage: contextWindowUsage,
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
                ConversationNavigationTitle(
                    title: title, projectName: session?.projectName,
                    machineName: session?.machineName, connectionStatus: connectionStatus
                )
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
        guard isCurrentWorkspace else { return }
        observedWorkspaceID = model.selectedWorkspaceID
        observedSessionID = sessionID
        conversation = model.cachedConversation(sessionID: sessionID)
        isLoading = conversation == nil
        connectionStatus = "Connecting…"
        var retryDelay = 1
        while !Task.isCancelled {
            do {
                try await model.observeConversation(sessionID: sessionID) { update in
                    guard isCurrentWorkspace else { return }
                    conversation = update.conversation
                    runConfigState.receive(update.runConfig)
                    contextWindowUsage = update.contextWindowUsage
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
        guard isCurrentWorkspace, !isSending, !isCancelling, model.supportsTextSending,
              model.supportsTextSendingWhileRunning ||
                model.sessions.first(where: { $0.id == sessionID })?.activity != .running else { return }
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let choice = runConfigState.choice
        draft = ""
        scrollRequestID += 1
        banner = nil
        isSending = true
        Task {
            guard isCurrentWorkspace else { return }
            defer { isSending = false }
            do {
                let sentChoice = try await model.send(text, runConfig: choice, sessionID: sessionID)
                guard isCurrentWorkspace else { return }
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
        guard isCurrentWorkspace else { return }
        runConfigState.choose(value)
    }

    private func cancelSession() {
        guard isCurrentWorkspace, !isSending, !isCancelling, model.supportsSessionCancellation,
              model.sessions.first(where: { $0.id == sessionID })?.activity == .running else { return }
        isCancelling = true
        banner = nil
        Task {
            guard isCurrentWorkspace else { return }
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
        guard isCurrentWorkspace, !isSending, let text = previousPendingText,
              previousPendingWorkspaceID == model.selectedWorkspaceID else { return }
        isSending = true
        banner = nil
        Task {
            guard isCurrentWorkspace else { return }
            defer { isSending = false }
            do {
                let sentChoice = try await model.send(text, sessionID: sessionID)
                guard isCurrentWorkspace else { return }
                runConfigState.didSend(sentChoice)
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
    let projectName: String?
    let machineName: String?
    let connectionStatus: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            if projectName?.isEmpty == false || machineName?.isEmpty == false {
                HStack(spacing: 4) {
                    if let projectName, !projectName.isEmpty {
                        Text(projectName)
                            .accessibilityIdentifier("conversation-project-name")
                    }
                    if projectName?.isEmpty == false && machineName?.isEmpty == false {
                        Text("·")
                            .accessibilityHidden(true)
                    }
                    if let machineName, !machineName.isEmpty {
                        Text(machineName)
                            .accessibilityIdentifier("conversation-machine-name")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            if let connectionStatus {
                Text(connectionStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("conversation-connection-status")
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
    let supportsTextSendingWhileRunning: Bool
    let supportsSessionCancellation: Bool
    let supportsPermissionResponses: Bool
    let runConfig: SessionRunConfig?
    let contextWindowUsage: ContextWindowUsage?
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
                SessionComposer(draft: $draft, isSending: isSending, isCancelling: isCancelling,
                                isSessionRunning: isSessionRunning,
                                supportsTextSending: supportsTextSending,
                                supportsTextSendingWhileRunning: supportsTextSendingWhileRunning,
                                supportsSessionCancellation: supportsSessionCancellation,
                                runConfig: runConfig?.menu,
                                contextWindowUsage: contextWindowUsage,
                                onSend: onSend, onCancel: onCancel,
                                onChooseRunConfig: { _, value in onChooseRunConfig(value) })
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
        // Even selecting the current baseline is explicit intent: an unconfirmed
        // earlier turn can still change the configuration the next turn inherits.
        choice = selected
    }

    mutating func didSend(_ sentChoice: RunConfigChoice?) {
        config = config?.applying(sentChoice)
        // A retry can send an older choice. Keep any unused selection for the next turn.
        if choice == sentChoice { choice = nil }
    }
}
