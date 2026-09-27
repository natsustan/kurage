import Foundation
import Testing
@testable import Kurage

struct ConversationChangesTests {
    @Test func subtaskPatchesReplaceAndClearWithoutLosingParentContent() throws {
        let subtask = ConversationSubtask(id: "child", title: "Review", agentName: "codex", status: .running)
        let previous = Conversation(sessionID: "root", turns: [
            ConversationTurn(id: "a", author: .agent, text: "Parent output"),
        ], permission: nil, subtasks: [subtask])
        func patch(_ fields: String) throws -> ConversationPatch {
            try JSONDecoder().decode(ConversationPatch.self, from: Data("""
            {"sessionID":"root","order":["a"],"changed":[],"permission":null,"activity":"idle","syncState":"live"\(fields)}
            """.utf8))
        }
        let unchanged = try patch("").applying(to: previous).conversation
        #expect(unchanged.subtasks == [subtask])
        let changed = try patch("""
        ,"replacesSubtasks":true,"subtasks":[{"id":"child","title":"Review","agentName":"codex","status":"idle"}]
        """).applying(to: previous).conversation
        #expect(changed.subtasks?.first?.status == .idle)
        #expect(changed.turns == previous.turns)
        let removed = try patch(",\"replacesSubtasks\":true,\"subtasks\":[]").applying(to: changed).conversation
        #expect(removed.subtasks == [])
        #expect(removed.turns == previous.turns)
    }

    @Test @MainActor func subtasksStayOutOfRootListAndUseWorkspaceScopedReading() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, records: SessionRecord.samplesWithSubtasks)
        let roots = try await client.sessions(workspaceID: "ws-demo")
        #expect(!roots.contains { $0.id == "review-reuse" || $0.id == "review-quality" })
        let parent = try await client.conversation(sessionID: "session-long", workspaceID: "ws-demo")
        #expect(parent.subtasks?.map(\.id) == ["review-reuse", "review-quality"])
        let other = try await client.conversation(sessionID: "session-tests", workspaceID: "ws-demo")
        #expect(other.subtasks == [])
        let child = try await client.conversation(sessionID: "review-reuse", workspaceID: "ws-demo")
        #expect(child.turns.last?.text == "Reuse review finished.")
        await #expect(throws: LodyClientError.self) {
            try await client.conversation(sessionID: "review-reuse", workspaceID: "other-workspace")
        }
    }

    @Test func latestTurnSurvivesPatchesEvenWhenItsUserMessageIsNotDisplayable() throws {
        let previous = Conversation(sessionID: "s", turns: [], permission: nil,
                                    fileChanges: [.fixture], latestTurnNumber: 21)
        #expect(previous.lastTurnNumber == 21)
        let patch = try JSONDecoder().decode(ConversationPatch.self, from: Data("""
        {"sessionID":"s","order":[],"changed":[],"permission":null,"activity":"idle","syncState":"live","latestTurnNumber":22}
        """.utf8))
        let next = try patch.applying(to: previous).conversation
        #expect(next.lastTurnNumber == 22)
        #expect(next.fileChanges == previous.fileChanges)
        #expect(next.fileChanges?.filter { $0.turnNumber == next.lastTurnNumber }.isEmpty == true)
    }

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
