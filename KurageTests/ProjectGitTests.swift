import Foundation
import Testing
@testable import Kurage

@MainActor
struct ProjectGitTests {
    @Test func branchLabelsDecodeSelectorsWithoutChangingIdentity() {
        let local = ProjectBranch(id: "lody:branch:local:feature%2Fclient")
        #expect(local.name == "feature/client")
        #expect(local.id == "lody:branch:local:feature%2Fclient")
        #expect(ProjectBranch(id: "lody:branch:remote:origin:feature%2Fclient").name == "origin/feature/client")
        #expect(ProjectBranch(id: "lody:branch:local:bad%ZZ").name == "bad%ZZ")
        #expect(ProjectBranch(id: "legacy-branch").name == "legacy-branch")
    }

    @Test func bridgeContractRepresentsNonGitDetachedAndReadFailure() throws {
        let nonGit = try JSONDecoder().decode(ProjectGitResult.self,
            from: Data(#"{"state":{"git":false}}"#.utf8))
        #expect(nonGit.state?.git == false)
        let detached = try JSONDecoder().decode(ProjectGitResult.self,
            from: Data(#"{"state":{"git":true,"currentBranch":null}}"#.utf8))
        #expect(detached.state?.branchName == "Detached HEAD")
        let denied = try JSONDecoder().decode(ProjectGitResult.self,
            from: Data(#"{"failure":"access_denied"}"#.utf8))
        #expect(denied.failure == .accessDenied)
    }

    @Test func fixtureReadsProjectsIndependentlyIncludingRunningSessions() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        client.projectGitStates["local:machine-1:prism"] = ProjectGitState(
            git: true, currentBranch: "lody:branch:local:feature%2Fclient")
        let snapshot = client.projectGitStates
        let result = try await client.projectGit(templateSessionID: "session-pr",
            projectID: "local:machine-1:prism", workspaceID: "ws-demo")
        #expect(result.state?.branchName == "feature/client")
        #expect(try await client.projectGit(templateSessionID: "session-long", projectID: "local:machine-1:kurage",
            workspaceID: "ws-demo").state?.branchName == "main")
        #expect(client.projectGitStates == snapshot)
        await #expect(throws: LodyClientError.notConnected) {
            try await client.projectGit(templateSessionID: "session-pr", projectID: "local:other:prism", workspaceID: "ws-demo")
        }
    }

    @Test(arguments: [ProjectGitFailure.unavailable, .unsupported, .accessDenied])
    func fixtureReadFailureCanBeRetried(failure: ProjectGitFailure) async throws {
        let client = FixtureLodyClient(startsSignedIn: true, projectGitFailureOnce: failure)
        let result = try await client.projectGit(templateSessionID: "session-pr",
            projectID: "local:machine-1:prism", workspaceID: "ws-demo")
        #expect(result.failure == failure)
        #expect(try await client.projectGit(templateSessionID: "session-pr", projectID: "local:machine-1:prism",
            workspaceID: "ws-demo").state?.branchName == "main")
    }

    @Test func cancelledFixtureReadDoesNotPublishState() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        client.projectGitDelay = .seconds(5)
        let task = Task { try await client.projectGit(templateSessionID: "session-pr", projectID: "local:machine-1:prism",
            workspaceID: "ws-demo") }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(client.projectGitStates.isEmpty)
    }

    @Test(arguments: [false, true]) func modelDiscardsGitResultsAfterWorkspaceOrAccountChanges(signOut: Bool) async throws {
        let client = DeferredGitClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let task = Task { try await model.projectGit(templateSessionID: "root", projectID: "local:machine:project") }
        var started = client.started.stream.makeAsyncIterator()
        _ = await started.next()
        #expect(client.requestedWorkspace == "a")
        if signOut { model.signOut() }
        else { await model.selectWorkspace("b") }
        client.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

@MainActor
private final class DeferredGitClient: LodyClient {
    var account: Account? = Account(email: "demo@example.com")
    let started = AsyncStream<Void>.makeStream()
    var requestedWorkspace: String?
    private var continuation: CheckedContinuation<ProjectGitResult, Never>?
    func finish() { continuation?.resume(returning: ProjectGitResult(failure: .unsupported)); continuation = nil }
    func projectGit(templateSessionID: String, projectID: String, workspaceID: String) async throws -> ProjectGitResult {
        requestedWorkspace = workspaceID
        return await withCheckedContinuation { continuation = $0; started.continuation.yield(()) }
    }
    func restoreSession() async -> Account? { account }
    func signOut() { account = nil }
    func beginDeviceAuthorization() async throws -> DeviceAuthorization { throw LodyClientError.notConnected }
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws {}
    func workspaces() async throws -> [WorkspaceSummary] {
        [.init(id: "a", name: "A", slug: "a"), .init(id: "b", name: "B", slug: "b")]
    }
    func sessions(workspaceID: String) async throws -> [SessionSummary] { [] }
    func conversation(sessionID: String, workspaceID: String) async throws -> Conversation { throw LodyClientError.sessionMissing }
    func send(_ text: String, attachments: [ComposerAttachment], runConfig: RunConfigChoice?, turnID: String,
              sessionID: String, workspaceID: String) async throws -> RunConfigChoice? { throw LodyClientError.notConnected }
    func cancelSession(sessionID: String, workspaceID: String) async throws {}
    func respond(_ decision: PermissionDecision, requestID: String, sessionID: String, workspaceID: String) async throws {}
}
