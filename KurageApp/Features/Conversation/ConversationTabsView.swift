import SwiftUI

struct ConversationDraft {
    var text = ""
    var mentions = ComposerMentionState()
    var attachments: [ComposerAttachment] = []
    var isCancelling = false
    var banner: String?
    var runConfig = ConversationRunConfigState()
}

/// Transient drafts outlive the detail column, but never cross a workspace generation.
@MainActor @Observable
final class ConversationDraftStore {
    private struct Key: Hashable {
        let rootID: String
        let workspaceGeneration: Int
    }

    private var values: [Key: [String: ConversationDraft]] = [:]

    subscript(rootID rootID: String, sessionID sessionID: String, workspaceGeneration workspaceGeneration: Int) -> ConversationDraft {
        get { values[Key(rootID: rootID, workspaceGeneration: workspaceGeneration)]?[sessionID] ?? ConversationDraft() }
        set { values[Key(rootID: rootID, workspaceGeneration: workspaceGeneration), default: [:]][sessionID] = newValue }
    }

    func removeRoots(_ rootIDs: Set<String>, workspaceGeneration: Int) {
        guard !rootIDs.isEmpty else { return }
        values = values.filter { key, _ in
            key.workspaceGeneration != workspaceGeneration || !rootIDs.contains(key.rootID)
        }
    }
}

struct ConversationTabsContent: View {
    let rootID: String
    let title: String
    let model: AppModel
    let workspaceGeneration: Int
    let isReadOnly: Bool
    var isReading = true
    var draftStore: ConversationDraftStore? = nil
    var onArchived: (() -> Void)? = nil
    var onEditSessionStart: ((OutgoingMessage) -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var localDrafts = ConversationDraftStore()
    @State private var showsNewTab = false
    @State private var restoredTabMessage: OutgoingMessage?
    @State private var errorMessage: String?
    @State private var changingTab = false

    private var activeID: String { model.activeSessionTab(rootID: rootID) }
    private var tabs: [SessionSummary] { model.sessionTabs(rootID: rootID) }
    private var openTabs: [SessionSummary] { tabs.filter { $0.id == rootID || $0.isTabClosed != true } }
    private var closedTabs: [SessionSummary] { tabs.filter { $0.id != rootID && $0.isTabClosed == true } }
    private var draft: Binding<ConversationDraft> {
        @Bindable var store = draftStore ?? localDrafts
        return $store[rootID: rootID, sessionID: activeID, workspaceGeneration: workspaceGeneration]
    }

    var body: some View {
        Group {
            if showsNewTab {
                NewSessionView(route: NewSessionRoute(
                    projectID: model.sessionSummary(rootID)?.projectID ?? "",
                    projectName: model.sessionSummary(rootID)?.projectName ?? "Shared working directory",
                    templateSessionID: rootID, workspaceGeneration: workspaceGeneration, parentSessionID: rootID
                ), model: model, restoredMessage: restoredTabMessage, isReading: isReading, onStaged: { id in
                    guard let id else { return }
                    model.setActiveSessionTab(id, rootID: rootID)
                    showsNewTab = false
                    restoredTabMessage = nil
                })
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") { showsNewTab = false }
                            .accessibilityIdentifier("cancel-new-session-tab")
                    }
                }
            } else {
                ConversationContent(sessionID: activeID, title: model.sessionSummary(activeID)?.title ?? title,
                    model: model, workspaceGeneration: workspaceGeneration, isReadOnly: isReadOnly, isReading: isReading,
                    draft: draft.text, mentions: draft.mentions, attachments: draft.attachments,
                    isCancelling: draft.isCancelling, banner: draft.banner,
                    runConfigState: draft.runConfig,
                    rootSessionID: rootID, onArchived: onArchived,
                    onNewTab: !isReadOnly && model.supportsSessionTabs ? {
                        restoredTabMessage = nil
                        showsNewTab = true
                    } : nil,
                    closedTabs: closedTabs, onReopenTab: { setClosed(false, tab: $0) },
                    onEditSessionStart: { message in
                        if activeID == rootID {
                            onEditSessionStart?(message)
                        } else {
                            restoredTabMessage = message
                            showsNewTab = true
                        }
                    })
                    .id(activeID)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !showsNewTab, !isReadOnly, model.supportsSessionTabs, openTabs.count > 1 {
                SessionTabBar(rootID: rootID, activeID: activeID, openTabs: openTabs,
                              select: { model.setActiveSessionTab($0, rootID: rootID) },
                              setClosed: setClosed)
                    .frame(maxWidth: ConversationMetrics.maximumContentWidth)
                    .frame(maxWidth: .infinity)
                    .disabled(changingTab || scenePhase != .active)
            }
        }
        .alert("Could not update tab", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .onChange(of: openTabs.map(\.id)) { _, ids in
            if activeID != rootID, !ids.contains(activeID) { model.setActiveSessionTab(rootID, rootID: rootID) }
        }
        .onChange(of: model.notificationOpenGeneration) { _, _ in
            showsNewTab = false
            restoredTabMessage = nil
        }
    }

    private func setClosed(_ closed: Bool, tab: SessionSummary) {
        guard model.workspaceGeneration == workspaceGeneration, !changingTab,
              !model.isSessionStartPending(sessionID: tab.id) else { return }
        changingTab = true
        Task { @MainActor in
            defer { changingTab = false }
            do {
                try await model.updateSessionMetadata(.tabClosed(closed), sessionID: tab.id)
                guard model.workspaceGeneration == workspaceGeneration else { return }
                if closed, activeID == tab.id { model.setActiveSessionTab(rootID, rootID: rootID) }
                if !closed { model.setActiveSessionTab(tab.id, rootID: rootID) }
            } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct SessionTabBar: View {
    let rootID: String
    let activeID: String
    let openTabs: [SessionSummary]
    let select: (String) -> Void
    let setClosed: (Bool, SessionSummary) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(openTabs) { tab in
                        Button {
                            select(tab.id)
                        } label: {
                            Text(tab.id == rootID ? "Main" : tab.title)
                                .lineLimit(1)
                                .frame(maxWidth: 180)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(activeID == tab.id ? Color.primary : Color.secondary)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(activeID == tab.id ? Color(uiColor: .secondarySystemBackground) : .clear,
                                            in: .capsule)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.id == rootID ? "Main tab" : tab.title)
                        .accessibilityValue(tab.activity == .running ? "Running" : tab.isUnread ? "Unread" : "Read")
                        .accessibilityAddTraits(activeID == tab.id ? .isSelected : [])
                        .accessibilityIdentifier("session-tab-\(tab.id)")
                        .id(tab.id)
                        .contextMenu {
                            if tab.id != rootID {
                                Button("Close tab", systemImage: "xmark") { setClosed(true, tab) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            // Entering on a restored tab must show it: the active pill can
            // sit outside the initial viewport once a session has many tabs.
            .onAppear { proxy.scrollTo(activeID, anchor: .center) }
            .onChange(of: activeID) { _, id in proxy.scrollTo(id, anchor: .center) }
        }
        .accessibilityIdentifier("session-tab-bar")
    }
}
