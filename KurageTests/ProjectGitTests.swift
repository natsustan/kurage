import Foundation
import Testing
@testable import Kurage
@testable import KurageCore

@MainActor
struct ProjectGitTests {
    @Test func branchLabelsDecodeSelectorsWithoutChangingIdentity() {
        let local = ProjectBranch(id: "lody:branch:local:feature%2Fclient")
        #expect(local.name == "feature/client")
        #expect(local.id == "lody:branch:local:feature%2Fclient")
        #expect(ProjectBranch(id: "lody:branch:remote:origin:feature%2Fclient").name == "origin/feature/client")
        #expect(ProjectBranch(id: "lody:branch:local:bad%ZZ").name == "bad%ZZ")
        #expect(ProjectBranch(id: "legacy-branch").name == "legacy-branch")
        #expect(ProjectBranch(id: "lody:branch:remote:origin:feature%2Fclient").localName == local.localName)
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
        let detailed = try JSONDecoder().decode(ProjectGitResult.self, from: Data(#"""
            {"state": {
                "git": true, "currentBranch": "lody:branch:local:feature%2Fclient",
                "defaultBranch": "lody:branch:local:main", "githubRepoFullName": "demo/prism",
                "workingTree": {"clean": true, "staged": false, "unstaged": false, "untracked": false, "conflicted": false},
                "hasUnpushedCommits": true, "hasBranchChanges": true, "hasOpenPR": false,
                "sessionDirectoryMatchesProject": true
            }}
            """#.utf8))
        #expect(detailed.state?.workingTree?.clean == true)
        #expect(detailed.state?.hasUnpushedCommits == true)
        #expect(QuickActionAvailability(state: try #require(detailed.state)).primaryActions == [.reviewChanges, .push, .createPR])
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

    @Test(arguments: ["background", "cancel", "workspace", "account", "project"])
    func inFlightGitActionCannotStageAfterItsContextChanges(change: String) async throws {
        let client = DeferredGitClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let generation = model.workspaceGeneration
        let options = NewSessionOptions(machineName: "Mac", agentConfigID: "codex", providers: [])
        let task = Task {
            try await model.stageQuickAction(.createBranch, rootID: "root", options: options,
                                            runConfig: nil, workspaceGeneration: generation)
        }
        var started = client.started.stream.makeAsyncIterator()
        _ = await started.next()
        switch change {
        case "background": model.setApplicationActive(false)
        case "cancel": task.cancel()
        case "workspace": await model.selectWorkspace("b")
        case "account": model.signOut()
        case "project":
            client.projectID = "local:machine:other"
            await model.refreshContent()
        default: Issue.record("Unknown change")
        }
        client.finish(result: ProjectGitResult(state: ProjectGitState(git: true,
            currentBranch: "lody:branch:local:main", defaultBranch: "lody:branch:local:main",
            workingTree: ProjectWorkingTree(clean: true), sessionDirectoryMatchesProject: true)))
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(model.pendingSessionTab(rootID: "root") == nil)
    }
}

@MainActor
private final class DeferredGitClient: LodyClient {
    var account: Account? = Account(email: "demo@example.com")
    let started = AsyncStream<Void>.makeStream()
    var requestedWorkspace: String?
    var projectID = "local:machine:project"
    var supportsSessionTabs: Bool { true }
    var supportsSessionCreation: Bool { true }
    private var continuation: CheckedContinuation<ProjectGitResult, Never>?
    func finish(result: ProjectGitResult = ProjectGitResult(failure: .unsupported)) {
        continuation?.resume(returning: result)
        continuation = nil
    }
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
    func sessions(workspaceID: String) async throws -> [SessionSummary] {
        [SessionSummary(id: "root", title: "Project", agentName: "codex", activity: .idle,
                        preview: "", projectID: projectID)]
    }
    func conversation(sessionID: String, workspaceID: String) async throws -> Conversation { throw LodyClientError.sessionMissing }
    func send(_ text: String, attachments: [ComposerAttachment], runConfig: RunConfigChoice?, turnID: String,
              sessionID: String, workspaceID: String) async throws -> RunConfigChoice? { throw LodyClientError.notConnected }
    func cancelSession(sessionID: String, workspaceID: String) async throws {}
    func respond(_ decision: PermissionDecision, requestID: String, sessionID: String, workspaceID: String) async throws {}
}
