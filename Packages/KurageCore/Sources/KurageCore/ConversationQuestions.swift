import Foundation

public struct ConversationQuestionRequest: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let turnID: String
    public let requestID: String
    public var questions: [ConversationQuestion]
    public var answerOptionID: String?
    public var skipOptionID: String?
    public var autoResolveAt: Double?
}

public struct ConversationQuestion: Codable, Equatable, Sendable, Identifiable {
    public struct Option: Codable, Equatable, Sendable {
        public var label: String
        public var description: String?
        public var preview: String?
    }
    public struct Note: Codable, Equatable, Sendable {
        public var fieldId: String
        public var title: String?
        public var description: String?
        public var isSecret: Bool?
    }
    public let id: String
    public var question: String
    public var header: String
    public var options: [Option]
    public var multiSelect: Bool
    public var allowCustomAnswer: Bool
    public var isSecret: Bool
    public var note: Note?
}

public enum QuestionAnswer: Codable, Equatable, Sendable {
    case text(String)
    case choices([String])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { self = .text(text) }
        else { self = .choices(try container.decode([String].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .choices(let choices): try container.encode(choices)
        }
    }
}

public struct QuestionDraft: Equatable {
    public var selected: [String] = []
    public var text = ""
    public var note = ""

    public init(selected: [String] = [], text: String = "", note: String = "") {
        self.selected = selected
        self.text = text
        self.note = note
    }

    public func answer(for question: ConversationQuestion) -> QuestionAnswer? {
        let custom = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if question.allowCustomAnswer, !custom.isEmpty { return .text(custom) }
        guard !selected.isEmpty else { return nil }
        return question.multiSelect ? .choices(selected) : .text(selected[0])
    }
}
