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

    var explanation: String {
        switch reason {
        case "turn_unavailable": "Historical snapshots are unavailable for this turn."
        case "not_changed": "No text differences recorded for this file."
        case "binary": "Binary files cannot be previewed as code."
        case "too_large": "This code difference is too large to preview."
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
    static func hunks(for edit: ConversationFileEdit) -> [FileDiffHunk]? {
        guard let lines = lines(for: edit) else { return nil }
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

    // Keep expensive comparisons bounded, including fixtures and decoded payloads.
    static func lines(for edit: ConversationFileEdit) -> [FileDiffLine]? {
        guard edit.oldText.utf8.count + edit.newText.utf8.count <= 128 * 1024 else { return nil }
        func split(_ text: String) -> [String] {
            guard !text.isEmpty else { return [] }
            return text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }.map(String.init)
        }
        let old = split(edit.oldText)
        let new = split(edit.newText)
        guard old.count + new.count <= 2_000 else { return nil }
        let difference = new.difference(from: old)
        guard !difference.isEmpty else { return [] }
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var rows: [FileDiffLine] = []
        var left = 0
        var right = 0
        while left < old.count || right < new.count {
            if Task.isCancelled { return nil }
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
        var visible = Set<Int>()
        for row in rows where row.kind != .context {
            for index in max(0, row.id - 3)...min(rows.count - 1, row.id + 3) { visible.insert(index) }
        }
        var result: [FileDiffLine] = []
        var inGap = false
        for row in rows {
            if visible.contains(row.id) {
                result.append(row)
                inGap = false
            } else if !inGap {
                result.append(FileDiffLine(id: row.id, oldNumber: nil, newNumber: nil,
                                           text: "…", kind: .gap))
                inGap = true
            }
        }
        return result
    }
}
