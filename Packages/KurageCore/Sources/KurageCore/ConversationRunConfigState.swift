import Foundation

/// Separates the synchronized configuration from a choice for the next new turn.
public struct ConversationRunConfigState {
    public init() {}

    public private(set) var config: SessionRunConfig?
    public private(set) var choice: RunConfigChoice?
    private var awaitsRestoredConfig = false

    public var displayed: SessionRunConfig? { config?.applying(choice) }

    public mutating func receive(_ config: SessionRunConfig?) {
        self.config = config
        // Observation can emit an empty configuration before capabilities arrive.
        guard config != nil || !awaitsRestoredConfig else { return }
        awaitsRestoredConfig = false
        // Drop a choice the agent no longer offers in the same place.
        choice = RunConfigChoice.combining(choice?.individualChoices.filter {
            config?.choosing($0.value) == $0 || config?.fastMode?.choosing($0.value) == $0
        } ?? [])
    }

    public mutating func choose(_ value: String) {
        guard let selected = config?.choosing(value) else { return }
        // Even selecting the current baseline is explicit intent: an unconfirmed
        // earlier turn can still change the configuration the next turn inherits.
        select(selected)
    }

    public mutating func chooseFastMode(_ value: String) {
        guard let selected = config?.fastMode?.choosing(value) else { return }
        select(selected)
    }

    public mutating func restore(_ choice: RunConfigChoice?) {
        for selection in choice?.individualChoices ?? [] {
            if config == nil || config?.choosing(selection.value) == selection ||
                config?.fastMode?.choosing(selection.value) == selection {
                select(selection)
            }
        }
        // An early resend carries the original choices through the normal sending path.
        awaitsRestoredConfig = config == nil && self.choice != nil
    }

    private mutating func select(_ selected: RunConfigChoice) {
        var choices = choice?.individualChoices ?? []
        choices.removeAll { $0.configOptionID == selected.configOptionID }
        choices.append(selected)
        choice = RunConfigChoice.combining(choices)
    }

    public mutating func didSend(_ sentChoice: RunConfigChoice?) {
        config = config?.applying(sentChoice)
        // A retry can send an older choice. Keep any unused selection for the next turn.
        let sent = sentChoice?.individualChoices ?? []
        choice = RunConfigChoice.combining(choice?.individualChoices.filter { !sent.contains($0) } ?? [])
        awaitsRestoredConfig = awaitsRestoredConfig && choice != nil
    }
}
