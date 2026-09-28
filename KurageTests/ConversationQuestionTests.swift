import Foundation
import Testing
@testable import Kurage

@MainActor
struct ConversationQuestionTests {
    private func fixture() throws -> ConversationQuestionRequest {
        try #require(SessionRecord.questionSample.questions.first)
    }

    @Test func questionAnswersEncodeProviderScalarAndArrayValues() throws {
        let answers: [String: QuestionAnswer] = ["text": .text("my answer"), "multiple": .choices(["A", "B"])]
        let data = try JSONEncoder().encode(answers)
        let decoded = try JSONDecoder().decode([String: QuestionAnswer].self, from: data)
        #expect(decoded == answers)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["text"] as? String == "my answer")
        #expect(json["multiple"] as? [String] == ["A", "B"])
    }

    @Test func draftRequiresAnAnswerAndCustomTextTakesPrecedence() throws {
        var question = try fixture().questions[0]
        #expect(QuestionDraft().answer(for: question) == nil)
        #expect(QuestionDraft(text: "  \n ").answer(for: question) == nil)
        #expect(QuestionDraft(selected: ["A"], text: " Custom ").answer(for: question) == .text("Custom"))
        question.multiSelect = true
        #expect(QuestionDraft(selected: ["A", "B"]).answer(for: question) == .choices(["A", "B"]))
        question.allowCustomAnswer = false
        #expect(QuestionDraft(text: "Custom").answer(for: question) == nil)
    }

    @Test func pendingQuestionsSurviveCacheAndAreRemovedByPatch() throws {
        let request = try fixture()
        let previous = Conversation(sessionID: "chat", turns: [], permission: nil, questions: [request])
        #expect(try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(previous)) == previous)
        let data = Data(#"{"sessionID":"chat","order":[],"changed":[],"permission":null,"questions":[],"activity":"running","syncState":"live"}"#.utf8)
        let patch = try JSONDecoder().decode(ConversationPatch.self, from: data)
        #expect(try patch.applying(to: previous).conversation.questions == [])
        let old = Data(#"{"sessionID":"chat","turns":[],"permission":null}"#.utf8)
        #expect(try JSONDecoder().decode(Conversation.self, from: old).questions == nil)
    }

    @Test func fixtureAnswersUseWorkspaceAndRequestIdentity() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, records: [SessionRecord.questionSample])
        let request = try fixture()
        await #expect(throws: LodyClientError.notConnected) {
            try await client.respondToQuestion(request, answers: nil, sessionID: "session-question", workspaceID: "foreign")
        }
        #expect(try await client.conversation(sessionID: "session-question", workspaceID: "ws-demo").questions?.count == 1)
        try await client.respondToQuestion(request, answers: ["session": .text("demo"), "preview": .text("Code diff")],
                                          sessionID: "session-question", workspaceID: "ws-demo")
        #expect(try await client.conversation(sessionID: "session-question", workspaceID: "ws-demo").questions == [])
        await #expect(throws: LodyClientError.permissionMissing) {
            try await client.respondToQuestion(request, answers: nil, sessionID: "session-question", workspaceID: "ws-demo")
        }
    }

    @Test func modelRejectsOldWorkspaceBeforeSubmitting() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, records: [SessionRecord.questionSample])
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let request = try fixture()
        await #expect(throws: CancellationError.self) {
            try await model.respondToQuestion(request, answers: nil, sessionID: "session-question",
                                              workspaceGeneration: model.workspaceGeneration - 1)
        }
        #expect(try await client.conversation(sessionID: "session-question", workspaceID: "ws-demo").questions?.count == 1)
        try await model.respondToQuestion(request, answers: nil, sessionID: "session-question",
                                          workspaceGeneration: model.workspaceGeneration)
        #expect(try await client.conversation(sessionID: "session-question", workspaceID: "ws-demo").questions == [])
    }
}
