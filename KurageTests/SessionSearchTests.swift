import Foundation
import Testing
@testable import Kurage

struct SessionSearchTests {
    @Test func matchesTitleWithoutASnippet() {
        let result = SessionSearch.result(title: "Fix flaky tests", body: "Running npm test", query: "  FLAKY ")
        #expect(result == SessionSearch.Result(snippet: nil))
    }

    @Test func matchesTranscriptLineAndIgnoresCaseAndDiacritics() {
        let body = "Question 1\nQuestion 7\nThe café is open"
        #expect(SessionSearch.result(title: "long conversation", body: body, query: "question 7")?.snippet == "Question 7")
        #expect(SessionSearch.result(title: "Notes", body: body, query: "cafe")?.snippet == "The café is open")
        #expect(SessionSearch.result(title: "修复测试", body: "运行 npm test", query: "npm")?.snippet == "运行 npm test")
    }

    @Test func rejectsBlankQueriesAndUnrelatedSessions() {
        #expect(SessionSearch.result(title: "fix flaky tests", body: "Running npm test", query: "   ") == nil)
        #expect(SessionSearch.result(title: "review the PR", body: "Look at this PR", query: "Question 7") == nil)
    }

    @Test func windowsALongMatchingLine() {
        let line = String(repeating: "a", count: 100) + "needle" + String(repeating: "b", count: 100)
        let snippet = SessionSearch.result(title: "t", body: line, query: "needle")?.snippet
        #expect(snippet?.contains("needle") == true)
        #expect(snippet?.hasPrefix("…") == true)
        #expect(snippet?.hasSuffix("…") == true)
        #expect((snippet?.count ?? 0) <= 82)
    }
}

@MainActor
struct SessionSearchIndexTests {
    @Test func indexesTurnTextSeparatelyPerSession() async {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()
        await model.indexSessionsForSearch()

        #expect(model.sessionSearchBody(sessionID: "session-long").contains("Question 7"))
        #expect(model.sessionSearchBody(sessionID: "session-tests").contains("Running npm test"))
        #expect(!model.sessionSearchBody(sessionID: "session-pr").contains("Question 7"))
        #expect(!model.isIndexingSessionSearch)
    }

    @Test func reloadsTranscriptsAfterTheSessionListRefreshes() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()
        await model.indexSessionsForSearch()

        try await model.send("unique-needle", sessionID: "session-pr")
        await model.indexSessionsForSearch()

        let body = model.sessionSearchBody(sessionID: "session-pr")
        #expect(body.contains("unique-needle"))
        #expect(body.contains("Look at this PR"))
        #expect(model.sessionSearchBody(sessionID: "session-long").contains("Question 7"))
    }

    @Test func signOutDropsSearchText() async {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()
        await model.indexSessionsForSearch()
        model.signOut()
        #expect(model.sessionSearchBody(sessionID: "session-long").isEmpty)
        #expect(!model.isIndexingSessionSearch)
    }
}
