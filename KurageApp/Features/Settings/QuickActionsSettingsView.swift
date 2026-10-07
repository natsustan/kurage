import SwiftUI

struct QuickActionsSettingsView: View {
    let model: AppModel
    @State private var selectedMachineID: String?

    private var machines: [QuickActionMachine] { model.quickActionMachines }
    private var selectedMachine: QuickActionMachine? {
        machines.first { $0.id == selectedMachineID } ?? machines.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let selectedMachine, model.supportsSessionTabs, model.supportsSessionCreation {
                    QuickActionSettingsPicker(title: "Machine", value: selectedMachine.name,
                        selection: Binding(get: { selectedMachine.id }, set: { selectedMachineID = $0 })) {
                        ForEach(machines) { Text($0.name).tag($0.id) }
                    }
                    .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
                    .accessibilityIdentifier("quick-action-machine")

                    ForEach(QuickActionProfile.allCases) { profile in
                        QuickActionProfileSettings(model: model, rootID: selectedMachine.templateSessionID,
                            workspaceGeneration: model.workspaceGeneration, profile: profile)
                    }
                    .id("\(model.workspaceGeneration):\(selectedMachine.id):\(selectedMachine.templateSessionID)")

                    Text("Each configuration is saved for this machine, workspace, and account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                } else {
                    Text("Open a session in a local project to configure Quick Actions for its machine.")
                        .foregroundStyle(.secondary)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
                }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(SettingsPalette.background)
        .navigationTitle("Quick Actions")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("quick-actions-settings")
    }
}

/// Each profile loads and saves independently using the new-turn capabilities.
private struct QuickActionProfileSettings: View {
    let model: AppModel
    let rootID: String
    let workspaceGeneration: Int
    let profile: QuickActionProfile
    @State private var state = QuickActionConfigurationState()
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
        VStack(alignment: .leading, spacing: 12) {
            QuickActionProfileHeader(profile: profile)
            VStack(spacing: 0) {
                if let options = state.options {
                    QuickActionConfigurationRows(options: options, runConfig: state.runConfig, profile: profile,
                        unavailableAgentID: state.unavailableAgentID,
                        chooseAgent: chooseAgent, chooseModel: chooseModel, chooseReasoning: chooseReasoning)
                }
                if state.isLoading {
                    ProgressView("Loading agent settings…")
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(profile.identifier("loading"))
                }
                if let error = state.error {
                    Text(error).foregroundStyle(.red).padding(18)
                    Button("Retry") { attempt += 1 }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(profile.identifier("retry"))
                }
                if let issue = state.preferenceIssue {
                    Text(issue).foregroundStyle(.red).padding(18)
                        .accessibilityIdentifier(profile.identifier("config-issue"))
                }
            }
            .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
        }
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
                profile: profile, agentConfigID: requestedAgentID, allowsAgentRecovery: true)
            guard !Task.isCancelled, token == loadToken, model.workspaceGeneration == workspaceGeneration else { return }
            state = loaded
            if requestedAgentID != nil, loaded.preferenceIssue == nil { save() }
        } catch {
            guard !Task.isCancelled, token == loadToken, model.workspaceGeneration == workspaceGeneration else { return }
            state.isLoading = false
            state.error = "Could not load this agent's settings. Retry to load the available options."
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
            rootID: rootID, profile: profile, workspaceGeneration: workspaceGeneration)
    }
}

private struct QuickActionProfileHeader: View {
    let profile: QuickActionProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.title).font(.subheadline.weight(.semibold))
            Text(profile.description).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
    }
}

private struct QuickActionConfigurationRows: View {
    let options: NewSessionOptions
    let runConfig: NewSessionRunConfig?
    let profile: QuickActionProfile
    let unavailableAgentID: String?
    let chooseAgent: @MainActor @Sendable (String) -> Void
    let chooseModel: @MainActor @Sendable (String) -> Void
    let chooseReasoning: @MainActor @Sendable (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !options.providers.isEmpty {
                QuickActionSettingsPicker(title: "Agent",
                    value: unavailableAgentID != nil ? String(localized: "Choose an Agent")
                        : options.provider?.label ?? options.agentConfigID,
                    selection: Binding(get: { unavailableAgentID ?? options.agentConfigID }, set: chooseAgent)) {
                    if let unavailableAgentID {
                        Text("Choose an Agent").tag(unavailableAgentID).disabled(true)
                    }
                    ForEach(options.providers, id: \.value) { Text($0.label).tag($0.value) }
                }
                .accessibilityIdentifier(profile.identifier("agent"))
                if runConfig?.model?.options.isEmpty == false || runConfig?.reasoningOptions.isEmpty == false {
                    QuickActionSettingsDivider()
                }
            }
            if let config = runConfig, let modelOption = config.model, !modelOption.options.isEmpty {
                QuickActionSettingsPicker(title: "Model",
                    value: modelOption.options.first { $0.value == modelOption.value }?.label ?? modelOption.value,
                    selection: Binding(get: { modelOption.value }, set: chooseModel)) {
                    ForEach(modelOption.options) { Text($0.label).tag($0.value) }
                }
                .accessibilityIdentifier(profile.identifier("model"))
                if runConfig?.reasoningOptions.isEmpty == false { QuickActionSettingsDivider() }
            }
            if let config = runConfig, !config.reasoningOptions.isEmpty {
                QuickActionSettingsPicker(title: "Reasoning",
                    value: config.selectedReasoning?.label ?? String(localized: "Automatic"),
                    selection: Binding(get: { config.selectedReasoning?.value ?? "" }, set: chooseReasoning)) {
                    if config.selectedReasoning == nil { Text("Automatic").tag("") }
                    ForEach(config.reasoningOptions, id: \.value) { Text($0.label).tag($0.value) }
                }
                .accessibilityIdentifier(profile.identifier("reasoning"))
            }
            if unavailableAgentID == nil && runConfig?.model == nil && runConfig?.reasoning == nil {
                Text("This agent's model settings are read-only. The task inherits its defaults.")
                    .font(.footnote).foregroundStyle(.secondary).padding(18)
            }
        }
    }
}

private struct QuickActionSettingsPicker<Options: View>: View {
    let title: LocalizedStringResource
    let value: String
    @Binding var selection: String
    @ViewBuilder let options: Options

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { options }
                .pickerStyle(.inline)
        } label: {
            HStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text(title)
                        Spacer(minLength: 12)
                        Text(value).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                        Text(value).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}

private struct QuickActionSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsPalette.separator)
            .frame(height: 0.5)
            .padding(.horizontal, 18)
            .accessibilityHidden(true)
    }
}
