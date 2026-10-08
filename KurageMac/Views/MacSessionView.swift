import SwiftUI
import KurageCore

struct MacSessionView: View {
    let model: AppModel
    @Bindable var window: MacWindowState
    let root: SessionSummary
    let isAwake: Bool

    var body: some View {
        let tabs = model.sessionTabs(rootID: root.id).filter { $0.isTabClosed != true }
        let sessionID = window.selectedTab(rootID: root.id)
        VStack(spacing: 0) {
            MacSessionTabBar(
                tabs: tabs,
                rootID: root.id,
                selectedID: sessionID,
                canCreate: model.supportsSessionTabs && model.supportsSessionCreation
                    && model.pendingSessionTab(rootID: root.id) == nil,
                select: { window.selectTab($0, rootID: root.id) },
                newTab: { window.newSession = NewSessionDestination(template: root, isTab: true) }
            )
            MacConversationView(model: model, window: window, sessionID: sessionID, rootID: root.id, isAwake: isAwake)
                .id(sessionID)
        }
        .navigationTitle(root.title)
        .navigationSubtitle(root.projectName ?? "")
        .toolbar {
            ToolbarItem {
                Button("Changes", systemImage: "sidebar.right") { window.showsChanges.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .accessibilityIdentifier("toggle-changes")
            }
        }
        .onChange(of: tabs.map(\.id)) { _, ids in
            if !ids.isEmpty, !ids.contains(sessionID) { window.selectTab(root.id, rootID: root.id) }
        }
    }
}

/// Session tabs sit on a neutral track. The selected tab is a raised chip.
private struct MacSessionTabBar: View {
    let tabs: [SessionSummary]
    let rootID: String
    let selectedID: String
    let canCreate: Bool
    let select: (String) -> Void
    let newTab: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(tabs) { tab in
                        MacSessionTabButton(
                            title: tab.id == rootID ? "Main" : tab.title,
                            selected: tab.id == selectedID
                        ) { select(tab.id) }
                        .accessibilityIdentifier("tab-\(tab.id)")
                        .id(tab.id)
                    }
                    MacSessionTabButton(title: "New tab", systemImage: "plus", selected: false, iconOnly: true, action: newTab)
                        .disabled(!canCreate)
                        .accessibilityIdentifier("new-tab")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
            .onChange(of: selectedID) { _, id in proxy.scrollTo(id, anchor: .center) }
        }
        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.045))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct MacSessionTabButton: View {
    let title: String
    var systemImage: String? = nil
    let selected: Bool
    var iconOnly = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                }
                if !iconOnly {
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, iconOnly ? 8 : 12)
            .frame(maxWidth: iconOnly ? nil : 220)
            .frame(height: 30)
            .background { chrome }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(title)
    }

    @ViewBuilder private var chrome: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if selected {
            shape
                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.06), radius: 1.5, y: 0.5)
                .overlay(shape.strokeBorder(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 1))
        } else if hovering, isEnabled {
            shape.fill(Color.primary.opacity(0.06))
        }
    }
}

private struct MacConversationView: View {
    let model: AppModel
    @Bindable var window: MacWindowState
    let sessionID: String
    let rootID: String
    let isAwake: Bool
    @State private var conversation: Conversation?
    @State private var activity: SessionActivity?
    @State private var observedGeneration: Int?
    @State private var connection = "Connecting…"
    @State private var error: String?
    @State private var cancelling = false
    @State private var confirmReplaceDraft = false
    @State private var atBottom = true
    @State private var latestMessageAt: Double?
    @State private var scrollRequest = 0
    @Environment(\.scenePhase) private var scenePhase

    private struct ObservationKey: Equatable {
        let awake: Bool
        let starting: Bool
    }

    var body: some View {
        let generation = model.workspaceGeneration
        let outgoing = model.outgoingMessage(sessionID: sessionID)
        let turns = model.displayedTurns(conversation?.turns ?? [], sessionID: sessionID)
        let isRunning = (activity ?? model.sessionSummary(sessionID)?.activity) == .running
        let config = window[draft: sessionID].runConfig.displayed
        VStack(spacing: 0) {
            if !connection.isEmpty {
                Text(connection).font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            MacTranscript(model: model, sessionID: sessionID, turns: turns,
                          atBottom: $atBottom, scrollRequest: scrollRequest, isAwake: isAwake)
            if isRunning, let request = conversation?.questions?.first {
                ConversationQuestionCard(
                    request: request,
                    isReady: isAwake && scenePhase == .active && connection.isEmpty
                        && observedGeneration == generation && model.supportsQuestionResponses
                ) { answers in
                    try await model.respondToQuestion(request, answers: answers, sessionID: sessionID,
                                                      workspaceGeneration: generation)
                    try Task.checkCancellation()
                    guard generation == model.workspaceGeneration else { throw CancellationError() }
                    conversation?.questions?.removeAll { $0.id == request.id }
                }
                .id(request.id)
                .frame(maxWidth: 800)
                .padding(12)
            }
            if let outgoing, outgoing.delivery != .sending, outgoing.delivery != .sent {
                HStack {
                    Text(deliveryDescription(outgoing.delivery)).foregroundStyle(.secondary)
                    if case .failed = outgoing.delivery {
                        Button("Edit") {
                            if window[draft: sessionID].hasContent {
                                confirmReplaceDraft = true
                            } else {
                                editFailedMessage()
                            }
                        }
                        .accessibilityIdentifier("edit-failed-message")
                    }
                    if outgoing.canRetry {
                        Button("Retry") {
                            if model.retryOutgoingMessage(sessionID: sessionID) { deliver() }
                        }
                    }
                }.font(.caption).padding(8)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption).padding(8) }
            MacComposer(draft: $window[draft: sessionID], runConfig: config,
                        canSend: isAwake && model.supportsTextSending && outgoing == nil
                            && (!isRunning || model.supportsTextSendingWhileRunning),
                        isRunning: isRunning, canStop: model.supportsSessionCancellation && !cancelling,
                        onSend: send, onStop: stop) { value in
                window[draft: sessionID].runConfig.choose(value)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Replace the current draft?", isPresented: $confirmReplaceDraft) {
            Button("Replace draft", role: .destructive) { editFailedMessage(replacingDraft: true) }
        } message: {
            Text("The failed message and its attachments will replace your current draft.")
        }
        .inspector(isPresented: $window.showsChanges) {
            if window.showsChanges {
                MacChangesInspector(model: model, sessionID: sessionID, conversation: conversation, isAwake: isAwake)
                    .inspectorColumnWidth(min: 300, ideal: 420, max: 700)
                    .accessibilityIdentifier("changes-inspector")
            }
        }
        .task(id: ObservationKey(awake: isAwake, starting: model.isSessionStartPending(sessionID: sessionID))) {
            guard isAwake, !model.isSessionStartPending(sessionID: sessionID) else { return }
            connection = "Connecting…"
            observedGeneration = generation
            model.restoreOutgoingMessage(sessionID: sessionID)
            conversation = model.cachedConversation(sessionID: sessionID)
            var delay = 1
            while !Task.isCancelled {
                do {
                    try await model.observeConversation(sessionID: sessionID, rootSessionID: rootID) { update in
                        conversation = update.conversation
                        activity = update.activity
                        window[draft: sessionID].runConfig.receive(update.runConfig)
                        latestMessageAt = update.lastMessageAt
                        connection = update.syncState == .live ? "" : "Reconnecting…"
                        if update.syncState == .live { delay = 1 }
                    }
                    return
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled else { return }
                    connection = "Connection interrupted. Reconnecting…"
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    delay = min(delay * 2, 30)
                }
            }
        }
        .task(id: atBottom && scenePhase == .active && isAwake ? latestMessageAt : nil) {
            guard atBottom, scenePhase == .active, isAwake, let latestMessageAt else { return }
            for attempt in 0..<3 {
                do {
                    try Task.checkCancellation()
                    try await model.markSessionRead(sessionID: sessionID, lastMessageAt: latestMessageAt,
                                                    workspaceGeneration: generation)
                    return
                } catch is CancellationError { return }
                catch {
                    if attempt < 2 {
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    }
                }
            }
        }
    }

    private func send() {
        let draft = window[draft: sessionID]
        do {
            try model.stageOutgoingMessage(draft.text, composerText: draft.text, mentions: .init(),
                attachments: draft.attachments, runConfig: draft.runConfig.choice, sessionID: sessionID)
            window[draft: sessionID].text = ""
            window[draft: sessionID].attachments = []
            error = nil
            scrollRequest += 1
            deliver()
        } catch { self.error = "Could not prepare the message. Resolve the previous send and try again." }
    }

    private func editFailedMessage(replacingDraft: Bool = false) {
        if !window.editFailedMessage(sessionID: sessionID, model: model, replacingDraft: replacingDraft) {
            error = "Could not edit this message. Its delivery may still be pending."
        } else {
            error = nil
        }
    }

    private func deliver() {
        let workspaceID = model.selectedWorkspaceID
        let turnID = model.outgoingMessage(sessionID: sessionID)?.id
        let generation = model.workspaceGeneration
        // Transmission outlives navigation. The shared outbox owns its result and retry identity.
        Task {
            do {
                let choice = try await model.deliverOutgoingMessage(sessionID: sessionID, workspaceID: workspaceID, turnID: turnID)
                guard generation == model.workspaceGeneration else { return }
                window[draft: sessionID].runConfig.didSend(choice)
            }
            catch { /* The shared outbox exposes delivery failure and same-ID retry. */ }
        }
    }

    private func stop() {
        guard let workspaceID = model.selectedWorkspaceID else { return }
        let generation = model.workspaceGeneration
        cancelling = true
        Task {
            defer { cancelling = false }
            do {
                try await model.cancelSession(sessionID: sessionID, workspaceID: workspaceID,
                                              workspaceGeneration: generation)
            } catch is CancellationError {
                return
            } catch {
                guard generation == model.workspaceGeneration else { return }
                self.error = "Could not stop the session. Try again."
            }
        }
    }

    private func deliveryDescription(_ delivery: MessageDelivery) -> String {
        switch delivery {
        case .unconfirmed: "Delivery not confirmed. Retry checks the same message."
        case .failed(let message): message
        case .notDelivered: "The message was not delivered."
        case .superseded: "This message was superseded."
        case .sending: "Sending…"
        case .sent: "Sent"
        }
    }
}
