import Foundation

/// Separates the synchronized configuration from a choice for the next new turn.
public struct ConversationRunConfigState {
    public init() {}

    public private(set) var config: SessionRunConfig?
    public private(set) var choice: RunConfigChoice?

    public var displayed: SessionRunConfig? { config?.applying(choice) }

    public mutating func receive(_ config: SessionRunConfig?) {
        self.config = config
        // Drop a choice the agent no longer offers in the same place.
        if let choice, config?.choosing(choice.value) != choice {
            self.choice = nil
        }
    }

    public mutating func choose(_ value: String) {
        guard let selected = config?.choosing(value) else { return }
        // Even selecting the current baseline is explicit intent: an unconfirmed
        // earlier turn can still change the configuration the next turn inherits.
        choice = selected
    }

    public mutating func didSend(_ sentChoice: RunConfigChoice?) {
        config = config?.applying(sentChoice)
        // A retry can send an older choice. Keep any unused selection for the next turn.
        if choice == sentChoice { choice = nil }
    }
}
