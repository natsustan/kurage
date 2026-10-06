import Foundation
import Testing
@testable import Kurage

struct ConversationErrorTests {
    @Test func errorOnlyPatchPreservesRawMessageAndCanReplaceOrRemoveIt() throws {
        let error = ConversationError(id: "notice-0", reason: "acp_internal_error",
                                      message: #"Internal error: API Error: 400 {"error":{"message":"Sample model unavailable"},"status":400}"#)
        let turn = ConversationTurn(id: "a", author: .agent, text: "", parts: [.error(error)])
        let encoded = try JSONEncoder().encode(turn)
        #expect(try JSONDecoder().decode(ConversationTurn.self, from: encoded) == turn)
        let payload: [String: Any] = ["sessionID": "s", "order": ["a"], "changed": [
            try JSONSerialization.jsonObject(with: encoded),
        ], "permission": NSNull(), "activity": "idle", "syncState": "live"]
        let patch = try JSONDecoder().decode(ConversationPatch.self, from: JSONSerialization.data(withJSONObject: payload))
        let conversation = try patch.applying(to: Conversation(sessionID: "s", turns: [], permission: nil)).conversation
        #expect(conversation.turns.first?.content == [.error(error)])

        let completed = try JSONDecoder().decode(ConversationPatch.self, from: Data(#"{"sessionID":"s","order":["a"],"changed":[{"id":"a","author":"agent","text":"Recovered"}],"permission":null,"activity":"idle","syncState":"live"}"#.utf8))
        #expect(try completed.applying(to: conversation).conversation.turns.first?.content == [.text("Recovered")])
        let removed = try JSONDecoder().decode(ConversationPatch.self, from: Data(#"{"sessionID":"s","order":[],"changed":[],"permission":null,"activity":"idle","syncState":"live"}"#.utf8))
        #expect(try removed.applying(to: conversation).conversation.turns.isEmpty == true)
    }

    @Test func readableMessagesExtractNestedAndFlatJSONAndKeepCopyVerbatim() {
        for raw in [#"Internal error: API Error: 400 {"error":{"message":"Missing \"messages\" parameter"}}"#,
                    #"{"message":"Missing \"messages\" parameter"}"#] {
            let error = ConversationError(id: "notice", reason: "acp_internal_error", message: raw)
            #expect(error.readableMessage == "Missing \"messages\" parameter")
            #expect(error.report == "Error: Agent internal error\nReason: acp_internal_error\n\n" + raw)
        }
        let raw = "  Internal error: API Error: 500 Invalid JSON {\nDiagnostic tail\n  "
        let error = ConversationError(id: "notice", message: raw)
        #expect(error.readableMessage == "Invalid JSON {\nDiagnostic tail")
        #expect(error.report.hasSuffix(raw))
        #expect(ConversationError(id: "notice", message: " \n").readableMessage == nil)
    }

    @Test func reasonsAndUnknownMetadataHaveReadableFallbacks() {
        #expect(String(localized: ConversationError(id: "a", reason: "acp_auth_required").title) == "Authentication required")
        #expect(String(localized: ConversationError(id: "a", reason: "future_reason").title) == "Failed to process message")
        #expect(ConversationError(id: "a", reason: "future_reason", code: "future_code").report ==
                "Error: Failed to process message\nReason: future_reason\nCode: future_code")
        #expect(String(localized: ConversationError(id: "a", reason: "session_init_failed", code: "git_executable_not_found").title) ==
                "Git executable was not found on the target machine")
    }

    @Test func malformedErrorPartsAreDroppedWithoutDroppingOtherContent() throws {
        let decoded = try JSONDecoder().decode(ConversationTurn.self, from: Data(#"{"id":"a","author":"agent","parts":[{"type":"error"},{"type":"error","id":""},{"type":"error","id":"bad","message":42},{"type":"error","id":"fallback"},{"type":"future","message":"hidden"},{"type":"text","text":"Visible"}]}"#.utf8))
        #expect(decoded.content == [.error(ConversationError(id: "fallback")), .text("Visible")])
    }

    @Test func errorBlocksPreserveOrderAndIdentityAndAreNotUserContent() {
        let error = ConversationError(id: "notice-1", reason: "acp_internal_error", message: "Failed")
        #expect(conversationBlocks(author: .agent, content: [.text("Before"), .error(error), .text("After")]) ==
                [.text(id: "text-0", text: "Before"), .error(error), .text(id: "text-2", text: "After")])
        #expect(ConversationBlock.error(error).id == "error-notice-1")
        #expect(conversationBlocks(author: .user, content: [.error(error)]).isEmpty)
    }
}
