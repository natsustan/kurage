import Foundation

struct ConversationQuestionRequest: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let turnID: String
    let requestID: String
    var questions: [ConversationQuestion]
    var answerOptionID: String?
    var skipOptionID: String?
    var autoResolveAt: Double?
}

struct ConversationQuestion: Codable, Equatable, Sendable, Identifiable {
    struct Option: Codable, Equatable, Sendable {
        var label: String
        var description: String?
        var preview: String?
    }
    struct Note: Codable, Equatable, Sendable {
        var fieldId: String
        var title: String?
        var description: String?
        var isSecret: Bool?
    }
    let id: String
    var question: String
    var header: String
    var options: [Option]
    var multiSelect: Bool
    var allowCustomAnswer: Bool
    var isSecret: Bool
    var note: Note?
}

enum QuestionAnswer: Codable, Equatable, Sendable {
    case text(String)
    case choices([String])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { self = .text(text) }
        else { self = .choices(try container.decode([String].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .choices(let choices): try container.encode(choices)
        }
    }
}

struct QuestionDraft: Equatable {
    var selected: [String] = []
    var text = ""
    var note = ""

    func answer(for question: ConversationQuestion) -> QuestionAnswer? {
        let custom = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if question.allowCustomAnswer, !custom.isEmpty { return .text(custom) }
        guard !selected.isEmpty else { return nil }
        return question.multiSelect ? .choices(selected) : .text(selected[0])
    }
}
