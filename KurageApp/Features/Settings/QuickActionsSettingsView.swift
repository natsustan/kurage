import SwiftUI

struct QuickActionsSettingsView: View {
    let model: AppModel
    @State private var selectedMachineID: String?

    private var machines: [QuickActionMachine] { model.quickActionMachines }
    private var selectedMachine: QuickActionMachine? {
        machines.first { $0.id == selectedMachineID } ?? machines.first
    }

    var body: some View {
        Form {
            if let selectedMachine, model.supportsSessionTabs, model.supportsSessionCreation {
                Section("Machine") {
                    Picker("Machine", selection: Binding(
                        get: { selectedMachine.id }, set: { selectedMachineID = $0 }
                    )) {
                        ForEach(machines) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("quick-action-machine")
                }
                QuickActionsMachineSettings(model: model, rootID: selectedMachine.templateSessionID,
                                            workspaceGeneration: model.workspaceGeneration)
                    .id("\(model.workspaceGeneration):\(selectedMachine.id)")
            } else {
                Section {
                    Text("Open a session in a local project to configure Quick Actions for its machine.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SettingsPalette.background)
        .navigationTitle("Quick Actions")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("quick-actions-settings")
    }
}

private struct QuickActionsMachineSettings: View {
    let model: AppModel
    let rootID: String
    let workspaceGeneration: Int
    @State private var configuration = QuickActionConfigurationState()

    var body: some View {
        QuickActionConfigurationSection(model: model, rootID: rootID,
            workspaceGeneration: workspaceGeneration, state: $configuration)
    }
}
