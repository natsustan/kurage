import Foundation

/// A machine-scoped shortcut that remembers its last reasoning selection.
struct DefaultModel: Codable, Equatable, Identifiable, Sendable {
    struct ID: Hashable, Sendable {
        let agentConfigID: String
        let modelID: String
    }

    let agentConfigID: String
    let modelID: String
    var providerName: String
    var modelName: String
    var icon: String? = nil
    var lastReasoning: Reasoning? = nil

    struct Reasoning: Codable, Equatable, Sendable {
        let configOptionID: String
        let value: String
    }

    /// Never carry another model's effort into a favorite with no valid memory.
    func restoreReasoning(in config: inout NewSessionRunConfig) {
        config.reasoning?.value = nil
        guard let lastReasoning,
              config.reasoning?.configOptionID == lastReasoning.configOptionID else { return }
        config.selectReasoning(lastReasoning.value)
    }
    var id: ID { ID(agentConfigID: agentConfigID, modelID: modelID) }

    static let limit = 5

    static func storageKey(account: Account, workspaceID: String, machineID: String) -> String? {
        guard let scope = try? JSONEncoder().encode([account.id ?? account.email.lowercased(), workspaceID, machineID]) else {
            return nil
        }
        return "defaultModels.v1.\(scope.base64EncodedString())"
    }

    static func candidates(in options: NewSessionOptions) -> [Self] {
        (options.runConfig?.model?.options ?? []).map {
            Self(agentConfigID: options.agentConfigID, modelID: $0.value,
                 providerName: options.provider?.label ?? options.agentConfigID, modelName: $0.label,
                 icon: options.provider?.icon)
        }
    }
}

extension RunConfigMenu {
    struct ModelShortcut: Equatable, Identifiable {
        let model: DefaultModel
        var isSelected: Bool
        var isEnabled: Bool
        var id: DefaultModel.ID { model.id }
    }
}

extension SessionRunConfig {
    func shortcutMenu(saved: [DefaultModel], recent: [DefaultModel] = [], agentConfigID: String?, agentName: String) -> RunConfigMenu? {
        guard var menu else { return nil }
        let shortcuts = saved.isEmpty ? recent : saved
        menu.providerLabel = shortcuts.first { $0.agentConfigID == agentConfigID }?.providerName ?? agentName
        let providerID = agentConfigID ?? ""
        let icon = shortcuts.first { $0.agentConfigID == agentConfigID }?.icon ?? agentName
        let available = editable?.kind == .model ? editable?.options ?? [] : []
        let candidates = shortcuts.filter { candidate in
            candidate.agentConfigID == agentConfigID && (!saved.isEmpty ||
                candidate.modelID == model?.value || available.contains { $0.value == candidate.modelID })
        }
        menu.modelShortcuts = candidates.map { candidate in
            .init(model: candidate, isSelected: candidate.modelID == model?.value,
                  isEnabled: available.contains { $0.value == candidate.modelID })
        }
        if let model, !menu.modelShortcuts.contains(where: { $0.isSelected }) {
            menu.modelShortcuts.insert(.init(model: DefaultModel(agentConfigID: providerID, modelID: model.value,
                providerName: menu.providerLabel ?? agentName, modelName: model.label, icon: icon),
                isSelected: true, isEnabled: false), at: 0)
        }
        if saved.isEmpty { menu.modelShortcuts = Array(menu.modelShortcuts.prefix(DefaultModel.limit)) }
        return menu
    }
}
