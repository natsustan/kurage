import Foundation
import SwiftUI
import Testing
@testable import Kurage

struct ComposerMentionsTests {
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
