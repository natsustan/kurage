import SwiftUI

/// The visible token stays short while the sent prompt carries Lody's stable
/// skill path or session URI. Offsets use UTF-16, matching native text selection.
struct ComposerMentionState: Equatable {
    enum Kind: Equatable {
        case session(id: String, title: String)
        case skill(token: String, path: String)
    }

    struct Range: Equatable {
        var start: Int
        var end: Int
        var token: String
        var kind: Kind
    }

    private(set) var ranges: [Range] = []
    private var previousText = ""

    var hasSkillMentions: Bool {
        ranges.contains { if case .skill = $0.kind { return true } else { return false } }
    }

    private static func editRange(from oldText: String, to newText: String)
        -> (old: [UInt16], prefix: Int, oldEnd: Int, newEnd: Int) {
        let old = Array(oldText.utf16)
        let new = Array(newText.utf16)
        let prefix = zip(old, new).prefix { $0 == $1 }.count
        let suffix = zip(old.dropFirst(prefix).reversed(), new.dropFirst(prefix).reversed())
            .prefix { $0 == $1 }.count
        return (old, prefix, old.count - suffix, new.count - suffix)
    }

    mutating func reconcile(_ text: String) {
        guard text != previousText else { return }
        let (_, prefix, oldEnd, newEnd) = Self.editRange(from: previousText, to: text)
        let change = newEnd - oldEnd
        ranges = ranges.compactMap { range in
            if range.end <= prefix { return range }
            if range.start >= oldEnd {
                var shifted = range
                shifted.start += change
                shifted.end += change
                return shifted
            }
            return nil
        }
        previousText = text
    }

    /// Expand a user deletion to the boundaries of every selected mention it
    /// touches. Plain typing and IME composition still use normal reconciliation.
    mutating func edit(_ text: String) -> (text: String, caret: Int?) {
        let (old, prefix, oldEnd, newEnd) = Self.editRange(from: previousText, to: text)
        guard oldEnd > prefix, newEnd == prefix else {
            reconcile(text)
            return (text, nil)
        }
        let touched = ranges.filter { $0.start < oldEnd && $0.end > prefix }
        guard !touched.isEmpty else {
            reconcile(text)
            return (text, nil)
        }
        let start = min(prefix, touched.map(\.start).min()!)
        let end = max(oldEnd, touched.map(\.end).max()!)
        let edited = String(decoding: old[..<start] + old[end...], as: UTF16.self)
        reconcile(edited)
        return (edited, start)
    }

    mutating func insert(_ token: String, kind: Kind, replacing replacement: Swift.Range<String.Index>, in text: String) -> (String, Int) {
        reconcile(text)
        let start = replacement.lowerBound.utf16Offset(in: text)
        let end = replacement.upperBound.utf16Offset(in: text)
        let inserted = token + " "
        let change = inserted.utf16.count - (end - start)
        ranges = ranges.compactMap { range in
            if range.end <= start { return range }
            if range.start >= end {
                var shifted = range
                shifted.start += change
                shifted.end += change
                return shifted
            }
            return nil
        }
        ranges.append(Range(start: start, end: start + token.utf16.count, token: token, kind: kind))
        ranges.sort { $0.start < $1.start }
        var edited = text
        edited.replaceSubrange(replacement, with: inserted)
        previousText = edited
        return (edited, start + inserted.utf16.count)
    }

    func expanded(_ text: String) -> String {
        var result = text
        for range in ranges.sorted(by: { $0.start > $1.start }) {
            guard range.start >= 0, range.end <= result.utf16.count else { continue }
            let start = String.Index(utf16Offset: range.start, in: result)
            let end = String.Index(utf16Offset: range.end, in: result)
            guard String(result[start..<end]) == range.token else { continue }
            let prompt: String
            switch range.kind {
            case .session(let id, let title):
                let label = ("@" + title).replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "[", with: "\\[")
                    .replacingOccurrences(of: "]", with: "\\]")
                prompt = "[\(label)](session://\(id))"
            case .skill(let token, let path):
                let destination = path.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: ")", with: "\\)")
                prompt = "use /\(token) [Skill Path](\(destination))"
            }
            result.replaceSubrange(start..<end, with: prompt)
        }
        return result
    }

    /// Re-point skill mentions at the skills the current source offers, dropping
    /// the ones it no longer has. A dropped token leaves the text as well: sent
    /// as plain words it would silently mean something else than the mention the
    /// user picked — and project skill paths are relative to their project.
    mutating func resolveSkills(_ skills: [MentionSkill], in text: String) -> String? {
        let paths = Dictionary(skills.map { ($0.token, $0.path) }, uniquingKeysWith: { first, _ in first })
        var kept: [Range] = []
        var dropped: [Range] = []
        for range in ranges {
            guard case .skill(let token, let path) = range.kind else {
                kept.append(range)
                continue
            }
            guard let updated = paths[token] else {
                dropped.append(range)
                continue
            }
            var range = range
            if updated != path { range.kind = .skill(token: token, path: updated) }
            kept.append(range)
        }
        ranges = kept
        guard !dropped.isEmpty else { return nil }
        var units = Array(text.utf16)
        for range in dropped.sorted(by: { $0.start > $1.start }) {
            guard range.start >= 0, range.end <= units.count else { continue }
            // The composer inserts a trailing space after every token.
            let end = range.end < units.count && units[range.end] == 0x20 ? range.end + 1 : range.end
            units.removeSubrange(range.start..<end)
            for index in ranges.indices where ranges[index].start >= end {
                ranges[index].start -= end - range.start
                ranges[index].end -= end - range.start
            }
        }
        let rewritten = String(decoding: units, as: UTF16.self)
        previousText = rewritten
        return rewritten
    }

    mutating func clear() {
        ranges = []
        previousText = ""
    }
}

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
