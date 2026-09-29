import SwiftUI

private struct TabDraft {
    var text = ""
    var mentions = ComposerMentionState()
    var attachments: [ComposerAttachment] = []
    var runConfig = ConversationRunConfigState()
}

struct ConversationTabsContent: View {
    let rootID: String
    let title: String
    let model: AppModel
    let workspaceGeneration: Int
    let isReadOnly: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?
    @State private var drafts: [String: TabDraft] = [:]
    @State private var showsNewTab = false
    @State private var errorMessage: String?
    @State private var changingTab = false

    private var activeID: String { selectedID ?? rootID }
    private var tabs: [SessionSummary] { model.sessionTabs(rootID: rootID) }
    private var openTabs: [SessionSummary] { tabs.filter { $0.id == rootID || $0.isTabClosed != true } }
    private var closedTabs: [SessionSummary] { tabs.filter { $0.id != rootID && $0.isTabClosed == true } }
    private var draft: Binding<TabDraft> {
        let id = activeID
        return Binding(get: { drafts[id] ?? TabDraft() }, set: { drafts[id] = $0 })
    }

    var body: some View {
        ConversationContent(sessionID: activeID, title: model.sessionSummary(activeID)?.title ?? title,
                            model: model, workspaceGeneration: workspaceGeneration, isReadOnly: isReadOnly, isReading: !showsNewTab,
                            draft: draft.text, mentions: draft.mentions, attachments: draft.attachments,
                            runConfigState: draft.runConfig,
                            onNewTab: !isReadOnly && model.supportsSessionTabs ? { showsNewTab = true } : nil,
                            closedTabs: closedTabs, onReopenTab: { setClosed(false, tab: $0) })
            .id(activeID)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !isReadOnly, model.supportsSessionTabs, openTabs.count > 1 {
                    SessionTabBar(rootID: rootID, activeID: activeID, openTabs: openTabs,
                                  select: { selectedID = $0 },
                                  setClosed: setClosed)
                        .disabled(changingTab || scenePhase != .active)
                }
            }
            .navigationDestination(isPresented: $showsNewTab) {
                NewSessionView(route: NewSessionRoute(
                    projectID: model.sessionSummary(rootID)?.projectID ?? "",
                    projectName: model.sessionSummary(rootID)?.projectName ?? "Shared working directory",
                    templateSessionID: rootID, workspaceGeneration: workspaceGeneration, parentSessionID: rootID
                ), model: model) { id in
                    selectedID = id
                    showsNewTab = false
                }
            }
            .alert("Could not update tab", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
            .onChange(of: openTabs.map(\.id)) { _, ids in
                if activeID != rootID, !ids.contains(activeID) { selectedID = nil }
            }
    }

    private func setClosed(_ closed: Bool, tab: SessionSummary) {
        guard model.workspaceGeneration == workspaceGeneration, !changingTab else { return }
        changingTab = true
        Task { @MainActor in
            defer { changingTab = false }
            do {
                try await model.updateSessionMetadata(.tabClosed(closed), sessionID: tab.id)
                guard model.workspaceGeneration == workspaceGeneration else { return }
                if closed, activeID == tab.id { selectedID = nil }
                if !closed { selectedID = tab.id }
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
        GlassEffectContainer(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(openTabs) { tab in
                            Button {
                                select(tab.id)
                            } label: {
                                HStack(spacing: 6) {
                                    if tab.activity == .running {
                                        ProgressView().controlSize(.mini)
                                    } else if tab.isUnread {
                                        Circle().fill(.blue).frame(width: 6, height: 6)
                                    }
                                    Text(tab.id == rootID ? "Main" : tab.title)
                                        .lineLimit(1)
                                        .frame(maxWidth: 180)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .glassEffect(.regular.tint(activeID == tab.id ? Color.accentColor.opacity(0.18) : .clear)
                                    .interactive(), in: .capsule)
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
                .onChange(of: activeID) { _, id in proxy.scrollTo(id, anchor: .center) }
            }
        }
        .accessibilityIdentifier("session-tab-bar")
    }
}

