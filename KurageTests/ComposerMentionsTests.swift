import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Kurage

struct ComposerMentionsTests {
    @Test(arguments: ["$review", "@review", "还有一个 bug $REVIEW"])
    func skillSearchIgnoresDescriptionsAndRanksNames(draft: String) throws {
        let query = try #require(ComposerMentionQuery.active(in: draft, selection: nil))
        let skills = [
            MentionSkill(token: "app-intents-specialist", name: "App Intents Specialist",
                         description: "Consult for any correctness review", path: "/skills/intents"),
            MentionSkill(token: "code-review", name: "Code Review",
                         description: "", path: "/skills/code-review"),
            MentionSkill(token: "review-agent", name: "Review Agent",
                         description: "", path: "/skills/review-agent"),
            MentionSkill(token: "swiftui-specialist", name: "SwiftUI Specialist",
                         description: "Review SwiftUI code", path: "/review-project/skills/swiftui"),
            MentionSkill(token: "review", name: "Review",
                         description: "", path: "/skills/review"),
            MentionSkill(token: "review-and-simplify-changes", name: "Review and Simplify Changes",
                         description: "", path: "/skills/simplify"),
            MentionSkill(token: "inspect", name: "Review Changes",
                         description: "", path: "/skills/inspect"),
        ]
        #expect(query.skillCandidates(in: skills).map(\.token) == [
            "review", "review-agent", "review-and-simplify-changes", "inspect", "code-review",
        ])
    }

    @Test func skillSearchRanksBeforeTheCandidateLimit() throws {
        let skills = (0..<30).map {
            MentionSkill(token: "code-review-\($0)", name: "Code Review \($0)",
                         description: "", path: "/skills/\($0)")
        } + [MentionSkill(token: "review-agent", name: "Review Agent",
                          description: "", path: "/skills/review-agent")]
        let query = try #require(ComposerMentionQuery.active(in: "$review", selection: nil))
        let candidates = Array(query.skillCandidates(in: skills).prefix(25))
        #expect(candidates.count == 25)
        #expect(candidates.first?.token == "review-agent")
        #expect(candidates.last?.token == "code-review-23")
    }

    @Test func skillSearchKeepsEmptyQueryAndHandlesNoMatches() throws {
        let skills = [MentionSkill(token: "swiftui", name: "SwiftUI",
                                   description: "Review code", path: "/skills/swiftui")]
        let empty = try #require(ComposerMentionQuery.active(in: "$", selection: nil))
        #expect(empty.skillCandidates(in: skills) == skills)
        let missing = try #require(ComposerMentionQuery.active(in: "$review", selection: nil))
        #expect(missing.skillCandidates(in: skills).isEmpty)
    }

    @Test func skillSearchMatchesNamesCaseAndDiacriticInsensitively() throws {
        let skill = MentionSkill(token: "inspect", name: "Réview Agent",
                                 description: "", path: "/skills/inspect")
        let query = try #require(ComposerMentionQuery.active(in: "$REVIEW", selection: nil))
        #expect(query.skillCandidates(in: [skill]) == [skill])
    }

    @MainActor
    @Test func nativeTypingDoesNotReplayItsPublishedCaret() {
        var text = "Im"
        var selection: TextSelection? = TextSelection(insertionPoint: text.endIndex)
        let editor = MentionEditor(text: Binding(get: { text }, set: { text = $0 }),
                                   selection: Binding(get: { selection }, set: { selection = $0 }),
                                   isFocused: .constant(false), ranges: [], isEnabled: true,
                                   identifier: "editor", accessibilityLabel: "Draft")
        let coordinator = editor.makeCoordinator()
        let view = UITextView()
        view.attributedText = NSAttributedString(string: "Immediate")
        view.selectedRange = NSRange(location: 9, length: 0)
        coordinator.textViewDidChange(view)
        #expect(text == "Immediate")
        #expect(coordinator.renderedText == text)

        // UIKit can advance its caret before the next delegate callback.
        // A SwiftUI update must not replay the last published native caret.
        view.attributedText = NSAttributedString(string: "Immediate first")
        view.selectedRange = NSRange(location: 15, length: 0)
        coordinator.applyRequestedSelection(to: view)
        #expect(view.selectedRange.location == 15)
        coordinator.textViewDidChange(view)
        #expect(text == "Immediate first")

        coordinator.parent.selectionRequest = .init(caret: 0)
        coordinator.applyRequestedSelection(to: view)
        #expect(view.selectedRange == NSRange(location: 0, length: 0))
    }

    @MainActor
    @Test func nativeTypingDuringAViewUpdateIsDeferredInsteadOfDropped() async {
        var text = "Imme"
        var selection: TextSelection?
        let editor = MentionEditor(text: Binding(get: { text }, set: { text = $0 }),
                                   selection: Binding(get: { selection }, set: { selection = $0 }),
                                   isFocused: .constant(false), ranges: [], isEnabled: true,
                                   identifier: "editor", accessibilityLabel: "Draft")
        let coordinator = editor.makeCoordinator()
        let view = UITextView()
        coordinator.isUpdating = true
        for value in ["Immediate", "Immediate first turn"] {
            view.attributedText = NSAttributedString(string: value)
            view.selectedRange = NSRange(location: value.utf16.count, length: 0)
            coordinator.textViewDidChange(view)
        }
        #expect(text == "Imme")
        coordinator.isUpdating = false
        await Task.yield()
        #expect(text == "Immediate first turn")
        #expect(coordinator.renderedText == text)
    }

    @MainActor
    @Test(.serialized, arguments: ["Send a follow-up", "Build anything"])
    func emptyComposerExposesItsInputPurpose(placeholder: String) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let host = UIHostingController(rootView: SessionComposer(
            draft: .constant(""), mentions: .constant(.init()), attachments: .constant([]),
            isSending: false, isCancelling: false, isSessionRunning: false,
            supportsTextSending: true, supportsTextSendingWhileRunning: false,
            supportsSessionCancellation: false, runConfig: nil,
            placeholder: LocalizedStringResource(stringLiteral: placeholder),
            onSend: { false }, onCancel: {}, onChooseRunConfig: { _, _ in }))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        var views = [host.view!]
        var editor: UITextView?
        while let view = views.popLast() {
            if let textView = view as? UITextView { editor = textView; break }
            views.append(contentsOf: view.subviews)
        }
        let field = try #require(editor)
        #expect(field.accessibilityLabel == placeholder)
        #expect(field.accessibilityIdentifier == "follow-up-field")
        #expect(field.accessibilityValue == "")
    }

    @MainActor
    @Test(.serialized, .timeLimit(.minutes(1)), arguments: ["@review", "$review"])
    func mentionLoadsCancelOffForegroundAndResume(draft: String) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let probe = MentionLoadProbe()
        let host = UIHostingController(rootView: MentionLifecycleHarness(probe: probe, draft: draft))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitForMentionLoad(probe: probe) { probe.starts == 2 && probe.completions == 1 }
        probe.phase = .inactive
        try await waitForMentionLoad(probe: probe) { probe.cancellations == 1 }
        probe.phase = .background
        try await Task.sleep(for: .milliseconds(100))
        #expect(probe.starts == 2)
        #expect(probe.skillStarts == 1)

        probe.phase = .active
        try await waitForMentionLoad(probe: probe) { probe.completions == 2 }
        #expect(probe.starts == 3)
    }

    @MainActor
    @Test func decoratedDraftPreservesUnicodeOffsetsAndProtocolTargets() {
        var state = ComposerMentionState()
        var text = "🐈 看 "
        (text, _) = state.insert("$review", kind: .skill(token: "review", path: "/skills/review/SKILL.md"),
                                 replacing: text.endIndex..<text.endIndex, in: text)
        (text, _) = state.insert("@会话", kind: .session(id: "chat", title: "会话"),
                                 replacing: text.endIndex..<text.endIndex, in: text)
        let rendered = MentionText.decorate(text, ranges: state.ranges, font: .systemFont(ofSize: 17), color: .systemBlue)
        #expect(rendered.length == text.utf16.count)
        #expect(!rendered.string.contains("$"))
        #expect(!rendered.string.contains("@"))
        #expect(MentionText.originalText(rendered) == text)
        #expect(state.expanded(MentionText.originalText(rendered)) == state.expanded(text))
    }

    @MainActor
    @Test func bubbleReferencesHideProtocolAndPreserveCopySource() {
        let text = #"🐈 use /review [Skill Path](folder\)/SKILL.md) 与 [@聊天\[一\]🐈](session://chat_1)\n继续"#
        let rendered = MentionText.message(text, font: .systemFont(ofSize: 17), color: .systemBlue)
        #expect(rendered.string.contains("review"))
        #expect(rendered.string.contains("聊天[一]🐈"))
        #expect(!rendered.string.contains("Skill Path"))
        #expect(!rendered.string.contains("session://"))
        #expect(MentionText.originalText(rendered) == text)
        let ordinary = "Use $review, @someone and [a link](https://example.com)."
        #expect(MentionText.references(in: ordinary).isEmpty)
    }

    @Test func skillAndSessionMentionsExpandToLodyPromptForms() {
        var state = ComposerMentionState()
        var text = "Ask @review"
        let sessionStart = text.range(of: "@review")!
        (text, _) = state.insert("@Review-Agent", kind: .session(id: "ses_123", title: "Review Agent"),
                                 replacing: sessionStart, in: text)
        let skillRange = text.endIndex..<text.endIndex
        (text, _) = state.insert("$swiftui-specialist",
                                 kind: .skill(token: "swiftui-specialist", path: ".agents/skills/swiftui-specialist/SKILL.md"),
                                 replacing: skillRange, in: text)
        #expect(state.expanded(text) ==
                "Ask [@Review Agent](session://ses_123) use /swiftui-specialist [Skill Path](.agents/skills/swiftui-specialist/SKILL.md) ")
    }

    @Test func editingInsideMentionDropsItsTargetButKeepsOtherMentions() {
        var state = ComposerMentionState()
        var text = "@one @two"
        (text, _) = state.insert("@first", kind: .session(id: "first", title: "First"),
                                 replacing: text.range(of: "@one")!, in: text)
        (text, _) = state.insert("@second", kind: .session(id: "second", title: "Second"),
                                 replacing: text.range(of: "@two")!, in: text)
        text = text.replacingOccurrences(of: "first", with: "firzt")
        state.reconcile(text)
        #expect(state.expanded(text).contains("@firzt"))
        #expect(state.expanded(text).contains("[@Second](session://second)"))
        #expect(!state.expanded(text).contains("session://first"))
    }

    @Test func backspaceDeletesEntireSkillAndKeepsFollowingSession() {
        var state = ComposerMentionState()
        var text = "🐈 "
        (text, _) = state.insert("$review", kind: .skill(token: "review", path: "/skills/review"),
                                 replacing: text.endIndex..<text.endIndex, in: text)
        (text, _) = state.insert("@second", kind: .session(id: "second", title: "Second"),
                                 replacing: text.endIndex..<text.endIndex, in: text)
        let edit = state.edit(text.replacingOccurrences(of: "$review", with: "$revie"))
        #expect(edit.text == "🐈  @second ")
        #expect(edit.caret == "🐈 ".utf16.count)
        #expect(state.expanded(edit.text) == "🐈  [@Second](session://second) ")
    }

    @Test func deletingInsideSessionRemovesWholeReference() {
        var state = ComposerMentionState()
        var text = "Before "
        (text, _) = state.insert("@聊天🐈", kind: .session(id: "chat", title: "聊天🐈"),
                                 replacing: text.endIndex..<text.endIndex, in: text)
        let edit = state.edit(text.replacingOccurrences(of: "聊", with: ""))
        #expect(edit.text == "Before  ")
        #expect(state.ranges.isEmpty)
        #expect(state.expanded(edit.text) == edit.text)
    }

    @Test func ordinaryBackspaceDoesNotDeleteAdjacentMention() {
        var state = ComposerMentionState()
        var text = ""
        (text, _) = state.insert("@chat", kind: .session(id: "chat", title: "Chat"),
                                 replacing: text.startIndex..<text.endIndex, in: text)
        let space = state.edit(String(text.dropLast()))
        #expect(space.text == "@chat")
        #expect(state.ranges.count == 1)
        let token = state.edit(String(space.text.dropLast()))
        #expect(token.text.isEmpty)
        #expect(state.ranges.isEmpty)
    }

    @Test func selectionDeletionExpandsAcrossTwoMentions() {
        var state = ComposerMentionState()
        var text = ""
        (text, _) = state.insert("@first", kind: .session(id: "first", title: "First"),
                                 replacing: text.endIndex..<text.endIndex, in: text)
        (text, _) = state.insert("$review", kind: .skill(token: "review", path: "/review"),
                                 replacing: text.endIndex..<text.endIndex, in: text)
        let edit = state.edit("@fiew ")
        #expect(edit.text == " ")
        #expect(state.ranges.isEmpty)
    }

    @Test func skillMentionsFollowTheSourceAndDropWhatItLost() {
        var state = ComposerMentionState()
        var text = "Ask "
        (text, _) = state.insert("$review", kind: .skill(token: "review", path: ".claude/skills/review/SKILL.md"),
                                 replacing: text.endIndex..<text.endIndex, in: text)
        (text, _) = state.insert("@chat", kind: .session(id: "chat", title: "Chat"),
                                 replacing: text.endIndex..<text.endIndex, in: text)
        // The same token in another project expands through that project's path.
        let moved = state.resolveSkills([MentionSkill(token: "review", name: "Review", description: "",
                                                     path: ".agents/skills/review/SKILL.md")], in: text)
        #expect(moved == nil)
        #expect(state.expanded(text) ==
                "Ask use /review [Skill Path](.agents/skills/review/SKILL.md) [@Chat](session://chat) ")
        // A skill the new source does not offer leaves the text along with its
        // token, while the session mention survives.
        let rewritten = state.resolveSkills([], in: text)
        #expect(rewritten == "Ask @chat ")
        #expect(rewritten.map(state.expanded) == "Ask [@Chat](session://chat) ")
    }

    @Test func queryUsesCaretBeforeTrailingText() {
        let text = "Please @rev later"
        let caret = text.range(of: "@rev")!.upperBound
        let query = ComposerMentionQuery.active(in: text, selection: TextSelection(insertionPoint: caret))
        #expect(query?.trigger == .combined)
        #expect(query?.term == "rev")
        #expect(query.map { String(text[$0.range]) } == "@rev")
    }

    @Test func staleSelectionFallsBackToCurrentDraftEnd() {
        let previousDraft = "A longer draft 🐈 @review"
        let staleSelection = TextSelection(insertionPoint: previousDraft.endIndex)
        #expect(ComposerMentionQuery.active(in: "", selection: staleSelection) == nil)
        let text = "🐈 $swift"
        let query = ComposerMentionQuery.active(in: text, selection: staleSelection)
        #expect(query?.trigger == .skill)
        #expect(query?.term == "swift")
    }

    @Test func unicodeBeforeMentionKeepsRangeAligned() {
        var state = ComposerMentionState()
        var text = "🐈 @review"
        (text, _) = state.insert("@review", kind: .session(id: "ses_1", title: "Review"),
                                 replacing: text.range(of: "@review")!, in: text)
        #expect(state.expanded(text) == "🐈 [@Review](session://ses_1) ")
    }
}

@MainActor
@Observable
private final class MentionLoadProbe {
    var phase = ScenePhase.active
    var starts = 0
    var skillStarts = 0
    var cancellations = 0
    var completions = 0

    func load(isSkill: Bool) async throws {
        starts += 1
        if isSkill { skillStarts += 1 }
        if starts == 1 {
            do { try await Task.sleep(for: .seconds(30)) }
            catch {
                cancellations += 1
                // Network cancellation need not arrive as CancellationError.
                throw URLError(.cancelled)
            }
        }
        completions += 1
    }
}

private struct MentionLifecycleHarness: View {
    let probe: MentionLoadProbe
    @State private var draft: String
    @State private var mentions = ComposerMentionState()
    @State private var attachments: [ComposerAttachment] = []

    init(probe: MentionLoadProbe, draft: String) {
        self.probe = probe
        _draft = State(initialValue: draft)
    }

    var body: some View {
        SessionComposer(draft: $draft, mentions: $mentions, attachments: $attachments,
                        isSending: false, isCancelling: false, isSessionRunning: false,
                        supportsTextSending: true, supportsTextSendingWhileRunning: false,
                        supportsSessionCancellation: false, runConfig: nil, focusesOnAppear: true,
                        loadMentionSessions: { try await probe.load(isSkill: false); return [] },
                        loadMentionSkills: { try await probe.load(isSkill: true); return [] },
                        onSend: { false }, onCancel: {}, onChooseRunConfig: { _, _ in })
            .environment(\.scenePhase, probe.phase)
    }
}

@MainActor
private func waitForMentionLoad(probe: MentionLoadProbe, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition(), "starts: \(probe.starts), skills: \(probe.skillStarts), cancellations: \(probe.cancellations), completions: \(probe.completions)")
}
