import SwiftUI

struct DefaultModelsSettingsView: View {
    let model: AppModel
    @State private var selectedMachineID: String?

    var body: some View {
        let machines = model.quickActionMachines
        let selected = machines.first { $0.id == selectedMachineID } ?? machines.first
        Group {
            if let selected, model.supportsSessionCreation {
                DefaultModelsMachineSettings(model: model, machines: machines, machine: selected,
                    workspaceGeneration: model.workspaceGeneration, chooseMachine: { selectedMachineID = $0 })
                    .id("\(model.workspaceGeneration):\(selected.id):\(selected.templateSessionID)")
            } else {
                ContentUnavailableView("No models available", systemImage: "desktopcomputer",
                    description: Text("Open a session in a local project to choose models for its machine."))
            }
        }
        .background(SettingsPalette.background)
        .navigationTitle("Default Models")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("default-models-settings")
    }
}

private struct DefaultModelsMachineSettings: View {
    let model: AppModel
    let machines: [QuickActionMachine]
    let machine: QuickActionMachine
    let workspaceGeneration: Int
    let chooseMachine: (String) -> Void
    @State private var catalog: [NewSessionOptions] = []
    @State private var providers: [SessionRunConfig.Value] = []
    @State private var isLoading = true
    @State private var failed = false
    @State private var attempt = 0
    @State private var editMode = EditMode.inactive
    @Environment(\.scenePhase) private var scenePhase

    private var saved: [DefaultModel] { model.defaultModels(sessionID: machine.templateSessionID) }

    var body: some View {
        List {
            Section {
                Picker("Machine", selection: Binding(get: { machine.id }, set: chooseMachine)) {
                    ForEach(machines) { Text($0.name).tag($0.id) }
                }
                .accessibilityIdentifier("default-models-machine")
            } footer: {
                Text("Choose up to 5 models for quick access in chat.")
            }
            .modifier(DefaultModelSectionStyle())
            .listRowBackground(DefaultModelRowBackground(isFirst: true, isLast: true))

            Section {
                ForEach(saved) { entry in
                    DefaultModelSettingsRow(entry: entry, unavailable: isUnavailable(entry))
                        .listRowBackground(DefaultModelRowBackground(isFirst: entry.id == saved.first?.id))
                        .accessibilityIdentifier("default-model-\(entry.agentConfigID)-\(entry.modelID)")
                }
                .onMove { source, destination in
                    var updated = saved
                    updated.move(fromOffsets: source, toOffset: destination)
                    save(updated)
                }
                .onDelete { offsets in
                    var updated = saved
                    updated.remove(atOffsets: offsets)
                    save(updated)
                }
                NavigationLink {
                    AddDefaultModelView(catalog: catalog, saved: saved, isLoading: isLoading, failed: failed,
                        retry: { attempt += 1 }, add: { entry in
                            guard !saved.contains(where: { $0.id == entry.id }), saved.count < DefaultModel.limit else { return }
                            save(saved + [entry])
                        })
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                        Text("Add Model")
                    }
                }
                .disabled(saved.count >= DefaultModel.limit)
                .accessibilityIdentifier("default-models-add")
                .moveDisabled(true)
                .deleteDisabled(true)
                .listRowBackground(DefaultModelRowBackground(isFirst: saved.isEmpty, isLast: true))
            } header: {
                HStack {
                    Text("Selected")
                        .foregroundStyle(Color.primary)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(saved.count) / 5")
                        .fontWeight(.regular)
                        .accessibilityIdentifier("default-models-count")
                }
            } footer: {
                if saved.count >= DefaultModel.limit {
                    Text("Remove a model to add another.")
                } else if editMode.isEditing {
                    Text("Drag to reorder.")
                }
            }
            .modifier(DefaultModelSectionStyle())

            if isLoading {
                Section { CatalogLoadingRow() }
                    .listSectionSeparator(.hidden)
            }
            if failed {
                Section {
                    Button("Could not load all providers. Retry") { attempt += 1 }
                        .accessibilityIdentifier("default-models-retry")
                }
                .modifier(DefaultModelSectionStyle())
                .listRowBackground(DefaultModelRowBackground(isFirst: true, isLast: true))
            }
        }
        .listStyle(.grouped)
        .environment(\.defaultMinListRowHeight, 50)
        .scrollContentBackground(.hidden)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        .environment(\.editMode, $editMode)
        .task(id: "\(attempt):\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            await load()
        }
    }

    private func save(_ entries: [DefaultModel]) {
        guard scenePhase == .active else { return }
        model.saveDefaultModels(entries, sessionID: machine.templateSessionID, workspaceGeneration: workspaceGeneration)
    }

    private func isUnavailable(_ entry: DefaultModel) -> Bool {
        if let options = catalog.first(where: { $0.agentConfigID == entry.agentConfigID }) {
            return !DefaultModel.candidates(in: options).contains { $0.id == entry.id }
        }
        return !isLoading && !failed && !providers.contains { $0.value == entry.agentConfigID }
    }

    private func load() async {
        isLoading = true
        failed = false
        do {
            let initial = try await model.quickActionOptions(rootID: machine.templateSessionID, agentConfigID: nil)
            guard !Task.isCancelled, model.workspaceGeneration == workspaceGeneration else { return }
            providers = initial.providers
            catalog = [initial]
            for provider in initial.providers where provider.value != initial.agentConfigID {
                do {
                    let options = try await model.quickActionOptions(rootID: machine.templateSessionID, agentConfigID: provider.value)
                    guard !Task.isCancelled, model.workspaceGeneration == workspaceGeneration else { return }
                    catalog.append(options)
                } catch {
                    guard !Task.isCancelled, model.workspaceGeneration == workspaceGeneration else { return }
                    failed = true
                }
            }
        } catch {
            guard !Task.isCancelled, model.workspaceGeneration == workspaceGeneration else { return }
            failed = true
        }
        isLoading = false
    }
}

private struct AddDefaultModelView: View {
    let catalog: [NewSessionOptions]
    let saved: [DefaultModel]
    let isLoading: Bool
    let failed: Bool
    let retry: () -> Void
    let add: (DefaultModel) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private struct ProviderGroup: Identifiable {
        let id: String
        let name: String
        let entries: [DefaultModel]
    }

    private var groups: [ProviderGroup] {
        catalog.compactMap { options in
            let entries = DefaultModel.candidates(in: options).filter {
                search.isEmpty || $0.modelName.localizedCaseInsensitiveContains(search) ||
                    $0.providerName.localizedCaseInsensitiveContains(search)
            }
            return entries.isEmpty ? nil : ProviderGroup(id: options.agentConfigID,
                name: options.provider?.label ?? options.agentConfigID, entries: entries)
        }
    }

    var body: some View {
        List {
            ForEach(groups) { group in
                Section(group.name) {
                    ForEach(group.entries) { entry in
                        let selected = saved.contains { $0.id == entry.id }
                        Button {
                            add(entry)
                            dismiss()
                        } label: {
                            HStack {
                                DefaultModelSettingsRow(entry: entry)
                                if selected { Image(systemName: "checkmark").foregroundStyle(.blue) }
                            }
                            .foregroundStyle(.primary)
                        }
                        .disabled(selected || saved.count >= DefaultModel.limit)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .listRowBackground(DefaultModelRowBackground(
                            isFirst: entry.id == group.entries.first?.id,
                            isLast: entry.id == group.entries.last?.id))
                        .accessibilityIdentifier("add-default-model-\(entry.agentConfigID)-\(entry.modelID)")
                    }
                }
                .modifier(DefaultModelSectionStyle())
            }
            if isLoading && !catalog.isEmpty {
                Section { CatalogLoadingRow() }
                    .listSectionSeparator(.hidden)
            }
            if failed { Button("Could not load all providers. Retry", action: retry) }
            if groups.isEmpty && !isLoading && !failed { Text("No models found").foregroundStyle(.secondary) }
        }
        .listStyle(.grouped)
        .environment(\.defaultMinListRowHeight, 50)
        .searchable(text: $search, prompt: "Search models")
        .scrollContentBackground(.hidden)
        .background(SettingsPalette.background)
        .overlay {
            if isLoading && catalog.isEmpty && !failed {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .accessibilityLabel("Loading models")
            }
        }
        .navigationTitle("Add Model")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DefaultModelSettingsRow: View {
    let entry: DefaultModel
    var unavailable = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            ModelProviderIcon(icon: entry.icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.modelName)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                if unavailable { Text("Unavailable").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.modelName), \(entry.providerName)")
        .accessibilityValue(unavailable ? String(localized: "Unavailable") : "")
    }
}

private struct CatalogLoadingRow: View {
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            ProgressView()
                .progressViewStyle(.circular)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading models")
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

private struct DefaultModelSectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listSectionMargins(.horizontal, 16)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listSectionSeparator(.hidden)
            .listRowSeparatorTint(SettingsPalette.separator)
    }
}

private struct DefaultModelRowBackground: View {
    var isFirst = false
    var isLast = false

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? 20 : 0,
            bottomLeadingRadius: isLast ? 20 : 0,
            bottomTrailingRadius: isLast ? 20 : 0,
            topTrailingRadius: isFirst ? 20 : 0
        )
        .fill(SettingsPalette.groupBackground)
    }
}

struct ModelProviderIcon: View {
    let icon: String?

    private var asset: String? {
        guard let icon, ["codex", "claude", "gemini", "deepseek", "kimi", "grok", "minimax", "glm", "mimo",
                         "pi", "devin", "amp", "cursor", "opencode", "copilot"].contains(icon) else { return nil }
        return "provider-\(icon)"
    }

    var body: some View {
        Group {
            if let asset {
                Image(asset).resizable().scaledToFit()
            } else {
                Image(systemName: "cpu").font(.body)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}
