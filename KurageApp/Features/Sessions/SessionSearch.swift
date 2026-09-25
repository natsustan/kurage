import Foundation

enum SessionSearch {
    struct Result: Equatable {
        /// A transcript line, present when the title itself does not match.
        var snippet: String?
    }

    static func bodyText(_ turns: [ConversationTurn]) -> String {
        turns.compactMap { turn in
            var lines: [String] = []
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { lines.append(turn.text) }
            for part in turn.parts {
                guard case .text(let partText) = part else { continue }
                let trimmed = partText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != text else { continue }
                lines.append(partText)
            }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// Blank queries are not matches. Callers show the unfiltered list themselves.
    static func result(title: String, body: String, query: String) -> Result? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        let titleMatches = contains(title, needle)
        guard titleMatches || contains(body, needle) else { return nil }
        guard !titleMatches else { return Result(snippet: nil) }
        return Result(snippet: snippet(in: body, matching: needle))
    }

    private static let options: String.CompareOptions = [
        .caseInsensitive, .diacriticInsensitive, .widthInsensitive,
    ]

    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: options) != nil
    }

    private static func snippet(in body: String, matching query: String, limit: Int = 80) -> String? {
        guard let range = body.range(of: query, options: options) else { return nil }
        let lineStart = body[..<range.lowerBound].lastIndex(of: "\n").map { body.index(after: $0) } ?? body.startIndex
        let lineEnd = body[range.upperBound...].firstIndex(of: "\n") ?? body.endIndex
        let line = String(body[lineStart..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        return window(line, around: query, limit: limit)
    }

    private static func window(_ line: String, around query: String, limit: Int) -> String {
        guard line.count > limit, let range = line.range(of: query, options: options) else { return line }
        let prefix = line.distance(from: line.startIndex, to: range.lowerBound)
        let match = min(line.distance(from: range.lowerBound, to: range.upperBound), limit)
        var startOffset = max(0, prefix - (limit - match) / 2)
        if startOffset + limit > line.count {
            startOffset = max(0, line.count - limit)
        }
        let start = line.index(line.startIndex, offsetBy: startOffset)
        let end = line.index(start, offsetBy: limit, limitedBy: line.endIndex) ?? line.endIndex
        var text = String(line[start..<end])
        if startOffset > 0 { text = "…" + text }
        if end < line.endIndex { text += "…" }
        return text
    }
}
