import Foundation
import Testing
import SwiftUI
import UIKit
import Synchronization
@testable import Kurage

struct ConversationChangesTests {
    @MainActor @Test(.timeLimit(.minutes(1)))
    func diffComputationCancelsInBackgroundAndRetainsCompletedResults() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let probe = FileDiffLifecycleProbe()
        let host = UIHostingController(rootView: FileDiffLifecycleHarness(probe: probe))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            probe.computation.finish()
            window.isHidden = true
            window.rootViewController = nil
        }
        func waitUntil(_ ready: () -> Bool) async throws {
            for _ in 0..<200 {
                if ready() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("Diff computation did not reach expected state")
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(probe.computation.counts.starts == 0)
        probe.phase = .active
        try await waitUntil { probe.computation.counts.starts == 1 }
        probe.phase = .inactive
        try await waitUntil { probe.computation.counts.cancellations == 1 }
        probe.phase = .background
        try await Task.sleep(for: .milliseconds(100))
        #expect(probe.computation.counts.starts == 1)
        #expect(probe.computation.counts.completions == 0)
        probe.phase = .active
        try await waitUntil { probe.computation.counts.starts == 2 }
        probe.computation.finish()
        try await waitUntil { probe.computation.counts.completions == 1 }
        // Allow the view's task to publish the detached computation's result.
        try await Task.sleep(for: .milliseconds(100))
        probe.phase = .background
        try await Task.sleep(for: .milliseconds(100))
        probe.phase = .active
        try await Task.sleep(for: .milliseconds(100))
        #expect(probe.computation.counts.starts == 2)
        probe.phase = .background
        try await Task.sleep(for: .milliseconds(100))
        probe.edit = .init(id: "changed", oldText: "old", newText: "updated")
        try await Task.sleep(for: .milliseconds(100))
        #expect(probe.computation.counts.starts == 2)
        probe.phase = .active
        try await waitUntil { probe.computation.counts.completions == 2 }
        #expect(probe.computation.counts.starts == 3)
    }

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

    @Test func normalizedSubtaskTranscriptDecodesAndReplacesWithoutLosingParentTurns() throws {
        let previous = Conversation(sessionID: "parent", turns: [
            ConversationTurn(id: "parent-answer", author: .agent, text: "Parent answer"),
        ], permission: nil)
        func patch(_ text: String, status: String = "completed") throws -> ConversationPatch {
            try JSONDecoder().decode(ConversationPatch.self, from: Data("""
            {"sessionID":"parent","order":["parent-answer"],"changed":[],"permission":null,"activity":"idle","syncState":"live",
             "replacesSubtasks":true,"subtasks":[{"id":"run","title":"Review","agentName":"Review",
             "status":"\(status)","run":{"turns":[{"id":"output","author":"agent","text":"\(text)",
             "parts":[{"type":"text","text":"\(text)"}],"work":{"durationMs":54000,"parts":[
             {"type":"activity","id":"read","reads":1,"steps":[{"id":"tool","kind":"read","title":"Read helper.swift"}]}]}}],
             "streamsOutput":true,"outputIncomplete":true,"plan":[{"content":"Check isolation","status":"completed"}]}}]}
            """.utf8))
        }
        let initial = try patch("First").applying(to: previous).conversation
        let run = try #require(initial.subtasks?.first?.run)
        #expect(run.turns.first?.displayedWork?.title == "Worked for 54s")
        #expect(run.plan.first?.content == "Check isolation")
        #expect(run.outputIncomplete)
        let grown = try patch("First and second", status: "unknown").applying(to: initial).conversation
        #expect(grown.subtasks?.first?.status == .unknown)
        #expect(grown.subtasks?.first?.run?.turns.first?.id == run.turns.first?.id)
        #expect(grown.subtasks?.first?.run?.turns.first?.text == "First and second")
        let cancelled = try patch("Stopped", status: "cancelled").applying(to: grown).conversation
        #expect(cancelled.subtasks?.first?.status == .cancelled)
        #expect(cancelled.turns == previous.turns)
        let empty = try JSONDecoder().decode(ConversationPatch.self, from: Data("""
        {"sessionID":"parent","order":["parent-answer"],"changed":[],"permission":null,"activity":"idle","syncState":"live",
         "replacesSubtasks":true,"subtasks":[]}
        """.utf8)).applying(to: cancelled).conversation
        #expect(empty.subtasks == [])
        #expect(empty.turns == previous.turns)
    }

    @Test func incrementalSubtasksPreserveUnchangedRunsAndApplyGrowthOrderAndDeletion() throws {
        let parent = ConversationTurn(id: "parent", author: .agent, text: "Parent answer")
        let one = ConversationSubtask(id: "one", title: "One", agentName: "Agent", status: .running,
            run: .init(turns: [ConversationTurn(id: "output", author: .agent, text: "First")],
                       streamsOutput: true, outputIncomplete: false))
        let two = ConversationSubtask(id: "two", title: "Two", agentName: "Agent", status: .completed,
            run: .init(turns: [ConversationTurn(id: "answer", author: .agent, text: "Unchanged")],
                       streamsOutput: true, outputIncomplete: false))
        let previous = Conversation(sessionID: "parent", turns: [parent], permission: nil, subtasks: [one, two])
        var grown = one
        grown.run?.turns[0].text = "First and second"
        func patch(_ order: [String], changed: [ConversationSubtask]) throws -> ConversationPatch {
            let taskData = try JSONEncoder().encode(changed)
            let json = """
            {"sessionID":"parent","order":["parent"],"changed":[],"permission":null,"activity":"idle","syncState":"live",
             "subtaskOrder":\(String(data: try JSONEncoder().encode(order), encoding: .utf8)!),
             "changedSubtasks":\(String(data: taskData, encoding: .utf8)!)}
            """
            return try JSONDecoder().decode(ConversationPatch.self, from: Data(json.utf8))
        }
        let updated = try patch(["two", "one"], changed: [grown]).applying(to: previous).conversation
        #expect(updated.subtasks == [two, grown])
        #expect(updated.turns == previous.turns)
        let removed = try patch(["one"], changed: []).applying(to: updated).conversation
        #expect(removed.subtasks == [grown])
        let empty = try patch([], changed: []).applying(to: removed).conversation
        #expect(empty.subtasks == [])
        #expect(throws: LodyClientError.notConnected) {
            try patch(["missing"], changed: []).applying(to: previous)
        }
        #expect(throws: LodyClientError.notConnected) {
            try patch(["one", "one"], changed: []).applying(to: previous)
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
        guard case .ready(let hunks, let truncated) = RecordedFileDiff.preview(for: oversized) else {
            Issue.record("Large addition should retain a partial preview")
            return
        }
        #expect(truncated)
        #expect(hunks.flatMap(\.lines).count == 2_000)
    }

    @Test func diffBoundsWorkAndFoldsUnchangedContext() throws {
        let old = (0..<100).map { "line \($0)" }.joined(separator: "\n")
        let edit = ConversationFileEdit(id: "e", oldText: old, newText: old.replacingOccurrences(of: "line 50\n", with: "changed\n"))
        let lines = try #require(RecordedFileDiff.lines(for: edit))
        #expect(lines.filter { $0.kind == .gap }.count == 2)
        #expect(lines.count == 10)
        let oversized = ConversationFileEdit(id: "large", oldText: "", newText: String(repeating: "line\n", count: 2_001))
        #expect(RecordedFileDiff.lines(for: oversized)?.count == 2_000)
    }

    @Test func largeFilesWithDistantSmallChangesKeepAbsoluteLineNumbers() throws {
        let old = (1...12_000).map { "// Context line \($0) with some text" }.joined(separator: "\n")
        let new = old.replacingOccurrences(of: "line 100 with", with: "changed 100 with")
            .replacingOccurrences(of: "line 11000 with", with: "changed 11000 with")
        guard case .ready(let hunks, let truncated) = RecordedFileDiff.preview(for: .init(id: "large", oldText: old, newText: new)) else {
            Issue.record("Large files with small edits should be previewable")
            return
        }
        #expect(!truncated)
        #expect(hunks.map(\.firstNumber) == [97, 10_997])
        #expect(hunks.map(\.lastNumber) == [103, 11_003])
        #expect(hunks.map(\.additions) == [1, 1])
        #expect(hunks.map(\.deletions) == [1, 1])
    }

    @Test func diffBudgetAndSnapshotLimitsHaveSpecificNonRetryableReasons() {
        let edit = ConversationFileEdit(id: "rewrite", oldText: (0..<5_000).map { "old \($0)" }.joined(separator: "\n"),
                                       newText: (0..<5_000).map { "new \($0)" }.joined(separator: "\n"))
        guard case .unavailable(let reason) = RecordedFileDiff.preview(for: edit) else {
            Issue.record("A complete rewrite should exhaust the comparison budget")
            return
        }
        #expect(reason == "comparison_limit")
        let oversized = ConversationFileEdit(id: "oversized", oldText: "", newText: String(repeating: "x", count: 10 * 1024 * 1024 + 1))
        guard case .unavailable(let sizeReason) = RecordedFileDiff.preview(for: oversized) else {
            Issue.record("Snapshot byte limit must remain bounded")
            return
        }
        #expect(sizeReason == "snapshot_limit")
        let manyLines = ConversationFileEdit(id: "lines", oldText: "", newText: String(repeating: "\n", count: 200_000))
        guard case .unavailable(let lineReason) = RecordedFileDiff.preview(for: manyLines) else {
            Issue.record("Input line allocations must remain bounded")
            return
        }
        #expect(lineReason == "line_limit")
        for reason in ["too_large", "snapshot_limit", "line_limit", "comparison_limit", "binary", "unsupported", "not_changed"] {
            #expect(!ConversationFilePreview(status: .unavailable, reason: reason).canRetry)
        }
        #expect(ConversationFilePreview(status: .unavailable, reason: "machine_offline").canRetry)
    }

    @Test func longChangedLinesAreClearlyTruncatedAndCancellationStopsComparison() async throws {
        let edit = ConversationFileEdit(id: "long-line", oldText: "old", newText: String(repeating: "新", count: 10_000))
        guard case .ready(let hunks, let truncated) = RecordedFileDiff.preview(for: edit) else {
            Issue.record("Long lines should retain an excerpt")
            return
        }
        #expect(truncated)
        #expect(hunks.first?.lines.last?.text.hasSuffix(" …") == true)
        #expect(hunks.first?.lines.last?.text.count == 1_002)
        let grapheme = "e" + String(repeating: "\u{301}", count: 10_000)
        let pathological = ConversationFileEdit(id: "grapheme", oldText: "", newText: grapheme)
        let excerpt = try #require(RecordedFileDiff.lines(for: pathological)?.first?.text)
        #expect(excerpt.utf8.count <= 4_004)
        #expect(excerpt.hasSuffix(" …"))
        #expect(!excerpt.contains("\u{FFFD}"))
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return RecordedFileDiff.lines(for: edit)
        }
        #expect(await task.value == nil)
    }

    @Test func boundedDiffMatchesMinimalEditCountsForDuplicateAndReorderedLines() throws {
        let samples = ["", "a", "b", "a\na", "a\nb", "b\na", "a\nb\na", "b\na\nb", "a\na\nb\nb"]
        for oldText in samples {
            for newText in samples {
                let edit = ConversationFileEdit(id: "sample", oldText: oldText, newText: newText)
                let lines = try #require(RecordedFileDiff.lines(for: edit))
                let old = oldText.isEmpty ? [] : oldText.components(separatedBy: "\n")
                let new = newText.isEmpty ? [] : newText.components(separatedBy: "\n")
                #expect(lines.filter { $0.kind == .addition || $0.kind == .deletion }.count == new.difference(from: old).count)
                // Every emitted context row must pair equal source lines.
                for row in lines where row.kind == .context {
                    #expect(old[try #require(row.oldNumber) - 1] == new[try #require(row.newNumber) - 1])
                }
            }
        }
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

@MainActor @Observable
private final class FileDiffLifecycleProbe {
    var phase = ScenePhase.background
    var edit = ConversationFileEdit(id: "full", oldText: "old", newText: "new")
    let computation = FileDiffComputationProbe()
}

private final class FileDiffComputationProbe: Sendable {
    struct Counts {
        var starts = 0
        var cancellations = 0
        var completions = 0
        var canComplete = false
    }

    private let state = Mutex(Counts())
    private let wake = DispatchSemaphore(value: 0)

    var counts: Counts { state.withLock { $0 } }

    func finish() {
        state.withLock { $0.canComplete = true }
        wake.signal()
    }

    func compute(_ edit: ConversationFileEdit) -> RecordedFileDiff.Preview {
        state.withLock { $0.starts += 1 }
        // Keep the real detached computation alive until cancellation or release.
        while !state.withLock({ $0.canComplete }) {
            if Task.isCancelled {
                state.withLock { $0.cancellations += 1 }
                return .unavailable(reason: "comparison_limit")
            }
            _ = wake.wait(timeout: .now() + .milliseconds(10))
        }
        let result = RecordedFileDiff.preview(for: edit)
        state.withLock { $0.completions += 1 }
        return result
    }
}

private struct FileDiffLifecycleHarness: View {
    let probe: FileDiffLifecycleProbe

    var body: some View {
        let computation = probe.computation
        RecordedFileDiffView(edit: probe.edit, computePreview: { computation.compute($0) })
            .environment(\.scenePhase, probe.phase)
    }
}
