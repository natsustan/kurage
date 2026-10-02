import SwiftUI
import MarkdownView

struct ConversationView: View {
    let sessionID: SessionSummary.ID
    let title: String
    let model: AppModel
    var isReadOnly = false
    var draftStore: ConversationDraftStore? = nil
    var onArchived: (() -> Void)? = nil

    var body: some View {
        ConversationTabsContent(rootID: sessionID, title: title, model: model,
                                    workspaceGeneration: model.workspaceGeneration, isReadOnly: isReadOnly,
                                    draftStore: draftStore, onArchived: onArchived)
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
    @Binding var isCancelling: Bool
    @State private var scrollRequestID = 0
    @Binding var banner: String?
    @State private var connectionStatus: String?
    @State private var showsConnectionIndicator = false
    @State private var showsConnectionMessage = false
    @Binding var runConfigState: ConversationRunConfigState
    let rootSessionID: SessionSummary.ID
    var onArchived: (() -> Void)? = nil
    var onNewTab: (() -> Void)? = nil
    var closedTabs: [SessionSummary] = []
    var onReopenTab: (SessionSummary) -> Void = { _ in }
    var onEditSessionStart: ((OutgoingMessage) -> Void)? = nil
    @State private var contextWindowUsage: ContextWindowUsage?
    @State private var previewImage: ConversationImage?
    @State private var changesSelection: FileChangesSelection?
    @State private var selectedSubtask: ConversationSubtask?
    @State private var observedActivity: SessionActivity?
    @State private var isVisible = false
    @State private var bottomMessageAt: Double?
    @State private var loadedMessageAt: Double?

    /// The live observation is fresher than the session list or the tab
    /// projection, which both lag behind a turn that just started or ended.
    private var isRunning: Bool { (observedActivity ?? session?.activity) == .running }

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

    private var outgoingMessage: OutgoingMessage? { model.outgoingMessage(sessionID: sessionID) }
    private var isStarting: Bool { model.isSessionStartPending(sessionID: sessionID) }
    private var isSending: Bool { outgoingMessage?.delivery == .sending }
    private var canRetryMessage: Bool {
        guard !isReadOnly, isCurrentWorkspace, scenePhase == .active, !isCancelling,
              let message = outgoingMessage, message.canRetry else { return false }
        return message.delivery != .sending && message.delivery != .sent &&
            (message.delivery == .unconfirmed || !isRunning || model.supportsTextSendingWhileRunning)
    }
    private var canEditMessage: Bool {
        !isReadOnly && isCurrentWorkspace && scenePhase == .active &&
            draft.isEmpty && attachments.isEmpty && !isSending
    }

    private var displayedTurns: [ConversationTurn] {
        model.displayedTurns(displayedConversation?.turns ?? [], sessionID: sessionID)
    }

    var body: some View {
        ConversationLayout(
            turns: displayedTurns,
            fileChanges: displayedConversation?.fileChanges ?? [],
            onOpenTurnChanges: { changesSelection = FileChangesSelection(turnNumber: $0) },
            isLoading: displayedConversation == nil && outgoingMessage == nil,
            isRunning: isRunning,
            scrollRequestID: scrollRequestID,
            messageTimestamp: loadedMessageAt,
            onBottomMessage: { bottomMessageAt = $0 },
            loadImage: { image, variant in
                try await model.loadSessionImage(image, conversationSessionID: sessionID, variant: variant)
            },
            onPreviewImage: { previewImage = $0 },
            onRefresh: { refreshID += 1 },
            canRetryMessage: canRetryMessage,
            canEditMessage: canEditMessage,
            onRetryMessage: { id in if outgoingMessage?.id == id { retryMessage() } },
            onEditMessage: { id in if outgoingMessage?.id == id { editMessage() } }
        ) {
            ConversationFooter(
                permission: displayedConversation?.permission,
                question: isRunning ? displayedConversation?.questions?.first : nil,
                questionReady: !isReadOnly && isCurrentWorkspace && scenePhase == .active &&
                    connectionStatus == nil && observedWorkspaceID == model.selectedWorkspaceID &&
                    isRunning && model.supportsQuestionResponses,
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
                canSubmit: outgoingMessage == nil,
                isCancelling: isCancelling,
                isSessionRunning: isRunning,
                banner: banner,
                connectionMessage: showsConnectionMessage ? connectionStatus : nil,
                supportsTextSending: !isReadOnly && model.supportsTextSending,
                supportsTextSendingWhileRunning: model.supportsTextSendingWhileRunning,
                supportsSessionCancellation: !isReadOnly && !isStarting && model.supportsSessionCancellation,
                supportsPermissionResponses: !isReadOnly && model.supportsPermissionResponses,
                runConfig: runConfigState.displayed,
                contextWindowUsage: contextWindowUsage,
                focusesComposerOnAppear: isStarting,
                dismissComposerFocus: changesSelection != nil,
                mentionSourceID: "\(workspaceGeneration):\(sessionID):\(isStarting)",
                loadMentionSessions: {
                    guard let projectID = session?.projectID else { return [] }
                    return try await model.mentionSessions(projectID: projectID, excluding: sessionID)
                },
                loadMentionSkills: {
                    guard !isStarting else { return [] }
                    return try await model.mentionSkills(templateSessionID: sessionID)
                },
                onSend: sendDraft,
                onCancel: cancelSession,
                onChooseRunConfig: chooseRunConfig,
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
                                    initialTurnNumber: selection.turnNumber,
                                    loadPreview: model.supportsHistoricalFilePreviews ? { group, file in
                                        guard let workspaceID = observedWorkspaceID, isCurrentWorkspace else { throw CancellationError() }
                                        return try await model.filePreview(sessionID: sessionID, turnID: group.id,
                                                                            file: file, workspaceID: workspaceID)
                                    } : nil)
        }
        .modifier(SessionActionPresenter(model: model, request: $actionRequest, onArchived: {
            if let onArchived { onArchived() } else { dismiss() }
        }))
        .toolbar {
            if !isReadOnly, let session {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let onNewTab {
                        Button(action: onNewTab) {
                            Image("add")
                        }
                        .accessibilityLabel("New tab")
                        .accessibilityIdentifier("new-session-tab")
                        .disabled(!model.supportsSessionCreation || isStarting)
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
                    .disabled(isStarting)
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
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onChange(of: isSending) { _, sending in
            // A send may finish in the previous view after this tab was rebuilt.
            if !sending, isCurrentWorkspace, let latest = model.cachedConversation(sessionID: sessionID) {
                receiveConversation(latest)
            }
        }
        .onChange(of: outgoingMessage?.id) { _, id in
            if id == nil, isCurrentWorkspace, let latest = model.cachedConversation(sessionID: sessionID) {
                receiveConversation(latest)
            }
        }
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
                                 active: scenePhase == .active && !isStarting, refreshID: refreshID)) {
            guard scenePhase == .active, !isStarting else { return }
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
        if !isReadOnly { model.restoreOutgoingMessage(sessionID: sessionID) }
        observedWorkspaceID = model.selectedWorkspaceID
        observedSessionID = sessionID
        conversation = model.cachedConversation(sessionID: sessionID)
        connectionStatus = "Connecting…"
        var retryDelay = 1
        while !Task.isCancelled {
            do {
                try await model.observeConversation(sessionID: sessionID, rootSessionID: rootSessionID) { update in
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
    }

    private func sendDraft() {
        guard !isReadOnly, isCurrentWorkspace, !isSending, !isCancelling, model.supportsTextSending,
              outgoingMessage == nil,
              model.supportsTextSendingWhileRunning || !isRunning else { return }
        do {
            try model.stageOutgoingMessage(mentions.expanded(draft), composerText: draft, mentions: mentions,
                attachments: attachments, runConfig: runConfigState.choice, sessionID: sessionID)
        } catch {
            banner = "Could not prepare this message. Try again."
            return
        }
        draft = ""
        mentions.clear()
        attachments = []
        scrollRequestID += 1
        banner = nil
        deliverMessage()
    }

    private func retryMessage() {
        guard canRetryMessage, model.retryOutgoingMessage(sessionID: sessionID) else { return }
        deliverMessage()
    }

    private func editMessage() {
        let editsStart = isStarting
        guard canEditMessage, let message = model.takeFailedOutgoingMessage(sessionID: sessionID) else { return }
        if editsStart {
            onEditSessionStart?(message)
            return
        }
        draft = message.composerText
        mentions = message.mentions
        attachments = message.attachments
        banner = nil
    }

    private func deliverMessage() {
        let sendingWorkspaceID = model.selectedWorkspaceID
        let sendingTurnID = outgoingMessage?.id
        Task {
            do {
                let choice = try await model.deliverOutgoingMessage(sessionID: sessionID,
                    workspaceID: sendingWorkspaceID, turnID: sendingTurnID)
                guard isCurrentWorkspace else { return }
                runConfigState.didSend(choice)
                if let latest = model.cachedConversation(sessionID: sessionID) { receiveConversation(latest) }
            } catch {
                // AppModel retains the message and its retry identity. A newer
                // draft is never replaced by the completion of an earlier send.
            }
        }
    }

    private func chooseRunConfig(_ value: String) {
        guard isCurrentWorkspace else { return }
        runConfigState.choose(value)
    }

    private func cancelSession() {
        guard !isReadOnly, isCurrentWorkspace, !isSending, !isCancelling, model.supportsSessionCancellation,
              isRunning else { return }
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
        // The placeholder fills the space above the composer. Its minimum
        // content size must not push the composer below the keyboard, even
        // while its hosting view is hidden behind a populated transcript.
        GeometryReader { geometry in
            Group {
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
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
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
    var canRetryMessage = false
    var canEditMessage = false
    var onRetryMessage: () -> Void = {}
    var onEditMessage: () -> Void = {}

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
            } else if turn.author == .user {
                HStack(alignment: .bottom, spacing: 8) {
                    Spacer(minLength: 44)
                    messageDelivery(turn.delivery == .sending ? nil : turn.delivery)
                    VStack(alignment: .trailing, spacing: 8) {
                        blocks(turn.content, alignment: alignment)
                    }
                }
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

    private func messageDelivery(_ delivery: MessageDelivery?) -> some View {
        MessageDeliveryView(turnID: turn.id, delivery: delivery,
            canRetry: canRetryMessage, canEdit: canEditMessage,
            onRetry: onRetryMessage, onEdit: onEditMessage)
            .fixedSize()
    }

    private func blocks(_ content: [ConversationPart], alignment: HorizontalAlignment) -> some View {
        let contentBlocks = conversationBlocks(author: turn.author, content: content)
        return ForEach(contentBlocks) { block in
            blockContent(block, alignment: alignment)
                .overlay(alignment: .bottomLeading) {
                    if turn.author == .user, turn.delivery == .sending, block.id == contentBlocks.last?.id {
                        // Anchor to the last bubble, even when a wider image sits above it.
                        // Use the leading gutter without changing the bubble's proposal.
                        messageDelivery(.sending)
                            .padding(.trailing, 4)
                            .frame(width: 0, alignment: .trailing)
                    }
                }
        }
    }

    @ViewBuilder
    private func blockContent(_ block: ConversationBlock, alignment: HorizontalAlignment) -> some View {
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

    @ViewBuilder
    private func messageText(_ text: String) -> some View {
        if turn.author == .user {
            UserMessageText(text: text)
        } else {
            MarkdownView(text)
                .tint(.primary)
                .tint(Color(uiColor: .secondaryLabel), for: .inlineCodeBlock)
                .font(.system(.footnote, design: .monospaced), for: .codeBlock)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MessageDeliveryView: View {
    let turnID: String
    let delivery: MessageDelivery?
    let canRetry: Bool
    let canEdit: Bool
    let onRetry: () -> Void
    let onEdit: () -> Void
    @State private var showsProgress = false

    var body: some View {
        Group {
            if let delivery, delivery != .sent {
                HStack(spacing: 0) {
                    switch delivery {
                    case .sending:
                        if showsProgress {
                            ProgressView().controlSize(.mini)
                                .frame(height: 44)
                                .accessibilityLabel("Sending")
                        }
                    case .unconfirmed:
                        retryButton
                            .accessibilityValue("Waiting for confirmation")
                    case .failed(let reason):
                        HStack(spacing: 0) {
                            retryButton
                                .accessibilityValue(reason)
                            Button("Edit", systemImage: "pencil", action: onEdit)
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                                .disabled(!canEdit)
                                .accessibilityIdentifier("edit-message-\(turnID)")
                        }
                        .foregroundStyle(.red)
                        .contextMenu {
                            Text(reason)
                            Button("Retry", action: onRetry).disabled(!canRetry)
                            Button("Edit", action: onEdit).disabled(!canEdit)
                        }
                    case .superseded:
                        Image(systemName: "exclamationmark.circle")
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Not run: replaced by a newer message")
                    case .notDelivered:
                        Image(systemName: "exclamationmark.circle")
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Not delivered")
                    case .sent:
                        EmptyView()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("message-delivery-\(turnID)")
            }
        }
        .task(id: delivery) {
            showsProgress = false
            guard delivery == .sending else { return }
            do { try await Task.sleep(for: .milliseconds(600)) }
            catch { return }
            showsProgress = true
        }
    }

    private var retryButton: some View {
        Button("Retry", systemImage: "arrow.clockwise", action: onRetry)
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            .disabled(!canRetry)
            .accessibilityIdentifier("retry-message-\(turnID)")
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
    let canSubmit: Bool
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
    var focusesComposerOnAppear = false
    var dismissComposerFocus = false
    let mentionSourceID: String
    let loadMentionSessions: @MainActor () async throws -> [MentionSession]
    let loadMentionSkills: @MainActor () async throws -> [MentionSkill]
    let onSend: () -> Void
    let onCancel: () -> Void
    let onChooseRunConfig: (String) -> Void
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
                                    isSending: isSending, allowsEditingWhileSending: true, isCancelling: isCancelling,
                                    isSessionRunning: isSessionRunning,
                                    supportsTextSending: supportsTextSending,
                                    supportsTextSendingWhileRunning: supportsTextSendingWhileRunning,
                                    supportsSessionCancellation: supportsSessionCancellation,
                                    runConfig: runConfig?.menu,
                                    contextWindowUsage: contextWindowUsage,
                                    canSubmit: canSubmit,
                                    focusesOnAppear: focusesComposerOnAppear,
                                    dismissFocus: dismissComposerFocus,
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
