import SwiftUI
import KurageCore

struct MacSessionView: View {
    let model: AppModel
    @Bindable var window: MacWindowState
    let root: SessionSummary
    let isAwake: Bool
    @AppStorage(MacTabLayout.storageKey) private var tabLayout: MacTabLayout = .separate
    @State private var width: CGFloat = 0

    var body: some View {
        let tabs = model.sessionTabs(rootID: root.id).filter { $0.isTabClosed != true }
        let sessionID = window.selectedTab(rootID: root.id)
        // A narrow detail column cannot fit the title, tabs and buttons in one toolbar
        // row, and NSToolbar would hide the tabs behind its overflow menu.
        let compact = tabLayout == .compact && width >= MacSessionTabBar.compactMinimumWidth
        MacConversationView(model: model, window: window, sessionID: sessionID, rootID: root.id, isAwake: isAwake,
                            tabsInToolbar: compact) {
            if !compact { tabBar(.row, tabs: tabs, selectedID: sessionID) }
        }
        .id(sessionID)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle(MacSessionContextTitle.title(projectName: root.projectName))
        .navigationSubtitle(MacSessionContextTitle.subtitle(machineName: root.machineName))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if compact {
                ToolbarItem {
                    tabBar(.toolbar, tabs: tabs, selectedID: sessionID)
                        .frame(maxWidth: width - MacSessionTabBar.compactReservedWidth)
                }
                .sharedBackgroundVisibility(.hidden)
            }
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

    private func tabBar(_ style: MacSessionTabBar.Style, tabs: [SessionSummary], selectedID: String) -> MacSessionTabBar {
        MacSessionTabBar(
            style: style,
            tabs: tabs,
            rootID: root.id,
            selectedID: selectedID,
            canCreate: model.supportsSessionTabs && model.supportsSessionCreation
                && model.pendingSessionTab(rootID: root.id) == nil,
            select: { window.selectTab($0, rootID: root.id) },
            newTab: { window.newSession = NewSessionDestination(template: root, isTab: true) }
        )
    }
}

/// The toolbar names the project and machine. The session name lives on its tab.
private enum MacSessionContextTitle {
    static func title(projectName: String?) -> String {
        trimmed(projectName) ?? "Conversation"
    }

    /// Bonjour host names end in `.local`, which adds nothing to the machine name.
    static func subtitle(machineName: String?) -> String {
        guard let name = trimmed(machineName) else { return "" }
        return name.hasSuffix(".local") ? String(name.dropLast(6)) : name
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Session tabs are always shown, so the transcript does not move when a tab opens
/// or closes. On their own row they share the conversation background and the selected
/// tab is underlined; in the toolbar the selected tab is a pill, like Safari's compact tabs.
private struct MacSessionTabBar: View {
    enum Style {
        case row
        case toolbar
    }

    /// Below this detail width the compact layout falls back to the row.
    static let compactMinimumWidth: CGFloat = 600
    /// Room kept for the title, the Changes button and, with the sidebar hidden, the window
    /// controls. The toolbar item reports its content width, so an uncapped strip of many
    /// tabs would push the whole item into the overflow menu.
    static let compactReservedWidth: CGFloat = 320

    let style: Style
    let tabs: [SessionSummary]
    let rootID: String
    let selectedID: String
    let canCreate: Bool
    let select: (String) -> Void
    let newTab: () -> Void
    @State private var overflow = MacTabOverflow()
    @State private var contentWidth: CGFloat?

    /// On the row this matches the transcript: an 800pt column with a 24pt gutter, so the
    /// first tab starts on the conversation's text edge and the gutters hold the overflow fades.
    private var gutter: CGFloat { style == .row ? 24 : 8 }
    private var spacing: CGFloat { style == .row ? 20 : 4 }

    var body: some View {
        // New Tab stays outside the scroll view so it is reachable however many tabs are open.
        // Capping the scroll view at its content width keeps it beside the last tab otherwise.
        let strip = HStack(spacing: spacing - gutter) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tabs) { tab in
                            MacSessionTabButton(tab: tab, selected: tab.id == selectedID, style: style) { select(tab.id) }
                                .accessibilityIdentifier("tab-\(tab.id)")
                                .id(tab.id)
                        }
                    }
                    .padding(.horizontal, gutter)
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: MacTabOverflow.self) { geometry in
                    MacTabOverflow(
                        leading: geometry.contentOffset.x > 1,
                        trailing: geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 1)
                } action: { _, value in
                    overflow = value
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.width } action: { _, width in
                    contentWidth = width
                }
                .mask { fade }
                .frame(maxWidth: contentWidth)
                .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
                .onChange(of: selectedID) { _, id in proxy.scrollTo(id, anchor: .center) }
            }
            MacNewTabButton(action: newTab)
                .disabled(!canCreate)
                .accessibilityIdentifier("new-tab")
        }
        switch style {
        case .row:
            strip
                .frame(height: 36)
                .frame(maxWidth: 800 + gutter * 2, alignment: .leading)
                .frame(maxWidth: .infinity)
        case .toolbar:
            strip
                .frame(height: 28)
        }
    }

    private var fade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [overflow.leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: gutter)
            Color.black
            LinearGradient(colors: [.black, overflow.trailing ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: gutter)
        }
    }
}

private struct MacTabOverflow: Equatable {
    var leading = false
    var trailing = false
}

private struct MacSessionTabButton: View {
    let tab: SessionSummary
    let selected: Bool
    let style: MacSessionTabBar.Style
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(tab.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                status
            }
            .foregroundStyle(selected || hovering ? Color.primary : Color.secondary)
            .padding(.horizontal, style == .toolbar ? 10 : 0)
            .frame(maxWidth: style == .toolbar ? 200 : 220)
            .frame(maxHeight: .infinity)
            .background {
                if style == .toolbar, selected || hovering {
                    Capsule().fill(Color.primary.opacity(selected ? 0.08 : 0.05))
                }
            }
            .overlay(alignment: .bottom) {
                if style == .row, selected { Capsule().fill(Color.primary).frame(height: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityValue(statusDescription)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(tab.title)
    }

    /// Running wins over unread. The open tab is being read, so it never shows a dot.
    @ViewBuilder private var status: some View {
        if tab.activity == .running {
            ProgressView().controlSize(.mini).accessibilityHidden(true)
        } else if tab.isUnread, !selected {
            Circle().fill(Color.accentColor).frame(width: 6, height: 6).accessibilityHidden(true)
        }
    }

    private var statusDescription: String {
        if tab.activity == .running { return "Running" }
        return tab.isUnread && !selected ? "Unread" : ""
    }
}

private struct MacNewTabButton: View {
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button("New tab", systemImage: "plus", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(hovering && isEnabled ? Color.primary : Color.secondary)
            .frame(width: 24, height: 24)
            .background {
                if hovering, isEnabled {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .keyboardShortcut("t", modifiers: .command)
            .onHover { hovering = $0 }
            .opacity(isEnabled ? 1 : 0.35)
            .help("New tab (⌘T)")
    }
}

private struct MacConversationView<TabBar: View>: View {
    let model: AppModel
    @Bindable var window: MacWindowState
    let sessionID: String
    let rootID: String
    let isAwake: Bool
    let tabsInToolbar: Bool
    @ViewBuilder let tabBar: TabBar
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
    @State private var recentModels: [DefaultModel] = []
    @State private var loadingRecentModels = false
    @State private var showsRunConfig = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    private var recentModelsLoadID: String? {
        guard showsRunConfig, isAwake, scenePhase == .active,
              model.defaultModels(sessionID: rootID).isEmpty,
              model.sessionSummary(sessionID)?.agentConfigID != nil else { return nil }
        return "\(model.workspaceGeneration):\(sessionID)"
    }

    private struct ObservationKey: Equatable {
        let awake: Bool
        let starting: Bool
    }

    var body: some View {
        let generation = model.workspaceGeneration
        let outgoing = model.outgoingMessage(sessionID: sessionID)
        let turns = model.displayedTurns(conversation?.turns ?? [], sessionID: sessionID)
        let isRunning = (activity ?? model.sessionSummary(sessionID)?.activity) == .running
        let session = model.sessionSummary(sessionID)
        let menu = window[draft: sessionID].runConfig.displayed?.shortcutMenu(
            saved: model.defaultModels(sessionID: rootID), recent: recentModels,
            agentConfigID: session?.agentConfigID, agentName: session?.agentName ?? "Agent")
        VStack(spacing: 0) {
            // Inside the inspector so the tabs center on the transcript column. Kept out of
            // the scroll view's safe area so bottom-follow geometry is unchanged.
            tabBar
            if !connection.isEmpty {
                Text(connection).font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            MacTranscript(model: model, sessionID: sessionID, turns: turns,
                          atBottom: $atBottom, scrollRequest: scrollRequest, isAwake: isAwake,
                          tabsInToolbar: tabsInToolbar)
                .overlay(alignment: .top) {
                    let fill = MacChrome.main(colorScheme)
                    LinearGradient(colors: [fill, fill.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .allowsHitTesting(false)
                }
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
            // The transcript column is 800pt with its 24pt gutter outside that cap.
            // Keep the same order here so the composer card lines up with the text.
            MacComposer(draft: $window[draft: sessionID], runConfig: menu, showsRunConfig: $showsRunConfig,
                        isLoadingModels: loadingRecentModels,
                        canSend: isAwake && model.supportsTextSending && outgoing == nil
                            && (!isRunning || model.supportsTextSendingWhileRunning),
                        isRunning: isRunning, canStop: model.supportsSessionCancellation && !cancelling,
                        onSend: send, onStop: stop, onChoose: chooseRunConfig)
            .frame(maxWidth: 800)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
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
        .task(id: recentModelsLoadID) {
            recentModels = []
            guard recentModelsLoadID != nil else {
                loadingRecentModels = false
                return
            }
            loadingRecentModels = true
            defer { loadingRecentModels = false }
            do {
                let loaded = try await model.recentModels(
                    sessionID: sessionID, agentConfigID: model.sessionSummary(sessionID)?.agentConfigID)
                try Task.checkCancellation()
                recentModels = loaded
            } catch is CancellationError {
                return
            } catch {
                // The current model stays visible when recent models cannot be loaded.
            }
        }
    }

    private func chooseRunConfig(_ value: String) {
        window[draft: sessionID].runConfig.choose(value)
        guard let config = window[draft: sessionID].runConfig.displayed,
              let editable = config.editable, editable.kind == .reasoning,
              editable.options.contains(where: { $0.value == value }),
              let optionID = editable.configOptionID, let modelID = config.model?.value,
              let agentConfigID = model.sessionSummary(sessionID)?.agentConfigID else { return }
        model.rememberDefaultModelReasoning(
            agentConfigID: agentConfigID, modelID: modelID,
            reasoning: .init(configOptionID: optionID, value: value),
            sessionID: rootID, workspaceGeneration: model.workspaceGeneration)
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
