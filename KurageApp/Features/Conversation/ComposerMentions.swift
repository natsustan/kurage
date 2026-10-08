import SwiftUI
import KurageCore

struct ComposerMentionQuery: Equatable {
    enum Trigger: Character { case skill = "$", combined = "@" }
    let trigger: Trigger
    let term: String
    let range: Swift.Range<String.Index>

    /// Search the skill's identity, not prose in its description. Keep source
    /// order within each rank so equal matches retain discovery precedence.
    func skillCandidates(in skills: [MentionSkill]) -> [MentionSkill] {
        guard !term.isEmpty else { return skills }
        var exact: [MentionSkill] = []
        var prefix: [MentionSkill] = []
        var substring: [MentionSkill] = []
        for skill in skills {
            let rank = [skill.token, skill.name].compactMap { value -> Int? in
                guard let match = value.localizedStandardRange(of: term) else { return nil }
                if match == value.startIndex..<value.endIndex { return 0 }
                return match.lowerBound == value.startIndex ? 1 : 2
            }.min()
            switch rank {
            case 0: exact.append(skill)
            case 1: prefix.append(skill)
            case 2: substring.append(skill)
            default: break
            }
        }
        return exact + prefix + substring
    }

    static func active(in text: String, selection: TextSelection?) -> Self? {
        let caret: String.Index
        if let selection, case .selection(let range) = selection.indices, range.isEmpty {
            // SwiftUI can briefly retain a selection from the previous draft
            // when the field gains focus. Never index `text` with that value.
            caret = text.indices.first(where: { $0 == range.lowerBound }) ?? text.endIndex
        } else {
            caret = text.endIndex
        }
        var start = caret
        while start > text.startIndex {
            let prior = text.index(before: start)
            let character = text[prior]
            if character.isWhitespace { break }
            start = prior
        }
        guard start < caret, let trigger = Trigger(rawValue: text[start]) else { return nil }
        let termStart = text.index(after: start)
        let term = String(text[termStart..<caret])
        guard !term.contains("@"), !term.contains("$") else { return nil }
        return Self(trigger: trigger, term: term, range: start..<caret)
    }
}
