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
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(tabs) { tab in
                        Button(tab.id == root.id ? "Main" : tab.title) { window.selectTab(tab.id, rootID: root.id) }
                            .buttonStyle(.bordered)
                            .tint(tab.id == sessionID ? .accentColor : .secondary)
                            .accessibilityIdentifier("tab-\(tab.id)")
                    }
                    Button("New tab", systemImage: "plus") {
                        window.newSession = NewSessionDestination(template: root, isTab: true)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!model.supportsSessionTabs || model.pendingSessionTab(rootID: root.id) != nil)
                    .accessibilityIdentifier("new-tab")
                }.padding(12)
            }
            Divider()
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

private struct MacConversationView: View {
    let model: AppModel
    @Bindable var window: MacWindowState
    let sessionID: String
    let rootID: String
    let isAwake: Bool
    @State private var conversation: Conversation?
    @State private var runConfig: SessionRunConfig?
    @State private var activity: SessionActivity?
    @State private var connection = "Connecting…"
    @State private var error: String?
    @State private var cancelling = false
    @State private var atBottom = true
    @State private var latestMessageAt: Double?
    @State private var scrollRequest = 0
    @Environment(\.scenePhase) private var scenePhase

    private struct ObservationKey: Equatable {
        let awake: Bool
        let starting: Bool
    }

    var body: some View {
        let outgoing = model.outgoingMessage(sessionID: sessionID)
        let turns = model.displayedTurns(conversation?.turns ?? [], sessionID: sessionID)
        let isRunning = (activity ?? model.sessionSummary(sessionID)?.activity) == .running
        let config = runConfig?.applying(window[draft: sessionID].choice)
        VStack(spacing: 0) {
            if !connection.isEmpty {
                Text(connection).font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            MacTranscript(model: model, sessionID: sessionID, turns: turns,
                          atBottom: $atBottom, scrollRequest: scrollRequest, isAwake: isAwake)
            if let outgoing, outgoing.delivery != .sending, outgoing.delivery != .sent {
                HStack {
                    Text(deliveryDescription(outgoing.delivery)).foregroundStyle(.secondary)
                    if outgoing.canRetry {
                        Button("Retry") {
                            if model.retryOutgoingMessage(sessionID: sessionID) { deliver() }
                        }
                    }
                }.font(.caption).padding(8)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption).padding(8) }
            Divider()
            MacComposer(draft: $window[draft: sessionID], runConfig: config,
                        canSend: isAwake && model.supportsTextSending && outgoing == nil
                            && (!isRunning || model.supportsTextSendingWhileRunning),
                        isRunning: isRunning, canStop: model.supportsSessionCancellation && !cancelling,
                        onSend: send, onStop: stop) { value in
                window[draft: sessionID].choice = runConfig?.choosing(value)
            }
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
            model.restoreOutgoingMessage(sessionID: sessionID)
            conversation = model.cachedConversation(sessionID: sessionID)
            var delay = 1
            while !Task.isCancelled {
                do {
                    try await model.observeConversation(sessionID: sessionID, rootSessionID: rootID) { update in
                        conversation = update.conversation
                        activity = update.activity
                        runConfig = update.runConfig
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
            try? await model.markSessionRead(sessionID: sessionID, lastMessageAt: latestMessageAt,
                                            workspaceGeneration: model.workspaceGeneration)
        }
    }

    private func send() {
        let draft = window[draft: sessionID]
        do {
            try model.stageOutgoingMessage(draft.text, composerText: draft.text, mentions: .init(),
                attachments: draft.attachments, runConfig: draft.choice, sessionID: sessionID)
            window[draft: sessionID].text = ""
            window[draft: sessionID].attachments = []
            error = nil
            scrollRequest += 1
            deliver()
        } catch { self.error = "Could not prepare the message. Resolve the previous send and try again." }
    }

    private func deliver() {
        let workspaceID = model.selectedWorkspaceID
        let turnID = model.outgoingMessage(sessionID: sessionID)?.id
        // Transmission outlives navigation. The shared outbox owns its result and retry identity.
        Task {
            do { try await model.deliverOutgoingMessage(sessionID: sessionID, workspaceID: workspaceID, turnID: turnID) }
            catch { /* The shared outbox exposes delivery failure and same-ID retry. */ }
        }
    }

    private func stop() {
        cancelling = true
        Task {
            defer { cancelling = false }
            do { try await model.cancelSession(sessionID: sessionID) }
            catch { self.error = "Could not stop the session. Try again." }
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
