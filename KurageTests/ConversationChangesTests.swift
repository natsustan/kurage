import Foundation
import Testing
@testable import Kurage

struct ConversationChangesTests {
    @Test func summaryCountsUniqueFilesButKeepsRecordedEditTotals() {
        let first = ConversationFileChangeGroup.fixture
        let second = ConversationFileChangeGroup(id: "other", turnNumber: 21, files: [first.files[0]])
        let summary = FileChangeSummary([first, second])
        #expect(summary.count == 2)
        #expect(summary.additions == 16)
        #expect(summary.deletions == 2)
        let unknown = ConversationFileChangeGroup(id: "unknown", turnNumber: 1, files: [
            ConversationFileChange(path: "other", additions: nil, deletions: nil, edits: []),
        ])
        #expect(FileChangeSummary([first, unknown]).additions == nil)
    }

    @Test func fileOnlyPatchReplacesAndClearsChangesWithoutLosingText() throws {
        let previous = Conversation(sessionID: "s", turns: [
            ConversationTurn(id: "a", author: .agent, text: "Hello"),
        ], permission: nil, fileChanges: [.fixture])
        let data = Data("""
        {"sessionID":"s","order":["a"],"changed":[],"permission":null,"activity":"idle","syncState":"live",
         "replacesFileChanges":true,"fileChanges":[{"id":"a","turnNumber":1,"files":[{"path":"test.swift","additions":1,"deletions":0,"edits":[]}]}]}
        """.utf8)
        let patch = try JSONDecoder().decode(ConversationPatch.self, from: data)
        let updated = try patch.applying(to: previous).conversation
        #expect(updated.turns == previous.turns)
        let unchanged = try JSONDecoder().decode(ConversationPatch.self, from: Data("""
        {"sessionID":"s","order":["a"],"changed":[],"permission":null,"activity":"idle","syncState":"live"}
        """.utf8))
        #expect(try unchanged.applying(to: updated).conversation.fileChanges == updated.fileChanges)

        #expect(updated.fileChanges?.first?.files.first?.path == "test.swift")
        let clear = try JSONDecoder().decode(ConversationPatch.self, from: Data("""
        {"sessionID":"s","order":["a"],"changed":[],"permission":null,"activity":"idle","syncState":"live","replacesFileChanges":true,"fileChanges":null}
        """.utf8))
        #expect(try clear.applying(to: updated).conversation.fileChanges == nil)
        let old = try JSONDecoder().decode(Conversation.self, from: Data(#"{"sessionID":"s","turns":[],"permission":null}"#.utf8))
        #expect(old.fileChanges == nil)
    }

    @Test func diffHandlesInsertDeleteUnicodeAndTrailingNewlines() throws {
        let edit = ConversationFileEdit(id: "e", oldText: "a\n旧\nz\n", newText: "a\n新\nextra\nz\n")
        let lines = try #require(RecordedFileDiff.lines(for: edit))
        #expect(lines.filter { $0.kind == .deletion }.map(\.text) == ["旧"])
        #expect(lines.filter { $0.kind == .addition }.map(\.text) == ["新", "extra"])
        #expect(lines.first { $0.text == "z" }?.oldNumber == 3)
        #expect(lines.first { $0.text == "z" }?.newNumber == 4)
        #expect(RecordedFileDiff.lines(for: .init(id: "e", oldText: "", newText: "new"))?.first?.kind == .addition)
        #expect(RecordedFileDiff.lines(for: .init(id: "e", oldText: "old", newText: ""))?.first?.kind == .deletion)
        #expect(RecordedFileDiff.lines(for: .init(id: "e", oldText: "same", newText: "same")) == [])
    }

    @Test func diffBoundsWorkAndFoldsUnchangedContext() throws {
        let old = (0..<100).map { "line \($0)" }.joined(separator: "\n")
        let edit = ConversationFileEdit(id: "e", oldText: old, newText: old.replacingOccurrences(of: "line 50\n", with: "changed\n"))
        let lines = try #require(RecordedFileDiff.lines(for: edit))
        #expect(lines.filter { $0.kind == .gap }.count == 2)
        #expect(lines.count == 10)
        let oversized = ConversationFileEdit(id: "large", oldText: "", newText: String(repeating: "line\n", count: 2_001))
        #expect(RecordedFileDiff.lines(for: oversized) == nil)
    }
}
