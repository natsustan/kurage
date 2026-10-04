import SwiftUI

struct NewSessionRoute: Hashable {
    let id = UUID()
    let projectID: String
    let projectName: String
    /// The project's most recent session; the new session reuses its machine and, by default, its agent.
    let templateSessionID: SessionSummary.ID
    let workspaceGeneration: Int
    var parentSessionID: String? = nil
}

extension NewSessionOptions {
    /// Provider, model and reasoning for the first turn, in the composer's run-config menu.
    func menu(_ runConfig: NewSessionRunConfig?) -> RunConfigMenu {
        var sections: [RunConfigMenu.Section] = []
        if providers.count > 1 {
            sections.append(.init(kind: .provider, options: providers, selection: agentConfigID))
        }
        if let model = runConfig?.model {
            sections.append(.init(
                kind: .model,
                options: model.options.map { SessionRunConfig.Value(value: $0.value, label: $0.label) },
                selection: model.value
            ))
        }
        if let runConfig, !runConfig.reasoningOptions.isEmpty {
            sections.append(.init(kind: .reasoning, options: runConfig.reasoningOptions,
                                  selection: runConfig.selectedReasoning?.value ?? ""))
        }
        let provider = provider?.label
        let model = runConfig?.selectedModel?.label
        let reasoning = runConfig?.selectedReasoning?.label
        return RunConfigMenu(
            modelLabel: model, reasoningLabel: reasoning, providerLabel: provider,
            accessibilitySummary: [provider.map { "Provider \($0)" }, model.map { "model \($0)" },
                                   reasoning.map { "reasoning \($0)" }]
                .compactMap { $0 }.joined(separator: ", "),
            sections: sections
        )
    }
}

/// Starts a session in a local project from its first message.
struct NewSessionView: View {
    let route: NewSessionRoute
    let model: AppModel
    let isReading: Bool
    var draftStore: ConversationDraftStore? = nil
    var onArchived: (() -> Void)? = nil
    var onStaged: ((SessionSummary.ID?) -> Void)? = nil

    @State private var selectedProject: SessionProject?
    private var projectID: String { selectedProject?.id ?? route.projectID }
    private var projectName: String { selectedProject?.name ?? route.projectName }
    private var templateSessionID: String { selectedProject?.templateSessionID ?? route.templateSessionID }

    private struct LoadRequest: Equatable {
        var agentConfigID: String?
        var attempt = 0
    }

    @State private var configuration = NewSessionConfiguration()
    @State private var request = LoadRequest()
    @State private var draft = ""
    @State private var mentions = ComposerMentionState()
    @State private var attachments: [ComposerAttachment] = []
    @State private var startedSessionID: SessionSummary.ID?
    @State private var banner: String?
    @Environment(\.scenePhase) private var scenePhase

    init(route: NewSessionRoute, model: AppModel, restoredMessage: OutgoingMessage? = nil, isReading: Bool = true,
         draftStore: ConversationDraftStore? = nil, onArchived: (() -> Void)? = nil,
         onStaged: ((SessionSummary.ID?) -> Void)? = nil) {
        self.route = route
        self.model = model
        self.isReading = isReading
        self.draftStore = draftStore
        self.onArchived = onArchived
        self.onStaged = onStaged
        _draft = State(initialValue: restoredMessage?.composerText ?? "")
        _mentions = State(initialValue: restoredMessage?.mentions ?? .init())
        _attachments = State(initialValue: restoredMessage?.attachments ?? [])
    }

    private var isStarting: Bool { startedSessionID != nil }

    private var pendingStart: PendingSessionStart? {
        guard isCurrentWorkspace else { return nil }
        if let rootID = route.parentSessionID {
            return model.pendingSessionTab(rootID: rootID).map {
                PendingSessionStart(id: $0.sessionID, projectID: projectID, templateSessionID: rootID,
                                    text: $0.text, attachments: $0.attachments, turnID: $0.turnID)
            }
        }
        return model.pendingSessionStarts.first { $0.projectID == projectID }
    }

    private var options: NewSessionOptions? { configuration.options }
    private var runConfig: NewSessionRunConfig? { configuration.runConfig }
    private var isLoading: Bool { configuration.isLoading }
    private var loadFailed: Bool { configuration.loadFailed }

    private var isCurrentWorkspace: Bool { model.workspaceGeneration == route.workspaceGeneration }

    private var machineName: String? {
        guard isCurrentWorkspace else { return nil }
        return options?.machineName ?? model.sessionSummary(templateSessionID)?.machineName
    }

    var body: some View {
        Group {
            if let startedSessionID, isCurrentWorkspace {
                // Keep this navigation destination alive through confirmation.
                // Its local first turn and the synchronized turn share an ID.
                ConversationTabsContent(rootID: startedSessionID, title: model.sessionSummary(startedSessionID)?.title ?? "Session",
                    model: model, workspaceGeneration: route.workspaceGeneration, isReadOnly: false,
                    isReading: isReading,
                    draftStore: draftStore, onArchived: onArchived,
                    onEditSessionStart: restoreDraft)
            } else {
                composition
            }
        }
    }

    private var composition: some View {
        // Short details sit just above the composer; large text scrolls instead of
        // pushing the composer under the keyboard.
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                details
                if let banner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if pendingStart == nil {
                SessionComposer(
                    draft: $draft, mentions: $mentions, attachments: $attachments,
                    isSending: isStarting, isCancelling: false, isSessionRunning: false,
                    supportsTextSending: true, supportsTextSendingWhileRunning: false,
                    supportsSessionCancellation: false,
                    runConfig: configuration.menu,
                    placeholder: "Build anything",
                    identifiers: .init(container: "new-session-composer", field: "new-session-field",
                                       send: "new-session-send"),
                    canSubmit: isCurrentWorkspace && scenePhase == .active && pendingStart == nil && options != nil && !isLoading && !loadFailed,
                    focusesOnAppear: true,
                    mentionSourceID: "\(route.workspaceGeneration):\(projectID):\(templateSessionID):\(options?.agentConfigID ?? "")",
                    loadMentionSessions: { try await model.mentionSessions(projectID: projectID) },
                    loadMentionSkills: {
                        try await model.mentionSkills(templateSessionID: templateSessionID,
                                                      agentConfigID: options?.agentConfigID,
                                                      projectID: route.parentSessionID == nil ? projectID : nil)
                    },
                    onSend: start, onCancel: {}, onChooseRunConfig: choose
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: ConversationMetrics.maximumContentWidth)
        .frame(maxWidth: .infinity)
        .navigationTitle(route.parentSessionID == nil ? "New Session" : "New Tab")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request) { await load() }
        .onAppear { resumePendingStart() }
        .onDisappear {
            configuration.cancelLoads()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { request.attempt += 1 }
            else { configuration.cancelLoads() }
        }
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Rows already provide a 44pt height; keep their touch targets adjacent.
            VStack(alignment: .leading, spacing: 0) {
                if let machineName {
                    detailRow(machineName, imageName: "laptop")
                        .accessibilityIdentifier("new-session-machine")
                }
                if route.parentSessionID == nil {
                    SessionProjectMenu(
                        model: model,
                        current: SessionProject(id: projectID, name: projectName,
                                                rootPath: selectedProject?.rootPath ?? "",
                                                templateSessionID: templateSessionID),
                        workspaceGeneration: route.workspaceGeneration,
                        onChoose: selectProject
                    )
                    .disabled(isStarting || pendingStart != nil || !isCurrentWorkspace)
                    if model.supportsProjectGitReading {
                        ProjectBranchRow(model: model, projectID: projectID, templateSessionID: templateSessionID,
                                         workspaceGeneration: route.workspaceGeneration,
                                         isDisabled: isStarting || pendingStart != nil)
                            .id(projectID)
                    }
                } else {
                    detailRow(projectName, imageName: "folder-open")
                        .accessibilityIdentifier("inherited-tab-project")
                }
            }
            if let pendingStart {
                Text(pendingStart.displayText)
                    .lineLimit(4)
                    .foregroundStyle(.primary)
                Button("Retry earlier start", systemImage: "arrow.clockwise") {
                    resumePendingStart(retry: true)
                }
                .disabled(!isCurrentWorkspace || isStarting)
                .accessibilityIdentifier("new-session-retry-start")
            }
            if isLoading {
                ProgressView()
                    .accessibilityLabel("Loading agent")
            } else if loadFailed {
                Button("Could not load the agent. Retry", systemImage: "arrow.clockwise") {
                    request.attempt += 1
                }
                .font(.subheadline)
                .accessibilityIdentifier("new-session-retry")
            }
        }
        .foregroundStyle(.secondary)
    }

    private func detailRow(_ title: String, imageName: String) -> some View {
        Label {
            Text(title).lineLimit(1)
        } icon: {
            NewSessionIcon(imageName: imageName)
        }
        .font(.body)
        .frame(minHeight: 44)
    }

    private func selectProject(_ project: SessionProject) {
        guard isCurrentWorkspace, !isStarting else { return }
        configuration.cancelLoads()
        selectedProject = project
        configuration = NewSessionConfiguration()
        request = LoadRequest(attempt: request.attempt + 1)
        // The draft is preserved, so its mentions must be too: clearing them
        // here sent `$skill` as plain words. The composer reloads this project's
        // skills and re-points or drops the mentions it can no longer resolve.
        banner = nil
    }

    private func load() async {
        guard isCurrentWorkspace, !isStarting, pendingStart == nil else { return }
        await configuration.load(providerID: request.agentConfigID,
                                 refresh: { try await fetchOptions(providerID: $0, refresh: true) },
                                 using: { try await fetchOptions(providerID: $0, refresh: false) })
    }

    private func fetchOptions(providerID: String?, refresh: Bool) async throws -> NewSessionOptions {
        guard isCurrentWorkspace else { throw CancellationError() }
        let loaded = try await model.newSessionOptions(
            templateSessionID: route.parentSessionID ?? templateSessionID, agentConfigID: providerID,
            projectID: route.parentSessionID == nil ? projectID : nil,
            isTab: route.parentSessionID != nil, refresh: refresh
        )
        guard isCurrentWorkspace else { throw CancellationError() }
        return loaded
    }

    private func choose(_ kind: RunConfigMenu.Section.Kind, _ value: String) {
        guard isCurrentWorkspace, !isStarting else { return }
        switch kind {
        case .provider:
            guard configuration.selectProvider(value) else { return }
            request = LoadRequest(agentConfigID: value, attempt: request.attempt + 1)
        case .model:
            configuration.selectModel(value)
        case .reasoning:
            configuration.selectReasoning(value)
        }
    }

    private func start() -> Bool {
        guard isCurrentWorkspace, scenePhase == .active, pendingStart == nil, let options, !isLoading, !loadFailed, !isStarting,
              (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) else { return false }
        do {
            let id = try model.stageSessionStart(mentions.expanded(draft), composerText: draft, mentions: mentions,
                attachments: attachments, agentConfigID: options.agentConfigID.isEmpty ? nil : options.agentConfigID,
                selections: runConfig?.selections ?? [], projectID: projectID, projectName: projectName,
                templateSessionID: route.parentSessionID ?? templateSessionID, parentSessionID: route.parentSessionID)
            draft = ""
            mentions.clear()
            attachments = []
            showConversation(id)
            deliverStart(id)
            return true
        } catch {
            banner = "Could not prepare the new session. Try again."
            return false
        }
    }

    private func showConversation(_ id: String) {
        configuration.cancelLoads()
        startedSessionID = id
        banner = nil
        onStaged?(id)
    }

    private func resumePendingStart(retry: Bool = false) {
        guard isCurrentWorkspace, !isStarting, let pendingStart else { return }
        do {
            let id = try model.restoreSessionStart(pendingStart, projectName: projectName, parentSessionID: route.parentSessionID)
            showConversation(id)
            if retry, model.retryOutgoingMessage(sessionID: id) { deliverStart(id) }
        } catch {
            banner = "Could not reopen the earlier start. Try again."
        }
    }

    private func deliverStart(_ id: String) {
        let workspaceID = model.selectedWorkspaceID
        let turnID = model.outgoingMessage(sessionID: id)?.id
        // Delivery belongs to the model's outbox and survives leaving this page.
        Task { try? await model.deliverOutgoingMessage(sessionID: id, workspaceID: workspaceID, turnID: turnID) }
    }

    private func restoreDraft(_ message: OutgoingMessage) {
        guard isCurrentWorkspace else { return }
        startedSessionID = nil
        draft = message.composerText
        mentions = message.mentions
        attachments = message.attachments
        configuration = NewSessionConfiguration()
        request = LoadRequest(attempt: request.attempt + 1)
        banner = nil
        onStaged?(nil)
    }
}

/// Keeps the detail titles aligned across asset images of different widths.
struct NewSessionIcon: View {
    let imageName: String
    @ScaledMetric(relativeTo: .body) private var width = 28
    @ScaledMetric(relativeTo: .body) private var iconSize = 20

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .frame(width: width)
    }
}


/// Page-scoped options and selections. Prefetching never changes the active
/// provider, and cancelled/older requests cannot overwrite a newer selection.
@MainActor @Observable
final class NewSessionConfiguration {
    private(set) var options: NewSessionOptions?
    private(set) var runConfig: NewSessionRunConfig?
    private(set) var isLoading = true
    private(set) var loadFailed = false
    @ObservationIgnored private var cached: [String: NewSessionOptions] = [:]
    @ObservationIgnored private var selections: [String: NewSessionRunConfig] = [:]
    @ObservationIgnored private var generation = 0
    private struct PendingLoad {
        let id = UUID()
        let task: Task<NewSessionOptions, Error>
    }
    @ObservationIgnored private var inFlight: [String: PendingLoad] = [:]

    var menu: RunConfigMenu? {
        guard let options else { return nil }
        var menu = options.menu(runConfig)
        menu.isLoading = isLoading
        menu.loadFailed = loadFailed
        return menu
    }

    @discardableResult
    func selectProvider(_ id: String) -> Bool {
        guard let current = options, current.providers.contains(where: { $0.value == id }),
              id != current.agentConfigID || loadFailed else { return false }
        if let runConfig, !isLoading, !loadFailed { selections[current.agentConfigID] = runConfig }
        generation += 1
        loadFailed = false
        if let cached = cached[id] {
            activate(cached)
        } else {
            // Reflect the new provider immediately, without exposing the old
            // provider's model/reasoning while its options load.
            options = NewSessionOptions(machineName: current.machineName, agentConfigID: id,
                                        providers: current.providers, runConfig: nil)
            runConfig = nil
            isLoading = true
        }
        return true
    }

    func selectModel(_ value: String) {
        guard !isLoading, !loadFailed else { return }
        runConfig?.selectModel(value)
        rememberSelection()
    }

    func selectReasoning(_ value: String) {
        guard !isLoading, !loadFailed else { return }
        runConfig?.selectReasoning(value)
        rememberSelection()
    }

    private func rememberSelection() {
        if let id = options?.agentConfigID, let runConfig { selections[id] = runConfig }
    }

    func load(providerID: String?,
              refresh: (@MainActor (String?) async throws -> NewSessionOptions)? = nil,
              using fetch: @escaping @MainActor (String?) async throws -> NewSessionOptions) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let request = generation
        loadFailed = false
        if let providerID, let existing = cached[providerID] {
            activate(existing)
        } else {
            isLoading = true
            do {
                let loaded = try await fetchOptions(providerID, using: fetch)
                try Task.checkCancellation()
                guard request == generation else { return }
                cached[loaded.agentConfigID] = loaded
                activate(loaded)
            } catch is CancellationError {
                return
            } catch {
                guard request == generation, !Task.isCancelled else { return }
                isLoading = false
                loadFailed = true
                return
            }
        }
        // A stale snapshot remains usable while refreshing. Explicit edits are
        // stored in selections and survive activation of the fresh capabilities.
        if let activeID = options?.agentConfigID, options?.needsRefresh == true, let refresh {
            await refreshOptions(activeID, request: request, using: refresh)
            guard request == generation, !Task.isCancelled else { return }
        }
        // Resolve other providers during the time spent composing. Their most
        // recent run configuration still comes from the service, not a guess.
        let providers = options?.providers ?? []
        for provider in providers where cached[provider.value] == nil {
            guard request == generation, !Task.isCancelled else { return }
            do {
                let loaded = try await fetchOptions(provider.value, using: fetch)
                try Task.checkCancellation()
                guard request == generation else { return }
                cached[loaded.agentConfigID] = loaded
                if loaded.needsRefresh == true, let refresh {
                    await refreshOptions(loaded.agentConfigID, request: request, using: refresh)
                }
            } catch {
                // A failed prefetch is retried only if this provider is chosen.
                if Task.isCancelled || request != generation { return }
            }
        }
    }

    private func refreshOptions(_ id: String, request: Int,
                                using refresh: @escaping @MainActor (String?) async throws -> NewSessionOptions) async {
        do {
            let loaded = try await fetchOptions(id, refreshing: true, using: refresh)
            try Task.checkCancellation()
            guard request == generation else { return }
            cached[loaded.agentConfigID] = loaded
            if options?.agentConfigID == loaded.agentConfigID { activate(loaded) }
        } catch {
            // Keep the snapshot on a transient failure; a later load retries it.
            // Creation always validates again on an independent writing replica.
        }
    }

    func cancelLoads() {
        generation += 1
        for pending in inFlight.values { pending.task.cancel() }
        inFlight.removeAll()
    }

    private func fetchOptions(
        _ providerID: String?,
        refreshing: Bool = false,
        using fetch: @escaping @MainActor (String?) async throws -> NewSessionOptions
    ) async throws -> NewSessionOptions {
        let key = "\(refreshing):\(providerID ?? "")"
        let pending: PendingLoad
        if let existing = inFlight[key] {
            pending = existing
        } else {
            pending = PendingLoad(task: Task {
                let loaded = try await fetch(providerID)
                try Task.checkCancellation()
                return loaded
            })
            inFlight[key] = pending
        }
        defer {
            if inFlight[key]?.id == pending.id { inFlight.removeValue(forKey: key) }
        }
        return try await pending.task.value
    }

    private func activate(_ loaded: NewSessionOptions) {
        options = loaded
        var current = loaded.runConfig
        if let selected = selections[loaded.agentConfigID] {
            if let value = selected.model?.value { current?.selectModel(value) }
            if let value = selected.reasoning?.value { current?.selectReasoning(value) }
            selections[loaded.agentConfigID] = current
        }
        runConfig = current
        isLoading = false
        loadFailed = false
    }
}
