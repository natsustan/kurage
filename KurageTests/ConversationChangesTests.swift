import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Kurage

struct ConversationChangesTests {
    @MainActor @Test(.serialized, .timeLimit(.minutes(1)))
    func historicalLoadCancelsInBackgroundAndResumesWithoutRecordedText() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let probe = FilePreviewLoadProbe()
        let host = UIHostingController(rootView: FilePreviewLifecycleHarness(probe: probe))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func waitUntil(_ ready: () -> Bool) async throws {
            for _ in 0..<200 {
                if ready() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("Historical preview did not reach expected state")
        }
        try await waitUntil { probe.starts == 1 }
        probe.phase = .inactive
        try await waitUntil { probe.cancellations == 1 }
        probe.phase = .background
        try await Task.sleep(for: .milliseconds(100))
        #expect(probe.starts == 1)
        probe.phase = .active
        try await waitUntil { probe.completions == 1 }
        #expect(probe.starts == 2)
        probe.phase = .background
        probe.phase = .active
        try await Task.sleep(for: .milliseconds(100))
        #expect(probe.starts == 2)
    }

    @MainActor @Test func lateHistoricalPreviewCannotSurviveSignOutOrWrongWorkspace() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()
        let file = ConversationFileChangeGroup.fixture.files[1]
        await #expect(throws: CancellationError.self) {
            try await model.filePreview(sessionID: "session-long", turnID: "long-agent-20", file: file, workspaceID: "other-workspace")
        }
        let task = Task { try await model.filePreview(sessionID: "session-long", turnID: "long-agent-20", file: file, workspaceID: "ws-demo") }
        try await Task.sleep(for: .milliseconds(50))
        model.signOut()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func historicalPreviewDecodesFullSnapshotsAndHunksKeepAbsoluteLineNumbers() throws {
        let preview = try JSONDecoder().decode(ConversationFilePreview.self, from: Data(#"{"status":"ready","edit":{"id":"turn:file","oldText":"old","newText":"new"}}"#.utf8))
        #expect(preview.status == .ready)
        #expect(preview.edit?.newText == "new")
        let old = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let new = old.replacingOccurrences(of: "line 10\n", with: "changed 10\n")
            .replacingOccurrences(of: "line 80\n", with: "changed 80\n")
        let hunks = try #require(RecordedFileDiff.hunks(for: .init(id: "diff", oldText: old, newText: new)))
        #expect(hunks.count == 2)
        #expect(hunks.map(\.firstNumber) == [7, 77])
        #expect(hunks.map(\.lastNumber) == [13, 83])
        #expect(hunks.map(\.additions) == [1, 1])
        #expect(hunks.map(\.deletions) == [1, 1])
        #expect(hunks[1].lines.first { $0.kind == .deletion }?.oldNumber == 80)
    }

    @MainActor @Test func fixtureHistoricalPreviewReadsSummaryOnlyFileAndRejectsAnotherWorkspace() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let preview = try await client.filePreview(sessionID: "session-long", turnID: "long-agent-20",
            path: "KurageTests/ConversationChangesTests.swift", workspaceID: "ws-demo")
        #expect(preview.status == .ready)
        #expect(preview.edit?.newText.contains("Historical test line 12") == true)
        await #expect(throws: LodyClientError.self) {
            try await client.filePreview(sessionID: "session-long", turnID: "long-agent-20",
                path: "KurageTests/ConversationChangesTests.swift", workspaceID: "other-workspace")
        }
        let missing = try await client.filePreview(sessionID: "session-long", turnID: "another-turn",
            path: "KurageTests/ConversationChangesTests.swift", workspaceID: "ws-demo")
        #expect(missing.reason == "turn_unavailable")
    }
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
        ,"replacesSubtasks":true,"subtasks":[{"id":"child","title":"Review","agentName":"codex","status":"completed","summary":"Done","totalTokens":42,"toolUses":2}]
        """).applying(to: previous).conversation
        #expect(changed.subtasks?.first?.status == .completed)
        #expect(changed.subtasks?.first?.summary == "Done")
        #expect(changed.subtasks?.first?.totalTokens == 42)
        #expect(changed.subtasks?.first?.toolUses == 2)
        #expect(changed.turns == previous.turns)
        let removed = try patch(",\"replacesSubtasks\":true,\"subtasks\":[]").applying(to: changed).conversation
        #expect(removed.subtasks == [])
        #expect(removed.turns == previous.turns)
    }

    @Test @MainActor func subtasksAreHistoryDataNotSessionsAndStayWorkspaceScoped() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, records: SessionRecord.samplesWithSubtasks)
        let roots = try await client.sessions(workspaceID: "ws-demo")
        #expect(!roots.contains { $0.id == "review-reuse" || $0.id == "review-quality" })
        let parent = try await client.conversation(sessionID: "session-long", workspaceID: "ws-demo")
        #expect(parent.subtasks?.map(\.id) == ["review-reuse", "review-quality"])
        let other = try await client.conversation(sessionID: "session-tests", workspaceID: "ws-demo")
        #expect(other.subtasks == [])
        await #expect(throws: LodyClientError.self) {
            try await client.conversation(sessionID: "review-reuse", workspaceID: "ws-demo")
        }
        await #expect(throws: LodyClientError.self) {
            try await client.conversation(sessionID: "session-long", workspaceID: "other-workspace")
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

    @Test func diffHandlesCRLFAndMixedLineEndings() throws {
        let edit = ConversationFileEdit(id: "crlf", oldText: "a\r\n旧\r\nz\r\n", newText: "a\r\n新\nextra\r\nz\r\n")
        let lines = try #require(RecordedFileDiff.lines(for: edit))
        #expect(lines.filter { $0.kind == .deletion }.map(\.text) == ["旧"])
        #expect(lines.filter { $0.kind == .addition }.map(\.text) == ["新", "extra"])
        #expect(lines.first { $0.text == "z" }?.oldNumber == 3)
        #expect(lines.first { $0.text == "z" }?.newNumber == 4)
        #expect(lines.last?.text == "")
        #expect(lines.last?.newNumber == 5)
        let oversized = ConversationFileEdit(id: "large", oldText: "", newText: String(repeating: "line\r\n", count: 2_001))
        #expect(RecordedFileDiff.lines(for: oversized) == nil)
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

@MainActor @Observable
private final class FilePreviewLoadProbe {
    var phase = ScenePhase.active
    var starts = 0
    var cancellations = 0
    var completions = 0

    func load() async throws -> ConversationFilePreview {
        starts += 1
        if starts == 1 {
            do { try await Task.sleep(for: .seconds(60)) }
            catch { cancellations += 1; throw error }
        }
        completions += 1
        return ConversationFilePreview(status: .ready, edit: .init(id: "full", oldText: "old", newText: "new"))
    }
}

private struct FilePreviewLifecycleHarness: View {
    let probe: FilePreviewLoadProbe

    var body: some View {
        FileChangeCardDetails(group: .fixture, file: ConversationFileChangeGroup.fixture.files[1],
                              loadPreview: { _, _ in try await probe.load() })
            .environment(\.scenePhase, probe.phase)
    }
}
