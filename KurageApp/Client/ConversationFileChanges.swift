import Foundation

struct ConversationFileChangeGroup: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let turnNumber: Int
    let files: [ConversationFileChange]
}

struct ConversationFileChange: Codable, Equatable, Sendable, Identifiable {
    var id: String { path }
    let path: String
    let additions: Int?
    let deletions: Int?
    let edits: [ConversationFileEdit]
    var previewLimited: Bool? = nil
    /// Historical checkpoint identity; changes invalidate an already loaded preview.
    var previewRevision: String? = nil
    /// A running turn's final checkpoint can arrive without changing its counts.
    var previewFinished: Bool? = nil

    var name: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
}

struct ConversationFileEdit: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let oldText: String
    let newText: String
}

struct ConversationFilePreview: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case ready, unavailable }
    let status: Status
    var edit: ConversationFileEdit? = nil
    var reason: String? = nil

    var canRetry: Bool { reason == "machine_offline" || reason == "permission_denied" || reason == "turn_unavailable" }

    var explanation: LocalizedStringResource {
        switch reason {
        case "turn_unavailable": "Historical snapshots are unavailable for this turn."
        case "not_changed": "No text differences recorded for this file."
        case "binary": "Binary files cannot be previewed as code."
        case "too_large": "The session machine could not provide this snapshot because it exceeds its size limit."
        case "snapshot_limit": "This file exceeds the preview limit of 10 MiB per snapshot."
        case "line_limit": "This file has too many lines to compare on this device."
        case "comparison_limit": "This file has too many changes to compare on this device."
        case "unsupported": "This machine does not support historical code previews."
        case "machine_offline": "The session machine is offline. Try again when it is online."
        case "permission_denied": "This file cannot be read with the current permissions."
        default: "Historical code preview is unavailable for this file."
        }
    }
}

struct FileDiffHunk: Identifiable, Equatable, Sendable {
    let id: Int
    let lines: [FileDiffLine]
    var additions: Int { lines.filter { $0.kind == .addition }.count }
    var deletions: Int { lines.filter { $0.kind == .deletion }.count }
    var firstNumber: Int { lines.first.flatMap { $0.newNumber ?? $0.oldNumber } ?? 1 }
    var lastNumber: Int { lines.last.flatMap { $0.newNumber ?? $0.oldNumber } ?? firstNumber }
}

struct FileChangeSummary: Equatable {
    let count: Int
    let additions: Int?
    let deletions: Int?

    init(_ groups: [ConversationFileChangeGroup]) {
        let files = groups.flatMap(\.files)
        count = Set(files.map(\.path)).count
        func total(_ values: [Int?]) -> Int? {
            var result = 0
            for value in values {
                guard let value, value >= 0 else { return nil }
                let sum = result.addingReportingOverflow(value)
                guard !sum.overflow else { return nil }
                result = sum.partialValue
            }
            return result
        }
        additions = total(files.map(\.additions))
        deletions = total(files.map(\.deletions))
    }
}

/// Line numbers belong to the recorded text block, which may be a file excerpt.
struct FileDiffLine: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case context, addition, deletion, gap }
    let id: Int
    let oldNumber: Int?
    let newNumber: Int?
    let text: String
    let kind: Kind
}

enum RecordedFileDiff {
    enum Preview: Sendable {
        case ready(hunks: [FileDiffHunk], truncated: Bool)
        case unavailable(reason: String)
    }

    private struct Comparison {
        let lines: [FileDiffLine]
        let truncated: Bool
    }

    private enum Limit: String, Error {
        case snapshotLimit = "snapshot_limit"
        case lineLimit = "line_limit"
        case comparisonLimit = "comparison_limit"
    }
    private static let maxSnapshotBytes = 10 * 1024 * 1024
    private static let maxInputLines = 200_000
    private static let maxVisibleLines = 2_000

    static func preview(for edit: ConversationFileEdit) -> Preview {
        do {
            let result = try compare(edit)
            return .ready(hunks: hunks(from: result.lines), truncated: result.truncated)
        } catch let limit as Limit {
            return .unavailable(reason: limit.rawValue)
        } catch {
            // Cancelled work is discarded by the view's task before publication.
            return .unavailable(reason: "comparison_limit")
        }
    }

    static func hunks(for edit: ConversationFileEdit) -> [FileDiffHunk]? {
        guard case .ready(let hunks, _) = preview(for: edit) else { return nil }
        return hunks
    }

    static func lines(for edit: ConversationFileEdit) -> [FileDiffLine]? {
        try? compare(edit).lines
    }

    private static func hunks(from lines: [FileDiffLine]) -> [FileDiffHunk] {
        var hunks: [FileDiffHunk] = []
        var current: [FileDiffLine] = []
        for line in lines {
            if line.kind == .gap {
                if let first = current.first { hunks.append(FileDiffHunk(id: first.id, lines: current)) }
                current = []
            } else { current.append(line) }
        }
        if let first = current.first { hunks.append(FileDiffHunk(id: first.id, lines: current)) }
        return hunks
    }

    private static func compare(_ edit: ConversationFileEdit) throws -> Comparison {
        try Task.checkCancellation()
        guard edit.oldText.utf8.count <= maxSnapshotBytes, edit.newText.utf8.count <= maxSnapshotBytes else {
            throw Limit.snapshotLimit
        }
        func split(_ text: String) throws -> [String] {
            guard !text.isEmpty else { return [] }
            let parts = text.split(maxSplits: maxInputLines, omittingEmptySubsequences: false,
                                   whereSeparator: { $0 == "\n" || $0 == "\r\n" })
            guard parts.count <= maxInputLines else { throw Limit.lineLimit }
            var lines: [String] = []
            for line in parts {
                try Task.checkCancellation()
                lines.append(String(line))
            }
            return lines
        }
        let old = try split(edit.oldText)
        let new = try split(edit.newText)
        guard old.count + new.count <= maxInputLines else { throw Limit.lineLimit }
        let (removed, inserted) = try changes(old: old, new: new)
        guard !removed.isEmpty || !inserted.isEmpty else { return Comparison(lines: [], truncated: false) }
        var rows: [FileDiffLine] = []
        var left = 0
        var right = 0
        while left < old.count || right < new.count {
            try Task.checkCancellation()
            if left < old.count && removed.contains(left) {
                rows.append(FileDiffLine(id: rows.count, oldNumber: left + 1, newNumber: nil,
                                         text: old[left], kind: .deletion))
                left += 1
            } else if right < new.count && inserted.contains(right) {
                rows.append(FileDiffLine(id: rows.count, oldNumber: nil, newNumber: right + 1,
                                         text: new[right], kind: .addition))
                right += 1
            } else {
                rows.append(FileDiffLine(id: rows.count, oldNumber: left + 1, newNumber: right + 1,
                                         text: old[left], kind: .context))
                left += 1
                right += 1
            }
        }
        var visible = Array(repeating: false, count: rows.count)
        for row in rows where row.kind != .context {
            try Task.checkCancellation()
            for index in max(0, row.id - 3)...min(rows.count - 1, row.id + 3) { visible[index] = true }
        }
        var result: [FileDiffLine] = []
        var inGap = false
        var truncated = false
        var visibleBytes = 0
        for row in rows {
            try Task.checkCancellation()
            if visible[row.id] {
                if result.count >= maxVisibleLines || visibleBytes >= 512 * 1024 {
                    truncated = true
                    break
                }
                let text = excerpt(row.text)
                if text != row.text { truncated = true }
                visibleBytes += text.utf8.count
                result.append(FileDiffLine(id: row.id, oldNumber: row.oldNumber, newNumber: row.newNumber,
                                           text: text == row.text ? text : text + " …", kind: row.kind))
                inGap = false
            } else if !inGap {
                result.append(FileDiffLine(id: row.id, oldNumber: nil, newNumber: nil,
                                           text: "…", kind: .gap))
                inGap = true
            }
        }
        return Comparison(lines: result, truncated: truncated)
    }

    private static func excerpt(_ text: String) -> String {
        let characters = String(text.prefix(1_000))
        let bytes = characters.utf8
        guard bytes.count > 4_000 else { return characters }
        // Also bound pathological single graphemes, without cutting a UTF-8 scalar.
        var end = bytes.index(bytes.startIndex, offsetBy: 4_000)
        while bytes[end] & 0xC0 == 0x80 { end = bytes.index(before: end) }
        return String(decoding: bytes[..<end], as: UTF8.self)
    }

    /// Myers' shortest edit path, bounded by frontier/comparison work and trace memory.
    /// Common ends are skipped first, so a small edit in a large file stays cheap.
    private static func changes(old: [String], new: [String]) throws -> (Set<Int>, Set<Int>) {
        var prefix = 0
        while prefix < min(old.count, new.count) && old[prefix] == new[prefix] {
            try Task.checkCancellation()
            prefix += 1
        }
        var oldEnd = old.count
        var newEnd = new.count
        while oldEnd > prefix && newEnd > prefix && old[oldEnd - 1] == new[newEnd - 1] {
            try Task.checkCancellation()
            oldEnd -= 1
            newEnd -= 1
        }
        let m = oldEnd - prefix
        let n = newEnd - prefix
        if m == 0 { return ([], Set(prefix..<newEnd)) }
        if n == 0 { return (Set(prefix..<oldEnd), []) }
        var trace: [[Int]] = []
        var work = 0
        for distance in 0...min(m + n, 2_000) {
            try Task.checkCancellation()
            var frontier = Array(repeating: 0, count: 2 * distance + 1)
            for diagonal in stride(from: -distance, through: distance, by: 2) {
                work += 1
                guard work <= 1_000_000 else { throw Limit.comparisonLimit }
                var x = 0
                if distance > 0 {
                    let previous = trace[distance - 1]
                    if diagonal == -distance || (diagonal != distance &&
                        previous[diagonal - 1 + distance - 1] < previous[diagonal + 1 + distance - 1]) {
                        x = previous[diagonal + 1 + distance - 1]
                    } else { x = previous[diagonal - 1 + distance - 1] + 1 }
                }
                var y = x - diagonal
                while x < m && y < n {
                    work += 1
                    guard work <= 1_000_000 else { throw Limit.comparisonLimit }
                    try Task.checkCancellation()
                    guard old[prefix + x] == new[prefix + y] else { break }
                    x += 1
                    y += 1
                }
                frontier[diagonal + distance] = x
                if x >= m && y >= n {
                    var removed = Set<Int>()
                    var inserted = Set<Int>()
                    var x = m
                    var y = n
                    for step in stride(from: distance, through: 1, by: -1) {
                        try Task.checkCancellation()
                        let previous = trace[step - 1]
                        let diagonal = x - y
                        let previousDiagonal: Int
                        if diagonal == -step || (diagonal != step &&
                            previous[diagonal - 1 + step - 1] < previous[diagonal + 1 + step - 1]) {
                            previousDiagonal = diagonal + 1
                        } else { previousDiagonal = diagonal - 1 }
                        let previousX = previous[previousDiagonal + step - 1]
                        let previousY = previousX - previousDiagonal
                        while x > previousX && y > previousY { x -= 1; y -= 1 }
                        if x == previousX { y -= 1; inserted.insert(prefix + y) }
                        else { x -= 1; removed.insert(prefix + x) }
                    }
                    return (removed, inserted)
                }
            }
            trace.append(frontier)
        }
        throw Limit.comparisonLimit
    }
}
