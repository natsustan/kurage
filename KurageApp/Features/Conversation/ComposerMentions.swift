import SwiftUI

/// The visible token stays short while the sent prompt carries Lody's stable
/// skill path or session URI. Offsets use UTF-16, matching TextField selection.
struct ComposerMentionState {
    enum Kind {
        case session(id: String, title: String)
        case skill(token: String, path: String)
    }

    struct Range {
        var start: Int
        var end: Int
        var token: String
        var kind: Kind
    }

    private(set) var ranges: [Range] = []
    private var previousText = ""

    mutating func reconcile(_ text: String) {
        guard text != previousText else { return }
        let old = Array(previousText.utf16)
        let new = Array(text.utf16)
        let prefix = zip(old, new).prefix { $0 == $1 }.count
        let suffix = zip(old.dropFirst(prefix).reversed(), new.dropFirst(prefix).reversed())
            .prefix { $0 == $1 }.count
        let oldEnd = old.count - suffix
        let newEnd = new.count - suffix
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
        let old = Array(previousText.utf16)
        let new = Array(text.utf16)
        let prefix = zip(old, new).prefix { $0 == $1 }.count
        let suffix = zip(old.dropFirst(prefix).reversed(), new.dropFirst(prefix).reversed())
            .prefix { $0 == $1 }.count
        let oldEnd = old.count - suffix
        let newEnd = new.count - suffix
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
