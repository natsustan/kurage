import SwiftUI
import MarkdownView

struct ConversationView: View {
    let sessionID: SessionSummary.ID
    let title: String
    let model: AppModel
    var isReadOnly = false

    var body: some View {
        ConversationTabsContent(rootID: sessionID, title: title, model: model,
                                    workspaceGeneration: model.workspaceGeneration, isReadOnly: isReadOnly)
            .id(ConversationScope(sessionID: sessionID, workspaceGeneration: model.workspaceGeneration, isReadOnly: isReadOnly))
    }
}

private struct FileChangesSelection: Identifiable {
    let turnNumber: Int?
    var id: String { turnNumber.map { "turn-\($0)" } ?? "conversation" }
}

private struct ConversationScope: Hashable {
    let sessionID: String
    let workspaceGeneration: Int
    let isReadOnly: Bool
}

// Scope the owner of all transient state, not just its layout subtree.
struct ConversationContent: View {
    let sessionID: SessionSummary.ID
    let title: String
    let model: AppModel
    let workspaceGeneration: Int
    let isReadOnly: Bool
    let isReading: Bool

    private var isCurrentWorkspace: Bool { model.workspaceGeneration == workspaceGeneration }
    private var session: SessionSummary? { model.sessionSummary(sessionID) }

    @Environment(\.dismiss) private var dismiss
    @State private var actionRequest: SessionActionRequest?
    @Environment(\.scenePhase) private var scenePhase
    @State private var observedWorkspaceID: String?
    @State private var observedSessionID: String?
    @State private var refreshID = 0
    @State private var conversation: Conversation?
    @Binding var draft: String
    @Binding var mentions: ComposerMentionState
    @Binding var attachments: [ComposerAttachment]
    @State private var isSending = false
    @State private var pendingTurns: [ConversationTurn] = []
    @State private var isCancelling = false
    @State private var scrollRequestID = 0
    @State private var banner: String?
    @State private var connectionStatus: String?
    @State private var showsConnectionIndicator = false
    @State private var showsConnectionMessage = false
    @State private var previousPendingText: String?
    @State private var previousPendingWorkspaceID: String?
    @Binding var runConfigState: ConversationRunConfigState
    var onNewTab: (() -> Void)? = nil
    var closedTabs: [SessionSummary] = []
    var onReopenTab: (SessionSummary) -> Void = { _ in }
    @State private var contextWindowUsage: ContextWindowUsage?
    @State private var previewImage: ConversationImage?
    @State private var changesSelection: FileChangesSelection?
    @State private var selectedSubtask: ConversationSubtask?
    @State private var observedActivity: SessionActivity?
    @State private var isVisible = false
    @State private var bottomMessageAt: Double?
    @State private var loadedMessageAt: Double?

    private var readReceiptTimestamp: Double? {
        guard isVisible, isReading, scenePhase == .active, isCurrentWorkspace,
              connectionStatus == nil, selectedSubtask == nil,
              previewImage == nil, changesSelection == nil,
              bottomMessageAt == loadedMessageAt else { return nil }
        return loadedMessageAt
    }

    private var displayedConversation: Conversation? {
        if observedWorkspaceID == model.selectedWorkspaceID, observedSessionID == sessionID {
            return conversation ?? model.cachedConversation(sessionID: sessionID)
        }
        return model.cachedConversation(sessionID: sessionID)
    }

    private var displayedTurns: [ConversationTurn] {
        let turns = displayedConversation?.turns ?? []
        guard !pendingTurns.isEmpty else { return turns }
        let receivedIDs = Set(turns.map(\.id))
        return turns + pendingTurns.filter { !receivedIDs.contains($0.id) }
    }

    var body: some View {
        ConversationLayout(
            turns: displayedTurns,
            fileChanges: displayedConversation?.fileChanges ?? [],
            onOpenTurnChanges: { changesSelection = FileChangesSelection(turnNumber: $0) },
            isLoading: displayedConversation == nil,
            isRunning: (session?.activity ?? observedActivity) == .running,
            scrollRequestID: scrollRequestID,
            messageTimestamp: loadedMessageAt,
            onBottomMessage: { bottomMessageAt = $0 },
            loadImage: { image, variant in
                try await model.loadSessionImage(image, conversationSessionID: sessionID, variant: variant)
            },
            onPreviewImage: { previewImage = $0 },
            onRefresh: { refreshID += 1 }
        ) {
            ConversationFooter(
                permission: displayedConversation?.permission,
                question: (observedActivity ?? session?.activity) == .running ? displayedConversation?.questions?.first : nil,
                questionReady: !isReadOnly && isCurrentWorkspace && scenePhase == .active &&
                    connectionStatus == nil && observedWorkspaceID == model.selectedWorkspaceID &&
                    (observedActivity ?? session?.activity) == .running && model.supportsQuestionResponses,
                onQuestionResponse: { request, answers in
                    try await model.respondToQuestion(request, answers: answers, sessionID: sessionID,
                                                      workspaceGeneration: workspaceGeneration)
                    guard isCurrentWorkspace else { throw CancellationError() }
                    conversation?.questions?.removeAll { $0.id == request.id }
                    refreshID += 1
                },
                fileChanges: displayedConversation?.fileChanges ?? [],
                onOpenChanges: { changesSelection = FileChangesSelection(turnNumber: nil) },
                subtasks: displayedConversation?.subtasks ?? [],
                onOpenSubtasks: { selectedSubtask = $0 },
                draft: $draft, mentions: $mentions, attachments: $attachments,
                isSending: isSending,
                isCancelling: isCancelling,
                isSessionRunning: (observedActivity ?? session?.activity) == .running,
                banner: banner,
                connectionMessage: showsConnectionMessage ? connectionStatus : nil,
                supportsTextSending: !isReadOnly && model.supportsTextSending,
                supportsTextSendingWhileRunning: model.supportsTextSendingWhileRunning,
                supportsSessionCancellation: !isReadOnly && model.supportsSessionCancellation,
                supportsPermissionResponses: !isReadOnly && model.supportsPermissionResponses,
                runConfig: runConfigState.displayed,
                contextWindowUsage: contextWindowUsage,
                mentionSourceID: "\(workspaceGeneration):\(sessionID)",
                loadMentionSessions: {
                    guard let projectID = session?.projectID else { return [] }
                    return try await model.mentionSessions(projectID: projectID, excluding: sessionID)
                },
                loadMentionSkills: { try await model.mentionSkills(templateSessionID: sessionID) },
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
        .navigationTitle(session?.title ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $previewImage) { image in
            ConversationImagePreview(image: image) { image, variant in
                try await model.loadSessionImage(image, conversationSessionID: sessionID, variant: variant)
            }
        }
        .sheet(item: $selectedSubtask) { subtask in
            ConversationSubtaskSheet(subtask: displayedConversation?.subtasks?.first { $0.id == subtask.id })
        }
        .sheet(item: $changesSelection) { selection in
            ConversationChangesView(groups: displayedConversation?.fileChanges ?? [],
                                    latestTurnNumber: displayedConversation?.lastTurnNumber ?? 1,
                                    initialTurnNumber: selection.turnNumber)
        }
        .modifier(SessionActionPresenter(model: model, request: $actionRequest, onArchived: { dismiss() }))
        .toolbar {
            if !isReadOnly, let session {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let onNewTab {
                        Button(action: onNewTab) {
                            Image("add")
                        }
                        .accessibilityLabel("New tab")
                        .accessibilityIdentifier("new-session-tab")
                        .disabled(!model.supportsSessionCreation)
                    }
                    Menu {
                        if !closedTabs.isEmpty {
                            Menu("Closed tabs", systemImage: "rectangle.on.rectangle") {
                                ForEach(closedTabs) { tab in
                                    Button(tab.title) { onReopenTab(tab) }
                                }
                            }
                            .accessibilityIdentifier("closed-session-tabs")
                        }
                        if session.parentSessionID == nil {
                            SessionActionButtons(session: session, model: model) { action in
                                actionRequest = SessionActionRequest(session: session, action: action)
                            }
                        } else {
                            Button("Rename session", systemImage: "pencil") {
                                actionRequest = SessionActionRequest(session: session, action: .rename)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis").accessibilityLabel("Session options")
                    }
                    .accessibilityIdentifier("session-options")
                }
            }
            ToolbarItem(placement: .principal) {
                ConversationNavigationTitle(
                    title: session?.title ?? title, projectName: session?.projectName,
                    machineName: session?.machineName,
                    connectionStatus: showsConnectionIndicator ? connectionStatus : nil
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if (observedActivity ?? session?.activity) == .running {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Agent running")
                }
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: readReceiptTimestamp) {
            guard let timestamp = readReceiptTimestamp else { return }
            // Keep transient receipt failures separate from conversation delivery.
            for attempt in 0..<3 {
                do {
                    try Task.checkCancellation()
                    try await model.markSessionRead(sessionID: sessionID, lastMessageAt: timestamp,
                                                    workspaceGeneration: workspaceGeneration)
                    return
                } catch is CancellationError { return }
                catch {
                    if attempt < 2 {
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    }
                }
            }
        }
        .task(id: ObservationKey(workspaceID: model.selectedWorkspaceID, sessionID: sessionID,
                                 active: scenePhase == .active, refreshID: refreshID)) {
            guard scenePhase == .active else { return }
            await observe()
        }
        .task(id: scenePhase == .active ? connectionStatus : nil) {
            await updateConnectionVisibility()
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
        // Restore only when this scoped view first opens; reconnecting must preserve edits.
        if observedSessionID == nil, !isReadOnly,
           let pending = model.pendingTextSend(sessionID: sessionID) {
            previousPendingText = pending.text
            previousPendingWorkspaceID = model.selectedWorkspaceID
            if draft.isEmpty { draft = pending.text; attachments = pending.attachments }
            banner = "Send could not be confirmed. Retry to resume the same message."
        }
        observedWorkspaceID = model.selectedWorkspaceID
        observedSessionID = sessionID
        conversation = model.cachedConversation(sessionID: sessionID)
        connectionStatus = "Connecting…"
        var retryDelay = 1
        while !Task.isCancelled {
            do {
                try await model.observeConversation(sessionID: sessionID) { update in
                    guard isCurrentWorkspace else { return }
                    receiveConversation(update.conversation)
                    observedActivity = update.activity
                    runConfigState.receive(update.runConfig)
                    contextWindowUsage = update.contextWindowUsage
                    loadedMessageAt = update.lastMessageAt
                    connectionStatus = update.syncState == .live ? nil : "Reconnecting…"
                    if update.syncState == .live { retryDelay = 1 }
                }
                return
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                connectionStatus = "Reconnecting…"
                do { try await Task.sleep(for: .seconds(retryDelay)) }
                catch { return }
                retryDelay = min(retryDelay * 2, 30)
            }
        }
    }

    private func updateConnectionVisibility() async {
        guard scenePhase == .active, connectionStatus != nil else {
            showsConnectionIndicator = false
            showsConnectionMessage = false
            return
        }
        if !showsConnectionIndicator {
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
            showsConnectionIndicator = true
        }
        guard !showsConnectionMessage else { return }
        do { try await Task.sleep(for: .seconds(4)) }
        catch { return }
        showsConnectionMessage = true
    }

    private func receiveConversation(_ latest: Conversation) {
        conversation = latest
        guard !pendingTurns.isEmpty else { return }
        let receivedIDs = Set(latest.turns.map(\.id))
        pendingTurns.removeAll { receivedIDs.contains($0.id) }
    }

    private func addPendingTurn(id: ConversationTurn.ID?, text: String) {
        guard let id, !displayedTurns.contains(where: { $0.id == id }) else { return }
        pendingTurns.append(ConversationTurn(id: id, author: .user, text: text))
    }

    private func removePendingTurn(id: ConversationTurn.ID?) {
        guard let id else { return }
        pendingTurns.removeAll { $0.id == id }
    }

    private func sendDraft() {
        guard !isReadOnly, isCurrentWorkspace, !isSending, !isCancelling, model.supportsTextSending,
              model.supportsTextSendingWhileRunning ||
                (observedActivity ?? session?.activity) != .running else { return }
        let originalDraft = draft
        let originalMentions = mentions
        let text = mentions.expanded(draft)
        let sentAttachments = attachments
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        let pending = model.pendingTextSend(sessionID: sessionID)
        let turnID: ConversationTurn.ID
        if let pending, pending.text == trimmed {
            turnID = pending.turnID
        } else {
            turnID = UUID().uuidString.lowercased()
        }
        let choice = runConfigState.choice
        draft = ""
        mentions.clear()
        scrollRequestID += 1
        banner = nil
        isSending = true
        // A different unconfirmed message must be retried before this one can be authored.
        if pending == nil || pending?.text == trimmed { addPendingTurn(id: turnID, text: trimmed) }
        Task {
            guard isCurrentWorkspace else { return }
            defer { isSending = false }
            do {
                let sentChoice = try await model.send(text, attachments: sentAttachments, runConfig: choice, turnID: turnID,
                                                       sessionID: sessionID)
                guard isCurrentWorkspace else { return }
                attachments.removeAll { sentAttachments.contains($0) }
                previousPendingText = nil
                previousPendingWorkspaceID = nil
                runConfigState.didSend(sentChoice)
                if let latest = try? await model.conversation(sessionID: sessionID) {
                    receiveConversation(latest)
                }
            } catch LodyClientError.deliveryUnconfirmed {
                guard isCurrentWorkspace else { return }
                removePendingTurn(id: turnID)
                draft = originalDraft
                mentions = originalMentions
                previousPendingText = trimmed
                previousPendingWorkspaceID = model.selectedWorkspaceID
                banner = "Send could not be confirmed. Retry to resume the same message."
            } catch LodyClientError.previousSendPending(let previousText) {
                guard isCurrentWorkspace else { return }
                removePendingTurn(id: turnID)
                draft = originalDraft
                mentions = originalMentions
                previousPendingText = previousText
                previousPendingWorkspaceID = model.selectedWorkspaceID
                banner = "An earlier send is unconfirmed. Retry it before sending different text."
            } catch LodyClientError.sendSuperseded {
                guard isCurrentWorkspace else { return }
                removePendingTurn(id: turnID)
                draft = originalDraft
                mentions = originalMentions
                previousPendingText = nil
                previousPendingWorkspaceID = nil
                banner = "A newer message took precedence. Send again to create a new message."
            } catch LodyClientError.sessionBusy {
                guard isCurrentWorkspace else { return }
                removePendingTurn(id: turnID)
                draft = originalDraft
                mentions = originalMentions
                banner = "Wait for the current reply before sending."
            } catch is CancellationError {
                removePendingTurn(id: turnID)
                return
            } catch {
                guard isCurrentWorkspace else { return }
                removePendingTurn(id: turnID)
                draft = originalDraft
                mentions = originalMentions
                previousPendingText = model.pendingTextSend(sessionID: sessionID)?.text
                previousPendingWorkspaceID = previousPendingText == nil ? nil : model.selectedWorkspaceID
                banner = previousPendingText == nil
                    ? "Could not upload attachments. Review your draft and try again."
                    : "Could not confirm send. Retry to resume the same message."
            }
        }
    }

    private func chooseRunConfig(_ value: String) {
        guard isCurrentWorkspace else { return }
        runConfigState.choose(value)
    }

    private func cancelSession() {
        guard !isReadOnly, isCurrentWorkspace, !isSending, !isCancelling, model.supportsSessionCancellation,
              (observedActivity ?? session?.activity) == .running else { return }
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
        guard !isReadOnly, isCurrentWorkspace, !isSending, let text = previousPendingText,
              previousPendingWorkspaceID == model.selectedWorkspaceID else { return }
        let pending = model.pendingTextSend(sessionID: sessionID)
        let turnID = pending?.text == text ? pending?.turnID : nil
        isSending = true
        addPendingTurn(id: turnID, text: text)
        banner = nil
        Task {
            guard isCurrentWorkspace else { return }
            defer { isSending = false }
            do {
                let sentChoice = try await model.send(text, attachments: pending?.attachments ?? [],
                    turnID: turnID ?? UUID().uuidString.lowercased(), sessionID: sessionID)
                guard isCurrentWorkspace else { return }
                attachments.removeAll { pending?.attachments.contains($0) == true }
                runConfigState.didSend(sentChoice)
                previousPendingText = nil
                previousPendingWorkspaceID = nil
                if mentions.expanded(draft).trimmingCharacters(in: .whitespacesAndNewlines) == text {
                    draft = ""
                    mentions.clear()
                }
                banner = draft.isEmpty ? nil : "Earlier message confirmed. Review your draft before sending."
                if let latest = try? await model.conversation(sessionID: sessionID) {
                    receiveConversation(latest)
                }
            } catch LodyClientError.sendSuperseded {
                guard isCurrentWorkspace else { return }
                removePendingTurn(id: turnID)
                previousPendingText = nil
                previousPendingWorkspaceID = nil
                banner = "Earlier message was replaced. You can send your draft as a new message."
            } catch is CancellationError {
                removePendingTurn(id: turnID)
                return
            } catch {
                guard isCurrentWorkspace else { return }
                removePendingTurn(id: turnID)
                if model.pendingTextSend(sessionID: sessionID) == nil {
                    previousPendingText = nil
                    previousPendingWorkspaceID = nil
                    banner = "Could not upload attachments. Review your draft and try again."
                } else {
                    banner = "Earlier send is still unconfirmed. Retry it before sending different text."
                }
            }
        }
    }

    private func respond(_ decision: PermissionDecision, requestID: PermissionPrompt.ID) {
        guard !isReadOnly else { return }
        Task {
            do {
                try await model.respond(decision, requestID: requestID, sessionID: sessionID)
                receiveConversation(try await model.conversation(sessionID: sessionID))
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

    private var hasSubtitle: Bool {
        projectName?.isEmpty == false || machineName?.isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if !hasSubtitle {
                    connectionIndicator
                }
            }
            if hasSubtitle {
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
                    connectionIndicator
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private var connectionIndicator: some View {
        Group {
            if let connectionStatus {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel(connectionStatus)
                    .accessibilityIdentifier("conversation-connection-status")
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 14, height: 14)
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
    var fileChanges: ConversationFileChangeGroup? = nil
    var onOpenChanges: (Int) -> Void = { _ in }
    var onToggleChanges: () -> Void = {}
    var disclosures = TurnDisclosures()
    var isRunning = false

    var body: some View {
        let alignment: HorizontalAlignment = turn.author == .user ? .trailing : .leading
        VStack(alignment: alignment, spacing: 8) {
            if isRunning, turn.author == .agent, let timing = turn.timing {
                TurnWorkingLabel(turnID: turn.id, timing: timing)
            }
            if let work = turn.displayedWork {
                let content = turn.content
                let insertionIndex = min(max(work.insertionIndex, 0), content.count)
                blocks(Array(content.prefix(insertionIndex)), alignment: alignment)
                TurnWorkDisclosure(turnID: turn.id, work: work, disclosures: disclosures) {
                    blocks(work.parts, alignment: alignment)
                }
                blocks(Array(content.dropFirst(insertionIndex)), alignment: alignment)
            } else {
                blocks(turn.content, alignment: alignment)
            }
            if turn.author == .agent, let fileChanges, !fileChanges.files.isEmpty {
                TurnFileChangesCard(group: fileChanges,
                                    onOpen: { onOpenChanges(fileChanges.turnNumber) },
                                    onToggle: onToggleChanges)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: turn.author == .user ? .trailing : .leading)
    }

    private func blocks(_ content: [ConversationPart], alignment: HorizontalAlignment) -> some View {
        ForEach(conversationBlocks(author: turn.author, content: content)) { block in
            switch block {
            case .file(_, let file):
                Label {
                    VStack(alignment: .leading) {
                        Text(file.fileName).lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "doc") }
                .padding(12).background(.quaternary, in: .rect(cornerRadius: 12))
            case .text(_, let text):
                messageText(text)
            case .images(_, let images):
                ConversationImageGroup(
                    images: images,
                    alignment: alignment,
                    loadImage: loadImage,
                    onPreview: onPreviewImage
                )
            case .activity(let activity):
                ConversationActivityRow(turnID: turn.id, activity: activity, disclosures: disclosures)
            }
        }
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
    let question: ConversationQuestionRequest?
    let questionReady: Bool
    let onQuestionResponse: @MainActor (ConversationQuestionRequest, [String: QuestionAnswer]?) async throws -> Void
    let fileChanges: [ConversationFileChangeGroup]
    let onOpenChanges: () -> Void
    let subtasks: [ConversationSubtask]
    let onOpenSubtasks: (ConversationSubtask) -> Void
    @Binding var draft: String
    @Binding var mentions: ComposerMentionState
    @Binding var attachments: [ComposerAttachment]
    let isSending: Bool
    let isCancelling: Bool
    let isSessionRunning: Bool
    let banner: String?
    let connectionMessage: String?
    let supportsTextSending: Bool
    let supportsTextSendingWhileRunning: Bool
    let supportsSessionCancellation: Bool
    let supportsPermissionResponses: Bool
    let runConfig: SessionRunConfig?
    let contextWindowUsage: ContextWindowUsage?
    let mentionSourceID: String
    let loadMentionSessions: @MainActor () async throws -> [MentionSession]
    let loadMentionSkills: @MainActor () async throws -> [MentionSkill]
    let onSend: () -> Void
    let onCancel: () -> Void
    let onChooseRunConfig: (String) -> Void
    let canRetryPrevious: Bool
    let onRetryPrevious: () -> Void
    let onDecision: (PermissionDecision, PermissionPrompt.ID) -> Void

    var body: some View {
        // Keep these glass backgrounds noninteractive: on iOS 27 their hit
        // regions intercept attachment-menu items overlapping the footer.
        // The controls themselves retain their normal button interactions.
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                if let banner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let connectionMessage {
                    Text(connectionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("conversation-connection-message")
                }
                if canRetryPrevious {
                    Button("Retry earlier message", action: onRetryPrevious)
                        .font(.footnote)
                        .disabled(isSending)
                }
                if let question {
                    ConversationQuestionCard(request: question, isReady: questionReady) { answers in
                        try await onQuestionResponse(question, answers)
                    }
                    .id(question.id)
                }
                if let permission, supportsPermissionResponses {
                    PermissionCard(permission: permission, onDecision: onDecision)
                }
                if !subtasks.isEmpty || !fileChanges.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { conversationHUDs }
                        VStack(spacing: 8) { conversationHUDs }
                    }
                    .frame(maxWidth: .infinity)
                }
                if supportsTextSending || supportsSessionCancellation && isSessionRunning {
                    SessionComposer(draft: $draft, mentions: $mentions, attachments: $attachments,
                                    isSending: isSending, isCancelling: isCancelling,
                                    isSessionRunning: isSessionRunning,
                                    supportsTextSending: supportsTextSending,
                                    supportsTextSendingWhileRunning: supportsTextSendingWhileRunning,
                                    supportsSessionCancellation: supportsSessionCancellation,
                                    runConfig: runConfig?.menu,
                                    contextWindowUsage: contextWindowUsage,
                                    mentionSourceID: mentionSourceID,
                                    loadMentionSessions: loadMentionSessions,
                                    loadMentionSkills: loadMentionSkills,
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

    @ViewBuilder
    private var conversationHUDs: some View {
        if !fileChanges.isEmpty {
            ConversationChangesHUD(summary: FileChangeSummary(fileChanges), compact: !subtasks.isEmpty,
                                   onOpen: onOpenChanges)
        }
        if !subtasks.isEmpty {
            ConversationSubtasksButton(subtasks: subtasks, onOpen: onOpenSubtasks)
        }
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
