import Foundation

/// A machine-scoped shortcut, never a reasoning preset or an automatic default.
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
    func shortcutMenu(saved: [DefaultModel], agentConfigID: String?, agentName: String) -> RunConfigMenu? {
        guard var menu else { return nil }
        menu.providerLabel = saved.first { $0.agentConfigID == agentConfigID }?.providerName ?? agentName
        let providerID = agentConfigID ?? ""
        let icon = saved.first { $0.agentConfigID == agentConfigID }?.icon ?? agentName
        let available = editable?.kind == .model ? editable?.options ?? [] : []
        let candidates = saved.isEmpty ? available.map {
            DefaultModel(agentConfigID: providerID, modelID: $0.value,
                         providerName: menu.providerLabel ?? agentName, modelName: $0.label, icon: icon)
        } : saved.filter { $0.agentConfigID == agentConfigID }
        menu.modelShortcuts = candidates.map { candidate in
            .init(model: candidate, isSelected: candidate.modelID == model?.value,
                  isEnabled: available.contains { $0.value == candidate.modelID })
        }
        if let model, !menu.modelShortcuts.contains(where: { $0.isSelected }) {
            menu.modelShortcuts.insert(.init(model: DefaultModel(agentConfigID: providerID, modelID: model.value,
                providerName: menu.providerLabel ?? agentName, modelName: model.label, icon: icon),
                isSelected: true, isEnabled: false), at: 0)
        }
        return menu
    }
}
