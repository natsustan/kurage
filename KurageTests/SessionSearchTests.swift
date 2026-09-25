import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Kurage

struct SessionSearchTests {
    @Test func indexesEachTextPartOnceAndKeepsLegacyText() {
        let turns = [
            ConversationTurn(id: "legacy", author: .user, text: "Legacy"),
            ConversationTurn(id: "parts", author: .agent, text: "A\n\nB", parts: [
                .text("A"), .image(ConversationImage(imageID: "shot", mimeType: "image/png")), .text("B"),
            ]),
        ]
        #expect(SessionSearch.bodyText(turns) == "Legacy\nA\nB")
    }

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

@MainActor
struct SessionSearchLifecycleTests {
    @Test(.timeLimit(.minutes(1))) func streamingDefersSearchProjectionUntilSearchResumes() async throws {
        let client = SearchLifecycleClient()
        client.immediateReads = true
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        await model.indexSessionsForSearch()
        model.stopSessionSearch()
        let original = model.sessionSearchBody(sessionID: "session-pr")
        let reads = client.readCount
        let (processed, signal) = AsyncStream<Void>.makeStream()
        var updates = processed.makeAsyncIterator()
        let observation = Task {
            try await model.observeConversation(sessionID: "session-pr") { _ in signal.yield(()) }
        }
        var events = client.events.makeAsyncIterator()
        while await events.next() != "observe" {}
        for text in ["first streaming text", "latest streaming text"] {
            client.observation?.yield(ConversationUpdate(
                conversation: Conversation(sessionID: "session-pr", turns: [
                    ConversationTurn(id: "turn", author: .agent, text: text),
                ], permission: nil), activity: .running, syncState: .live
            ))
            _ = await updates.next()
            #expect(model.sessionSearchBody(sessionID: "session-pr") == original)
        }
        observation.cancel()
        _ = await observation.result
        await model.indexSessionsForSearch()
        #expect(model.sessionSearchBody(sessionID: "session-pr") == "latest streaming text")
        #expect(client.readCount == reads)
    }

    @Test func successfulArchiveRefreshClearsOnlyTheLoadError() async {
        let client = SearchLifecycleClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        client.failArchiveLoad = true
        await model.refreshArchivedSessions()
        #expect(model.archiveStatusNote?.text == "Could not load archived sessions.")
        client.failArchiveLoad = false
        await model.refreshArchivedSessions()
        #expect(!model.archivedSessions.isEmpty)
        #expect(model.archiveStatusNote == nil)
        await model.restoreArchivedSession("archived-newer")
        let operationError = model.archiveStatusNote
        #expect(operationError != nil)
        await model.refreshArchivedSessions()
        #expect(model.archiveStatusNote == operationError)
    }

    @Test(.timeLimit(.minutes(1))) func backgroundCancelsReadsAndForegroundResumes() async {
        let client = SearchLifecycleClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        var events = client.events.makeAsyncIterator()
        let indexing = Task { await model.indexSessionsForSearch() }
        #expect(await events.next() == "read")
        model.setApplicationActive(false)
        #expect(await events.next() == "cancelled")
        await indexing.value
        await model.indexSessionsForSearch()
        #expect(client.readCount == 1)
        #expect(!model.isIndexingSessionSearch)
        model.setApplicationActive(true)
        #expect(await events.next() == "read")
        model.stopSessionSearch()
        #expect(await events.next() == "cancelled")
        #expect(client.readCount == 2)
    }

    @Test(.timeLimit(.minutes(1))) func endingObservationInBackgroundDoesNotRestartSearch() async throws {
        let client = SearchLifecycleClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        var events = client.events.makeAsyncIterator()
        let observation = Task { try await model.observeConversation(sessionID: "session-pr") { _ in } }
        #expect(await events.next() == "observe")
        await model.indexSessionsForSearch()
        model.setApplicationActive(false)
        observation.cancel()
        _ = await observation.result
        await model.indexSessionsForSearch()
        #expect(client.readCount == 0)
        #expect(!model.isIndexingSessionSearch)
        model.setApplicationActive(true)
        #expect(await events.next() == "read")
        model.stopSessionSearch()
        #expect(await events.next() == "cancelled")
    }
}

@MainActor
private final class SearchLifecycleClient: LodyClient {
    private let fixture = FixtureLodyClient(startsSignedIn: true)
    var account: Account? { fixture.account }
    let supportsConversations = true
    private(set) var readCount = 0
    private(set) var sessionReadCount = 0
    var emptySessions = false
    var immediateReads = false
    var failArchiveLoad = false
    var observation: AsyncThrowingStream<ConversationUpdate, Error>.Continuation?
    let events: AsyncStream<String>
    private let signal: AsyncStream<String>.Continuation

    init() { (events, signal) = AsyncStream.makeStream() }
    func beginDeviceAuthorization() async throws -> DeviceAuthorization { try await fixture.beginDeviceAuthorization() }
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws {
        try await fixture.finishDeviceAuthorization(authorization)
    }
    func restoreSession() async -> Account? { account }
    func signOut() { fixture.signOut() }
    func workspaces() async throws -> [WorkspaceSummary] { try await fixture.workspaces() }
    func sessions(workspaceID: String) async throws -> [SessionSummary] {
        sessionReadCount += 1
        return emptySessions ? [] : try await fixture.sessions(workspaceID: workspaceID)
    }
    func conversation(sessionID: String, workspaceID: String) async throws -> Conversation {
        readCount += 1
        if immediateReads { return try await fixture.conversation(sessionID: sessionID, workspaceID: workspaceID) }
        signal.yield("read")
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            signal.yield("cancelled")
            throw error
        }
        return try await fixture.conversation(sessionID: sessionID, workspaceID: workspaceID)
    }
    func observeConversation(sessionID: String, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error> {
        let (stream, continuation) = AsyncThrowingStream<ConversationUpdate, Error>.makeStream()
        observation = continuation
        signal.yield("observe")
        return stream
    }
    func send(_ text: String, runConfig: RunConfigChoice?, sessionID: String, workspaceID: String) async throws {}
    func cancelSession(sessionID: String, workspaceID: String) async throws {}
    func archivedSessions(workspaceID: String) async throws -> [ArchivedSessionSummary] {
        if failArchiveLoad { throw LodyClientError.unreachable }
        return try await fixture.archivedSessions(workspaceID: workspaceID)
    }

    func respond(_ decision: PermissionDecision, requestID: String, sessionID: String, workspaceID: String) async throws {}
}

@MainActor
struct SessionListRefreshTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func pullingToRefreshReloadsSessions(empty: Bool) async throws {
        let client = SearchLifecycleClient()
        client.emptySessions = empty
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let initialReads = client.sessionReadCount
        let host = UIHostingController(rootView: SessionListView(model: model))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<50 {
            window.layoutIfNeeded()
            if refreshControl(in: host.view) != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let control = try #require(refreshControl(in: host.view))
        control.beginRefreshing()
        control.sendActions(for: .valueChanged)
        for _ in 0..<50 {
            if client.sessionReadCount > initialReads && !control.isRefreshing { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(client.sessionReadCount == initialReads + 1)
        #expect(!control.isRefreshing)
    }

    private func refreshControl(in view: UIView) -> UIRefreshControl? {
        if let control = view as? UIRefreshControl { return control }
        if let control = (view as? UIScrollView)?.refreshControl { return control }
        return view.subviews.lazy.compactMap { refreshControl(in: $0) }.first
    }
}
