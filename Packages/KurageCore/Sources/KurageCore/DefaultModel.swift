import Foundation

/// The run configuration presented by an app's composer. This shared value contains
/// only protocol-derived display rules; each platform owns its UI.
public struct RunConfigMenu: Equatable {
    public struct Section: Identifiable, Equatable {
        public enum Kind: String {
            case provider
            case model
            case reasoning

            public var title: String {
                switch self {
                case .provider: "Provider"
                case .model: "Model"
                case .reasoning: "Reasoning"
                }
            }
        }

        public var kind: Kind
        public let options: [SessionRunConfig.Value]
        public var selection: String
        public var id: Kind { kind }

        public init(kind: Kind, options: [SessionRunConfig.Value], selection: String) {
            self.kind = kind
            self.selection = selection
            let options = kind == .reasoning ? options.map {
                SessionRunConfig.Value(value: $0.value, label: RunConfigMenu.displayReasoningLabel($0.label))
            } : options
            if kind == .reasoning {
                let ranked = options.compactMap { option -> (SessionRunConfig.Value, Int)? in
                    guard let rank = Self.reasoningRank(option.value) ?? Self.reasoningRank(option.label) else { return nil }
                    return (option, rank)
                }
                var ordered = ranked.enumerated().sorted {
                    $0.element.1 == $1.element.1 ? $0.offset < $1.offset : $0.element.1 < $1.element.1
                }.map { $0.element.0 }.makeIterator()
                self.options = options.map { option in
                    if (Self.reasoningRank(option.value) ?? Self.reasoningRank(option.label)) != nil {
                        return ordered.next() ?? option
                    }
                    return option
                }
            } else {
                self.options = options
            }
        }

        public var reasoningZeroOffset: Int {
            guard let first = options.first else { return 0 }
            return (Self.reasoningRank(first.value) ?? Self.reasoningRank(first.label)) == 0 ? 0 : 1
        }

        public var reasoningTickCount: Int { options.count + reasoningZeroOffset }

        private static func reasoningRank(_ value: String) -> Int? {
            let key = value.lowercased().filter { $0.isLetter || $0.isNumber }
            switch key {
            case "none", "off", "disabled": return 0
            case "minimal": return 1
            case "low": return 2
            case "medium": return 3
            case "high": return 4
            case "xhigh", "extrahigh": return 5
            case "max", "maximum": return 6
            case "ultra": return 7
            default: return nil
            }
        }
    }

    public var modelLabel: String? = nil
    public var reasoningLabel: String? = nil
    public var providerLabel: String? = nil
    public var isLoading = false
    public var loadFailed = false
    public var modelShortcuts: [ModelShortcut] = []

    public static func displayReasoningLabel(_ label: String) -> String {
        let key = label.lowercased().filter { $0.isLetter || $0.isNumber }
        return key == "xhigh" || key == "extrahigh" ? "Extra High" : label
    }

    public var reasoningProgress: Double {
        guard let section = sections.first(where: { $0.kind == .reasoning }),
              let index = section.options.firstIndex(where: { $0.value == section.selection }) else { return 1 }
        return Double(index + section.reasoningZeroOffset) / Double(max(1, section.reasoningTickCount - 1))
    }

    public var accessibilitySummary: String
    public var sections: [Section]

    public init(
        modelLabel: String? = nil,
        reasoningLabel: String? = nil,
        providerLabel: String? = nil,
        isLoading: Bool = false,
        loadFailed: Bool = false,
        modelShortcuts: [ModelShortcut] = [],
        accessibilitySummary: String,
        sections: [Section]
    ) {
        self.modelLabel = modelLabel
        self.reasoningLabel = reasoningLabel
        self.providerLabel = providerLabel
        self.isLoading = isLoading
        self.loadFailed = loadFailed
        self.modelShortcuts = modelShortcuts
        self.accessibilitySummary = accessibilitySummary
        self.sections = sections
    }
}

/// A machine-scoped shortcut that remembers its last reasoning selection.
public struct DefaultModel: Codable, Equatable, Identifiable, Sendable {
    public struct ID: Hashable, Sendable {
        public let agentConfigID: String
        public let modelID: String
    }

    public let agentConfigID: String
    public let modelID: String
    public var providerName: String
    public var modelName: String
    public var icon: String? = nil
    public var lastReasoning: Reasoning? = nil

    public struct Reasoning: Codable, Equatable, Sendable {
        public let configOptionID: String
        public let value: String

        public init(configOptionID: String, value: String) {
            self.configOptionID = configOptionID
            self.value = value
        }
    }

    public init(
        agentConfigID: String,
        modelID: String,
        providerName: String,
        modelName: String,
        icon: String? = nil,
        lastReasoning: Reasoning? = nil
    ) {
        self.agentConfigID = agentConfigID
        self.modelID = modelID
        self.providerName = providerName
        self.modelName = modelName
        self.icon = icon
        self.lastReasoning = lastReasoning
    }

    /// Resolve a concrete, sendable effort without inheriting another model's value.
    public func restoreReasoning(in config: inout NewSessionRunConfig) {
        config.reasoning?.value = nil
        if let lastReasoning,
           config.reasoning?.configOptionID == lastReasoning.configOptionID {
            config.selectReasoning(lastReasoning.value)
        }
        let resolved = config.selectedReasoning?.value
        config.reasoning?.value = resolved
    }
    public var id: ID { ID(agentConfigID: agentConfigID, modelID: modelID) }

    public static let limit = 5

    public static func storageKey(account: Account, workspaceID: String, machineID: String) -> String? {
        guard let scope = try? JSONEncoder().encode([account.id ?? account.email.lowercased(), workspaceID, machineID]) else {
            return nil
        }
        return "defaultModels.v1.\(scope.base64EncodedString())"
    }

    public static func candidates(in options: NewSessionOptions) -> [Self] {
        (options.runConfig?.model?.options ?? []).map {
            Self(agentConfigID: options.agentConfigID, modelID: $0.value,
                 providerName: options.provider?.label ?? options.agentConfigID, modelName: $0.label,
                 icon: options.provider?.icon)
        }
    }
}

extension RunConfigMenu {
    public struct ModelShortcut: Equatable, Identifiable {
        public let model: DefaultModel
        public var isSelected: Bool
        public var isEnabled: Bool
        public var id: DefaultModel.ID { model.id }

        public init(model: DefaultModel, isSelected: Bool, isEnabled: Bool) {
            self.model = model
            self.isSelected = isSelected
            self.isEnabled = isEnabled
        }
    }
}

extension SessionRunConfig {
    public var menu: RunConfigMenu? {
        let reasoningLabel = reasoning.map { RunConfigMenu.displayReasoningLabel($0.label) }
        let parts = [model?.label, reasoningLabel].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        let accessibility = [model.map { "Model \($0.label)" }, reasoningLabel.map { "reasoning \($0)" }]
            .compactMap { $0 }.joined(separator: ", ")
        var sections: [RunConfigMenu.Section] = []
        if let editable {
            let isReasoning = editable.kind == .reasoning
            sections.append(RunConfigMenu.Section(
                kind: isReasoning ? .reasoning : .model, options: editable.options,
                selection: (isReasoning ? reasoning : model)?.value ?? ""
            ))
        }
        return RunConfigMenu(
            modelLabel: model?.label, reasoningLabel: reasoningLabel,
            accessibilitySummary: accessibility,
            sections: sections
        )
    }

    public func shortcutMenu(saved: [DefaultModel], recent: [DefaultModel] = [], agentConfigID: String?, agentName: String) -> RunConfigMenu? {
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
