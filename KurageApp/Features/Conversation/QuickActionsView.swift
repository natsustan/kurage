import SwiftUI

struct QuickActionConfigurationState {
    var options: NewSessionOptions?
    var runConfig: NewSessionRunConfig?
    var isLoading = true
    var error: String?
    var preferenceIssue: String?

    var isReady: Bool { options != nil && !isLoading && error == nil && preferenceIssue == nil }

    @MainActor
    static func load(model: AppModel, rootID: String, agentConfigID: String? = nil) async throws -> Self {
        let preference = model.quickActionPreference(rootID: rootID)
        let agentID = agentConfigID ?? preference?.agentConfigID
        var options = try await model.newSessionOptions(templateSessionID: rootID, agentConfigID: agentID, isTab: true)
        if options.needsRefresh == true {
            options = try await model.newSessionOptions(templateSessionID: rootID, agentConfigID: agentID,
                                                        isTab: true, refresh: true)
        }
        try Task.checkCancellation()
        var config = options.runConfig
        var issue: String?
        if preference?.agentConfigID == options.agentConfigID {
            do { try preference?.apply(to: &config) } catch { issue = error.localizedDescription }
        }
        return Self(options: options, runConfig: config, isLoading: false, preferenceIssue: issue)
    }
}

struct QuickActionsMenu: View {
    let rootID: String
    let workspaceGeneration: Int
    let model: AppModel
    @Binding var isPreparing: Bool
    let onStarted: (String) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var request: Request?
    @State private var failedAction: QuickAction?
    @State private var errorMessage: String?
    @State private var canResetPreference = false
    @State private var availability: QuickActionAvailability?
    @State private var gitError: String?
    @State private var isLoadingGit = true
    @State private var refreshAttempt = 0
    @State private var loadToken = UUID()

    private struct Request: Identifiable {
        let id = UUID()
        let action: QuickAction
        let projectID: String
    }

    private var failure: QuickActionFailure? { model.quickActionBlockingFailure(rootID: rootID) }

    private struct GitLoadID: Equatable {
        let rootID: String
        let projectID: String?
        let generation: Int
        let isActive: Bool
        let failure: QuickActionFailure?
        let lastActivityAt: Double?
        let attempt: Int
    }

    var body: some View {
        Menu {
            if let failure {
                Button("Why are actions unavailable?", systemImage: "info.circle") {
                    failedAction = nil
                    canResetPreference = false
                    errorMessage = failure.errorDescription
                }
                .accessibilityIdentifier("quick-action-blocked")
            } else if isLoadingGit {
                Text("Loading Git status…")
            } else if let gitError {
                Button("Retry Git Status", systemImage: "arrow.clockwise") { refreshAttempt += 1 }
                    .accessibilityIdentifier("quick-actions-refresh")
                Text(gitError)
            } else if let availability {
                Section {
                    ForEach(availability.primaryActions) { action in
                        actionRow(action, availability: availability)
                    }
                }
                if let message = availability.message { Text(message) }
                Menu("More Actions", systemImage: "ellipsis") {
                    if availability.allowsBranchCreation, !availability.primaryActions.contains(.createBranch) {
                        actionButton(.createBranch)
                    }
                    Button("Refresh Actions", systemImage: "arrow.clockwise") { refreshAttempt += 1 }
                        .accessibilityIdentifier("quick-actions-refresh")
                }
                .accessibilityIdentifier("quick-actions-more")
            }
        } label: {
            if isPreparing {
                ProgressView()
            } else {
                Image(systemName: "bolt")
            }
        }
        .menuOrder(.fixed)
        .accessibilityLabel(isPreparing ? Text("Starting action") : Text("Quick Actions"))
        .accessibilityValue(isLoadingGit && failure == nil ? Text("Loading Git status") : Text("Ready"))
        .accessibilityIdentifier("quick-actions-button")
        .disabled(isPreparing || scenePhase != .active)
        .alert("Quick Actions", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            if let failedAction {
                Button("Retry") { prepare(failedAction) }
                    .accessibilityIdentifier("quick-action-retry")
                if canResetPreference {
                    Button("Use Session Defaults") {
                        guard scenePhase == .active, model.workspaceGeneration == workspaceGeneration else { return }
                        model.saveQuickActionPreference(nil, rootID: rootID, workspaceGeneration: workspaceGeneration)
                        prepare(failedAction)
                    }
                    .accessibilityIdentifier("quick-action-reset")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: request?.id) {
            guard let request else { return }
            await start(request)
        }
        .task(id: GitLoadID(rootID: rootID, projectID: model.sessionSummary(rootID)?.projectID,
                           generation: model.workspaceGeneration,
                           isActive: scenePhase == .active, failure: failure,
                           lastActivityAt: model.sessionSummary(rootID)?.lastActivityAt, attempt: refreshAttempt)) {
            guard scenePhase == .active, model.workspaceGeneration == workspaceGeneration, failure == nil else {
                availability = nil
                return
            }
            await loadAvailability()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cancel() }
        }
        .onChange(of: model.workspaceGeneration) { _, _ in cancel() }
        .onDisappear { cancel() }
    }

    @ViewBuilder
    private func actionRow(_ action: QuickAction, availability: QuickActionAvailability) -> some View {
        if action == .commit {
            Menu("Commit…", systemImage: action.symbol) {
                Button("Commit only", systemImage: action.symbol) { prepare(.commit) }
                    .accessibilityIdentifier("quick-action-commit")
                if availability.allowsCommitAndPush { actionButton(.commitAndPush) }
            }
            .accessibilityIdentifier("quick-action-commit-menu")
        } else if action == .createPR {
            Menu("Create PR…", systemImage: action.symbol) {
                Button("Regular PR", systemImage: action.symbol) { prepare(.createPR) }
                    .accessibilityIdentifier("quick-action-create-pr")
                Button("Draft PR", systemImage: action.symbol) { prepare(.createDraftPR) }
                    .accessibilityIdentifier("quick-action-create-draft-pr")
            }
            .accessibilityIdentifier("quick-action-pr-menu")
        } else {
            actionButton(action)
        }
    }

    private func actionButton(_ action: QuickAction) -> some View {
        Button(action.title, systemImage: action.symbol) { prepare(action) }
            .accessibilityIdentifier("quick-action-\(action.rawValue)")
    }

    private func loadAvailability() async {
        let token = UUID()
        loadToken = token
        isLoadingGit = true
        availability = nil
        gitError = nil
        defer { if token == loadToken { isLoadingGit = false } }
        do {
            let loaded = try await model.quickActionAvailability(rootID: rootID)
            try Task.checkCancellation()
            guard token == loadToken, model.workspaceGeneration == workspaceGeneration, scenePhase == .active else { return }
            availability = loaded
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, token == loadToken, model.workspaceGeneration == workspaceGeneration,
                  scenePhase == .active else { return }
            gitError = error.localizedDescription
        }
    }

    private func prepare(_ action: QuickAction) {
        guard !isPreparing, scenePhase == .active, model.workspaceGeneration == workspaceGeneration,
              let projectID = model.sessionSummary(rootID)?.projectID else { return }
        errorMessage = nil
        failedAction = nil
        canResetPreference = false
        isPreparing = true
        request = Request(action: action, projectID: projectID)
    }

    private func cancel() {
        loadToken = UUID()
        availability = nil
        request = nil
        isPreparing = false
        errorMessage = nil
        failedAction = nil
    }

    private func start(_ request: Request) async {
        defer {
            if self.request?.id == request.id {
                self.request = nil
                isPreparing = false
            }
        }
        do {
            let configuration = try await QuickActionConfigurationState.load(model: model, rootID: rootID)
            try Task.checkCancellation()
            guard self.request?.id == request.id, scenePhase == .active,
                  model.workspaceGeneration == workspaceGeneration,
                  model.sessionSummary(rootID)?.projectID == request.projectID else { return }
            if let issue = configuration.preferenceIssue {
                canResetPreference = true
                errorMessage = issue
                failedAction = request.action
                return
            }
            guard let options = configuration.options else { return }
            let id = try await model.stageQuickAction(request.action, rootID: rootID, options: options,
                runConfig: configuration.runConfig, workspaceGeneration: workspaceGeneration)
            let workspaceID = model.selectedWorkspaceID
            let turnID = model.outgoingMessage(sessionID: id)?.id
            // Delivery belongs to the model's outbox after the toolbar leaves the screen.
            Task { try? await model.deliverOutgoingMessage(sessionID: id, workspaceID: workspaceID, turnID: turnID) }
            onStarted(id)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, self.request?.id == request.id,
                  model.workspaceGeneration == workspaceGeneration, scenePhase == .active else { return }
            let actionFailure = error as? QuickActionFailure
            canResetPreference = model.quickActionPreference(rootID: rootID) != nil &&
                (actionFailure == nil || actionFailure == .savedModelUnavailable || actionFailure == .savedReasoningUnavailable)
            errorMessage = error.localizedDescription
            failedAction = actionFailure == .stateChanged ? nil : request.action
            refreshAttempt += 1
        }
    }
}

/// Settings for quick tasks use the new-turn capability projection, so both model
/// and reasoning can be edited without changing a chat.
struct QuickActionConfigurationSection: View {
    let model: AppModel
    let rootID: String
    let workspaceGeneration: Int
    @Binding var state: QuickActionConfigurationState
    @Environment(\.scenePhase) private var scenePhase
    @State private var requestedAgentID: String?
    @State private var attempt = 0
    @State private var loadToken = UUID()

    private struct LoadID: Equatable {
        let agentID: String?
        let attempt: Int
        let isActive: Bool
    }

    var body: some View {
        Section {
            if let options = state.options {
                if !options.providers.isEmpty {
                    Picker("Agent", selection: Binding(get: { options.agentConfigID }, set: chooseAgent)) {
                        ForEach(options.providers, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .accessibilityIdentifier("quick-action-agent")
                }
                if let config = state.runConfig, let modelOption = config.model, !modelOption.options.isEmpty {
                    Picker("Model", selection: Binding(get: { modelOption.value }, set: chooseModel)) {
                        ForEach(modelOption.options) { Text($0.label).tag($0.value) }
                    }
                    .accessibilityIdentifier("quick-action-model")
                }
                if let config = state.runConfig, !config.reasoningOptions.isEmpty {
                    Picker("Reasoning", selection: Binding(
                        get: { config.selectedReasoning?.value ?? "" }, set: chooseReasoning
                    )) {
                        if config.selectedReasoning == nil { Text("Automatic").tag("") }
                        ForEach(config.reasoningOptions, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .accessibilityIdentifier("quick-action-reasoning")
                }
                if state.runConfig?.model == nil && state.runConfig?.reasoning == nil {
                    Text("This agent's model settings are read-only. The task inherits its defaults.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if state.isLoading {
                ProgressView("Loading agent settings…")
                    .accessibilityIdentifier("quick-action-loading")
            }
            if let error = state.error {
                Text(error).foregroundStyle(.red)
                Button("Retry") { attempt += 1 }
                    .accessibilityIdentifier("quick-action-retry")
            }
            if let issue = state.preferenceIssue {
                Text(issue).foregroundStyle(.red)
                    .accessibilityIdentifier("quick-action-config-issue")
            }
            Button("Use Session Defaults", action: reset)
                .accessibilityIdentifier("quick-action-reset")
                .disabled(scenePhase != .active)
        } header: {
            Text("Execution")
        } footer: {
            Text("Your choices are saved for Quick Actions on this machine, in this workspace and account.")
        }
        .pickerStyle(.menu)
        .task(id: LoadID(agentID: requestedAgentID, attempt: attempt, isActive: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await load()
        }
    }

    private func load() async {
        let token = UUID()
        loadToken = token
        state = QuickActionConfigurationState()
        do {
            let loaded = try await QuickActionConfigurationState.load(model: model, rootID: rootID,
                                                                      agentConfigID: requestedAgentID)
            guard !Task.isCancelled, token == loadToken, model.workspaceGeneration == workspaceGeneration else { return }
            state = loaded
            if requestedAgentID != nil, loaded.preferenceIssue == nil { save() }
        } catch {
            guard !Task.isCancelled, token == loadToken, model.workspaceGeneration == workspaceGeneration else { return }
            state.isLoading = false
            state.error = "Could not load this agent's settings. Retry or use session defaults."
        }
    }

    private func chooseAgent(_ id: String) {
        guard scenePhase == .active, model.workspaceGeneration == workspaceGeneration else { return }
        loadToken = UUID()
        state = QuickActionConfigurationState()
        requestedAgentID = id
        attempt += 1
    }

    private func chooseModel(_ value: String) {
        guard scenePhase == .active, model.workspaceGeneration == workspaceGeneration else { return }
        state.runConfig?.selectModel(value)
        state.preferenceIssue = nil
        save()
    }

    private func chooseReasoning(_ value: String) {
        guard scenePhase == .active, model.workspaceGeneration == workspaceGeneration else { return }
        if value.isEmpty { state.runConfig?.reasoning?.value = nil }
        else { state.runConfig?.selectReasoning(value) }
        state.preferenceIssue = nil
        save()
    }

    private func save() {
        guard let options = state.options, !state.isLoading, scenePhase == .active else { return }
        model.saveQuickActionPreference(.init(options: options, runConfig: state.runConfig),
            rootID: rootID, workspaceGeneration: workspaceGeneration)
    }

    private func reset() {
        guard scenePhase == .active, model.workspaceGeneration == workspaceGeneration else { return }
        loadToken = UUID()
        state = QuickActionConfigurationState()
        model.saveQuickActionPreference(nil, rootID: rootID, workspaceGeneration: workspaceGeneration)
        requestedAgentID = nil
        attempt += 1
    }
}
