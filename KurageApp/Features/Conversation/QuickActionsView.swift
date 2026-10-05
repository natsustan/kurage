import SwiftUI

struct QuickActionRoute: Identifiable {
    let rootID: String
    let workspaceGeneration: Int
    var id: String { rootID }
}

struct QuickActionConfigurationState {
    var options: NewSessionOptions?
    var runConfig: NewSessionRunConfig?
    var isLoading = true
    var error: String?
    var preferenceIssue: String?

    var isReady: Bool { options != nil && !isLoading && error == nil && preferenceIssue == nil }
}

struct QuickActionsView: View {
    let route: QuickActionRoute
    let model: AppModel
    let onStarted: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var configuration = QuickActionConfigurationState()
    @State private var startError: String?
    @State private var isStarting = false

    private var root: SessionSummary? { model.sessionSummary(route.rootID) }
    private var failure: QuickActionFailure? { model.quickActionBlockingFailure(rootID: route.rootID) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Working Directory") {
                    LabeledContent("Project", value: root?.projectName ?? "Project")
                    LabeledContent("Machine", value: root?.machineName ?? "Machine")
                    Text("Uses this session's working directory and current Git branch.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                QuickActionConfigurationSection(model: model, rootID: route.rootID,
                    workspaceGeneration: route.workspaceGeneration, state: $configuration)
                if let failure {
                    Section {
                        Text(failure.message).foregroundStyle(.secondary)
                            .accessibilityIdentifier("quick-action-blocked")
                    }
                }
                Section {
                    ForEach(QuickAction.allCases) { action in
                        Button { start(action) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: action.symbol)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(action.title).font(.body.weight(.medium))
                                    Text(action.detail).font(.footnote).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("quick-action-\(action.rawValue)")
                        .disabled(!configuration.isReady || failure != nil || isStarting || scenePhase != .active)
                    }
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Each action opens a new task tab. Commits stay local; nothing is pushed.")
                }
                if let startError {
                    Section { Text(startError).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SettingsPalette.background)
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("quick-actions-close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("quick-actions-panel")
        .onChange(of: model.workspaceGeneration) { _, _ in dismiss() }
    }

    private func start(_ action: QuickAction) {
        guard configuration.isReady, let options = configuration.options, !isStarting, scenePhase == .active else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let id = try model.stageQuickAction(action, rootID: route.rootID, options: options,
                runConfig: configuration.runConfig, workspaceGeneration: route.workspaceGeneration)
            let workspaceID = model.selectedWorkspaceID
            let turnID = model.outgoingMessage(sessionID: id)?.id
            onStarted(id)
            // Like ordinary tab creation, delivery belongs to the model's outbox.
            Task { try? await model.deliverOutgoingMessage(sessionID: id, workspaceID: workspaceID, turnID: turnID) }
            dismiss()
        } catch is CancellationError {
            dismiss()
        } catch {
            startError = error.localizedDescription
        }
    }
}

/// Shared by Settings and the action panel; choices use the new-turn capability
/// projection, so both model and reasoning can be edited without changing a chat.
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
        let preference = model.quickActionPreference(rootID: rootID)
        let agentID = requestedAgentID ?? preference?.agentConfigID
        do {
            var options = try await model.newSessionOptions(templateSessionID: rootID, agentConfigID: agentID, isTab: true)
            if options.needsRefresh == true {
                options = try await model.newSessionOptions(templateSessionID: rootID, agentConfigID: agentID,
                                                            isTab: true, refresh: true)
            }
            try Task.checkCancellation()
            guard token == loadToken, model.workspaceGeneration == workspaceGeneration else { return }
            var config = options.runConfig
            var issue: String?
            if preference?.agentConfigID == options.agentConfigID {
                do { try preference?.apply(to: &config) } catch { issue = error.localizedDescription }
            }
            state = QuickActionConfigurationState(options: options, runConfig: config,
                                                  isLoading: false, preferenceIssue: issue)
            if requestedAgentID != nil, issue == nil { save() }
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
