import Foundation
import Testing
@testable import Kurage

@MainActor
struct ProjectGitTests {
    @Test func branchLabelsDecodeSelectorsWithoutChangingIdentity() {
        let local = ProjectBranch(id: "lody:branch:local:feature%2Fclient")
        #expect(local.name == "feature/client")
        #expect(local.id == "lody:branch:local:feature%2Fclient")
        #expect(!local.isRemote)
        #expect(ProjectBranch(id: "lody:branch:remote:origin:feature%2Fclient").name == "origin/feature/client")
        #expect(ProjectBranch(id: "lody:branch:local:bad%ZZ").name == "bad%ZZ")
        #expect(ProjectBranch(id: "legacy-branch").name == "legacy-branch")
    }

    @Test func bridgeContractRepresentsNonGitDetachedAndUnconfirmedSwitch() throws {
        let nonGit = try JSONDecoder().decode(ProjectGitResult.self,
            from: Data(#"{"state":{"git":false,"branches":[],"busy":false}}"#.utf8))
        #expect(nonGit.state?.git == false)
        #expect(nonGit.state?.canSwitch == false)
        let uncertain = try JSONDecoder().decode(ProjectGitResult.self, from: Data(#"{"state":{"git":true,"currentBranch":null,"branches":["lody:branch:local:main"],"busy":false,"observedAtMs":1,"workingTree":{"clean":true,"staged":false,"unstaged":false,"untracked":false,"conflicted":false}},"failure":"switch_unconfirmed"}"#.utf8))
        #expect(uncertain.state?.branchName == "Detached HEAD")
        #expect(uncertain.failure == .switchUnconfirmed)
    }

    @Test func fixtureSwitchPreservesProjectIsolationAndRefreshesRemoteCheckout() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let project = "local:machine-1:prism"
        let template = "session-pr"
        let feature = "lody:branch:local:feature%2Fclient"
        let changed = try await client.projectGit(templateSessionID: template, projectID: project, branch: feature, workspaceID: "ws-demo")
        #expect(changed.state?.branchName == "feature/client")
        #expect(try await client.projectGit(templateSessionID: "session-long", projectID: "local:machine-1:kurage",
            branch: nil, workspaceID: "ws-demo").state?.branchName == "main")
        let remote = try await client.projectGit(templateSessionID: template, projectID: project,
            branch: "lody:branch:remote:origin:develop", workspaceID: "ws-demo")
        #expect(remote.state?.currentBranch == "lody:branch:local:develop")
        #expect(remote.state?.branches.contains("lody:branch:local:develop") == true)
        await #expect(throws: LodyClientError.notConnected) {
            try await client.projectGit(templateSessionID: template, projectID: "local:other:prism", branch: feature, workspaceID: "ws-demo")
        }
    }

    @Test func localChangesAndRunningSessionsRejectCheckout() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let feature = "lody:branch:local:feature%2Fclient"
        var dirty = try #require(try await client.projectGit(templateSessionID: "session-pr",
            projectID: "local:machine-1:prism", branch: nil, workspaceID: "ws-demo").state)
        dirty.workingTree?.clean = false
        dirty.workingTree?.untracked = true
        client.projectGitStates["local:machine-1:prism"] = dirty
        let refused = try await client.projectGit(templateSessionID: "session-pr", projectID: "local:machine-1:prism",
                                                  branch: feature, workspaceID: "ws-demo")
        #expect(refused.failure == .localChanges)
        #expect(refused.state?.branchName == "main")
        #expect(try await client.projectGit(templateSessionID: "session-long", projectID: "local:machine-1:kurage",
            branch: feature, workspaceID: "ws-demo").failure == .busy)
    }

    @Test func cancelledFixtureCheckoutDoesNotChangeBranch() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        client.projectGitDelay = .seconds(5)
        let task = Task { try await client.projectGit(templateSessionID: "session-pr", projectID: "local:machine-1:prism",
            branch: "lody:branch:local:feature%2Fclient", workspaceID: "ws-demo") }
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

    @Test func unconfirmedTabStartPreventsSharedProjectCheckout() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        _ = try model.stageSessionStart("Start a tab", composerText: "Start a tab", mentions: .init(),
            attachments: [], agentConfigID: nil, selections: [],
            projectID: "local:machine-1:prism", projectName: "prism", templateSessionID: "session-pr", parentSessionID: "session-pr")
        let result = try await model.projectGit(templateSessionID: "session-pr", projectID: "local:machine-1:prism",
            branch: "lody:branch:local:feature%2Fclient")
        #expect(result.failure == .busy)
        #expect(client.projectGitStates.isEmpty)
    }
}

@MainActor
private final class DeferredGitClient: LodyClient {
    var account: Account? = Account(email: "demo@example.com")
    let started = AsyncStream<Void>.makeStream()
    var requestedWorkspace: String?
    private var continuation: CheckedContinuation<ProjectGitResult, Never>?
    func finish() { continuation?.resume(returning: ProjectGitResult(failure: .unsupported)); continuation = nil }
    func projectGit(templateSessionID: String, projectID: String, branch: String?, workspaceID: String) async throws -> ProjectGitResult {
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
