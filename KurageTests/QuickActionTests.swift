import Foundation
import Testing
@testable import Kurage
@testable import KurageCore

@MainActor
struct QuickActionTests {
    private func state(for action: QuickAction) -> ProjectGitState {
        var state = ProjectGitState(git: true, currentBranch: "lody:branch:local:feature%2Fclient",
            defaultBranch: "lody:branch:local:main", githubRepoFullName: "demo/prism",
            workingTree: ProjectWorkingTree(clean: true), hasUnpushedCommits: true, hasBranchChanges: true,
            hasOpenPR: false, sessionDirectoryMatchesProject: true)
        switch action {
        case .createBranchAndCommit:
            state.currentBranch = state.defaultBranch
            state.workingTree = ProjectWorkingTree(clean: false, unstaged: true)
        case .commit, .commitAndPush, .reviewChanges:
            state.workingTree = ProjectWorkingTree(clean: false, untracked: true)
        default: break
        }
        return state
    }

    @Test(arguments: ["default-clean", "default-dirty", "feature-dirty", "unpublished", "existing-pr",
                      "synced", "synced-changes", "unknown-diff", "unknown-diff-existing-pr", "unknown-diff-pr-status",
                      "conflicted", "detached", "non-git", "unknown", "worktree", "remote-base"])
    func menuShowsOnlyContextualNextSteps(scenario: String) {
        var git = state(for: .push)
        var expected: [QuickAction] = []
        switch scenario {
        case "default-clean":
            git.currentBranch = git.defaultBranch
            expected = [.createBranch]
        case "default-dirty":
            git = state(for: .createBranchAndCommit)
            expected = [.reviewChanges, .createBranchAndCommit]
        case "feature-dirty":
            git = state(for: .commit)
            expected = [.reviewChanges, .commit]
        case "unpublished": expected = [.reviewChanges, .push, .createPR]
        case "existing-pr":
            git.hasOpenPR = true
            expected = [.reviewChanges, .push]
        case "synced":
            git.hasUnpushedCommits = false
            git.hasBranchChanges = false
        case "synced-changes":
            git.hasUnpushedCommits = false
            expected = [.reviewChanges, .createPR]
        case "unknown-diff":
            git.hasUnpushedCommits = false
            git.hasBranchChanges = nil
            expected = [.reviewChanges, .createPR]
        case "unknown-diff-existing-pr":
            git.hasBranchChanges = nil
            git.hasOpenPR = true
            expected = [.reviewChanges, .push]
        case "unknown-diff-pr-status":
            git.hasBranchChanges = nil
            git.hasOpenPR = nil
            expected = [.reviewChanges, .push]
        case "conflicted":
            git.workingTree = ProjectWorkingTree(clean: false, conflicted: true)
            expected = [.reviewChanges]
        case "detached":
            git.currentBranch = nil
            expected = [.createBranch]
        case "non-git": git.git = false
        case "unknown": git.workingTree = nil
        case "worktree": git.sessionDirectoryMatchesProject = false
        case "remote-base":
            git.currentBranch = "lody:branch:local:main"
            git.defaultBranch = "lody:branch:remote:origin:main"
            expected = [.createBranch]
        default: Issue.record("Unknown scenario")
        }
        let availability = QuickActionAvailability(state: git)
        #expect(availability.primaryActions == expected)
        #expect(availability.primaryActions.count <= 3)
        #expect(availability.allows(.commitAndPush) == (scenario == "feature-dirty"))
        #expect(availability.allows(.createDraftPR) == expected.contains(.createPR))
        if ["conflicted", "non-git", "unknown", "worktree"].contains(scenario) {
            #expect(!availability.allows(.createBranch))
        }
    }

    @Test(arguments: [QuickAction.reviewChanges, .createPR, .createDraftPR])
    func unknownBranchDiffCanStartATaskAfterTheGitRecheck(action: QuickAction) async throws {
        let client = FixtureLodyClient(startsSignedIn: true,
            projectGitStates: FixtureLodyClient.quickActionGitStates(arguments: ["--fixture-git-zero-lines"]))
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let rootID = "session-pr"
        #expect(try await model.quickActionAvailability(rootID: rootID).allows(action))
        let options = try await model.newSessionOptions(templateSessionID: rootID, isTab: true)
        let id = try await model.stageQuickAction(action, rootID: rootID, options: options,
            runConfig: options.runConfig, workspaceGeneration: model.workspaceGeneration)
        #expect(model.pendingSessionTab(rootID: rootID)?.sessionID == id)
        #expect(model.outgoingMessage(sessionID: id)?.text == action.prompt)
    }

    @Test func actionRechecksGitInsteadOfTrustingAnEarlierMenu() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        client.projectGitStates["local:machine-1:prism"] = state(for: .commit)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        #expect(try await model.quickActionAvailability(rootID: "session-pr").allows(.commit))
        client.projectGitStates["local:machine-1:prism"]?.workingTree = ProjectWorkingTree(clean: true)
        let options = try await model.newSessionOptions(templateSessionID: "session-pr", isTab: true)
        await #expect(throws: QuickActionFailure.stateChanged) {
            try await model.stageQuickAction(.commit, rootID: "session-pr", options: options,
                runConfig: options.runConfig, workspaceGeneration: model.workspaceGeneration)
        }
        #expect(model.pendingSessionTab(rootID: "session-pr") == nil)
    }

    @Test func unavailableGitCannotCreateATask() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, projectGitFailureOnce: .unsupported)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let options = try await model.newSessionOptions(templateSessionID: "session-pr", isTab: true)
        await #expect(throws: QuickActionFailure.gitUnavailable) {
            try await model.stageQuickAction(.createBranch, rootID: "session-pr", options: options,
                runConfig: options.runConfig, workspaceGeneration: model.workspaceGeneration)
        }
        #expect(model.pendingSessionTab(rootID: "session-pr") == nil)
    }

    @Test func nativeTabRequestCarriesItsTitleIDsAndFirstTurnChoicesToJavaScript() throws {
        let choices = [RunConfigChoice(configOptionID: nil, value: "gpt-5.4-mini"),
                       RunConfigChoice(configOptionID: "reasoning_effort", value: "low")]
        let request = SessionTabStart(text: QuickAction.commit.prompt, selections: choices,
                                      agentConfigID: "codex", title: "Commit")
        let value = try request.bridgeValue(attachments: [], parentSessionID: "root", userID: "user")
        let json = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: value)) as? [String: Any]
        #expect(json?["title"] as? String == "Commit")
        #expect(json?["templateSessionID"] as? String == "root")
        #expect(json?["parentSessionID"] as? String == "root")
        #expect(json?["sessionID"] as? String == request.sessionID)
        #expect(json?["turnID"] as? String == request.turnID)
        #expect(json?["agentConfigID"] as? String == "codex")
        #expect(json?["text"] as? String == QuickAction.commit.prompt)
        let selections = try #require(json?["selections"] as? [[String: Any]])
        #expect(selections.map { $0["value"] as? String } == ["gpt-5.4-mini", "low"])
        #expect(selections[0]["configOptionID"] is NSNull)
        #expect(selections[1]["configOptionID"] as? String == "reasoning_effort")
        let ordinary = try SessionTabStart(text: "Continue").bridgeValue(attachments: [], parentSessionID: "root", userID: "user")
        #expect(ordinary["title"] is NSNull)
    }

    @Test(arguments: QuickAction.allCases)
    func taskUsesANamedTabAndIndependentModelWithoutChangingParentHistory(action: QuickAction) async throws {
        let suite = "QuickActionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = FixtureLodyClient(startsSignedIn: true)
        client.projectGitStates["local:machine-1:prism"] = state(for: action)
        let model = AppModel(client: client, quickActionDefaults: defaults)
        await model.adoptExistingAccount()
        let rootID = "session-pr"
        let before = try await client.conversation(sessionID: rootID, workspaceID: "ws-demo")
        model.saveQuickActionPreference(.init(agentConfigID: "codex", modelID: "gpt-5.5", reasoning: "high"),
            rootID: rootID, profile: .review, workspaceGeneration: model.workspaceGeneration)
        model.saveQuickActionPreference(.init(agentConfigID: "codex", modelID: "gpt-5.4-mini", reasoning: "low"),
            rootID: rootID, profile: .git, workspaceGeneration: model.workspaceGeneration)
        let configuration = try await QuickActionConfigurationState.load(model: model, rootID: rootID, profile: action.profile)
        let options = try #require(configuration.options)
        let config = try #require(configuration.runConfig)
        let id = try await model.stageQuickAction(action, rootID: rootID, options: options,
            runConfig: config, workspaceGeneration: model.workspaceGeneration)
        #expect(model.sessionSummary(id)?.title == String(localized: action.title))
        #expect(model.sessionSummary(id)?.projectID == model.sessionSummary(rootID)?.projectID)
        #expect(model.sessionSummary(id)?.parentSessionID == rootID)
        #expect(!model.sessions.contains { $0.id == id })
        #expect(!model.shouldFocusSessionStartComposer(sessionID: id))
        try await model.deliverOutgoingMessage(sessionID: id)
        try await model.observeConversation(sessionID: id, rootSessionID: rootID) { update in
            #expect(update.conversation.turns.first?.text == action.prompt)
            #expect(update.runConfig?.model?.value == (action == .reviewChanges ? "gpt-5.5" : "gpt-5.4-mini"))
            #expect(update.runConfig?.reasoning?.value == (action == .reviewChanges ? "high" : "low"))
        }
        #expect(try await client.conversation(sessionID: rootID, workspaceID: "ws-demo") == before)
    }

    @Test func uncertainTaskRetryKeepsItsTabTurnTitleAndFirstConfiguration() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, failTabStartOnce: true)
        client.projectGitStates["local:machine-1:prism"] = state(for: .commit)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let options = try await model.newSessionOptions(templateSessionID: "session-pr", agentConfigID: "codex", isTab: true)
        var config = try #require(options.runConfig)
        config.selectModel("gpt-5.4-mini")
        config.selectReasoning("low")
        let id = try await model.stageQuickAction(.commit, rootID: "session-pr", options: options,
            runConfig: config, workspaceGeneration: model.workspaceGeneration)
        let pending = try #require(model.pendingSessionTab(rootID: "session-pr"))
        await #expect(throws: LodyClientError.deliveryUnconfirmed) { try await model.deliverOutgoingMessage(sessionID: id) }
        #expect(model.quickActionBlockingFailure(rootID: "session-pr") == .pending)
        #expect(model.retryOutgoingMessage(sessionID: id))
        try await model.deliverOutgoingMessage(sessionID: id)
        let conversation = try await client.conversation(sessionID: id, workspaceID: "ws-demo")
        #expect(conversation.turns.map(\.id) == [pending.turnID])
        #expect(model.sessionSummary(id)?.title == "Commit")
        try await model.observeConversation(sessionID: id, rootSessionID: "session-pr") { update in
            #expect(update.runConfig?.model?.value == "gpt-5.4-mini")
            #expect(update.runConfig?.reasoning?.value == "low")
        }
    }

    @Test func busyProjectsAndStaleWorkspaceCannotStageGitActions() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, workspaceSummaries: [
            WorkspaceSummary(id: "ws-demo", name: "Demo", slug: "demo"),
            WorkspaceSummary(id: "ws-studio", name: "Studio", slug: "studio"),
        ])
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let options = try await model.newSessionOptions(templateSessionID: "session-long", isTab: true)
        let generation = model.workspaceGeneration
        #expect(model.quickActionBlockingFailure(rootID: "session-long") == .busy)
        await #expect(throws: QuickActionFailure.busy) {
            try await model.stageQuickAction(.commit, rootID: "session-long", options: options,
                                      runConfig: options.runConfig, workspaceGeneration: generation)
        }
        #expect(model.pendingSessionTab(rootID: "session-long") == nil)
        await model.selectWorkspace("ws-studio")
        await #expect(throws: CancellationError.self) {
            try await model.stageQuickAction(.commit, rootID: "session-long", options: options,
                                      runConfig: options.runConfig, workspaceGeneration: generation)
        }
    }

    @Test(arguments: QuickActionProfile.allCases)
    func preferencesPersistAcrossLaunchesShareOneMachineAndRespectScopes(profile: QuickActionProfile) async throws {
        let suite = "QuickActionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await model.adoptExistingAccount()
        let preference = QuickActionPreference(agentConfigID: "codex", modelID: "gpt-5.4-mini", reasoning: "low")
        model.saveQuickActionPreference(preference, rootID: "session-pr", profile: profile, workspaceGeneration: model.workspaceGeneration)
        #expect(model.quickActionPreference(rootID: "session-long", profile: profile) == preference)
        let relaunched = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await relaunched.adoptExistingAccount()
        #expect(relaunched.quickActionPreference(rootID: "session-pr", profile: profile) == preference)
        let loaded = try await QuickActionConfigurationState.load(model: relaunched, rootID: "session-pr", profile: profile)
        #expect(loaded.isReady)
        #expect(loaded.options?.agentConfigID == "codex")
        #expect(loaded.runConfig?.model?.value == "gpt-5.4-mini")
        #expect(loaded.runConfig?.selectedReasoning?.value == "low")
        let account = try #require(model.account)
        let key = QuickActionPreference.storageKey(account: account, workspaceID: "ws-demo", machineID: "machine-1")
        #expect(key != QuickActionPreference.storageKey(account: account, workspaceID: "other", machineID: "machine-1"))
        #expect(key != QuickActionPreference.storageKey(account: account, workspaceID: "ws-demo", machineID: "other"))
        #expect(key != QuickActionPreference.storageKey(account: Account(email: "other@example.test", id: "other"),
                                                       workspaceID: "ws-demo", machineID: "machine-1"))
        model.signOut()
        #expect(model.quickActionPreference(rootID: "session-pr", profile: profile) == nil)
        model.saveQuickActionPreference(nil, rootID: "session-pr", profile: profile, workspaceGeneration: model.workspaceGeneration)
        #expect(relaunched.quickActionPreference(rootID: "session-pr", profile: profile) == preference)
        relaunched.saveQuickActionPreference(nil, rootID: "session-pr", profile: profile, workspaceGeneration: relaunched.workspaceGeneration)
        #expect(relaunched.quickActionPreference(rootID: "session-pr", profile: profile) == nil)
    }

    @Test func legacyPreferencesMigrateWithoutCouplingProfilesOrRevivingResetValues() async throws {
        let suite = "QuickActionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await model.adoptExistingAccount()
        let account = try #require(model.account)
        let key = try #require(QuickActionPreference.storageKey(account: account, workspaceID: "ws-demo", machineID: "machine-1"))
        let legacy = QuickActionPreference(agentConfigID: "codex", modelID: "gpt-5.4-mini", reasoning: "low")
        defaults.set(try JSONEncoder().encode(legacy), forKey: key)
        #expect(model.quickActionPreference(rootID: "session-pr", profile: .review) == legacy)
        #expect(model.quickActionPreference(rootID: "session-pr", profile: .git) == legacy)
        // Reset must migrate both profiles, retaining the other's original value.
        model.saveQuickActionPreference(nil, rootID: "session-pr", profile: .review, workspaceGeneration: model.workspaceGeneration)
        let relaunched = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await relaunched.adoptExistingAccount()
        #expect(relaunched.quickActionPreference(rootID: "session-pr", profile: .review) == nil)
        #expect(relaunched.quickActionPreference(rootID: "session-pr", profile: .git) == legacy)
        let review = QuickActionPreference(agentConfigID: "claude", modelID: "opus")
        relaunched.saveQuickActionPreference(review, rootID: "session-pr", profile: .review,
            workspaceGeneration: relaunched.workspaceGeneration)
        #expect(relaunched.quickActionPreference(rootID: "session-pr", profile: .git) == legacy)
        let configuration = try await QuickActionConfigurationState.load(model: relaunched, rootID: "session-pr", profile: .review)
        #expect(configuration.options?.agentConfigID == "claude")
        #expect(configuration.runConfig?.model?.value == "opus")
        relaunched.saveQuickActionPreference(nil, rootID: "session-pr", profile: .git,
            workspaceGeneration: relaunched.workspaceGeneration)
        #expect(relaunched.quickActionPreference(rootID: "session-pr", profile: .review) == review)
        #expect(relaunched.quickActionPreference(rootID: "session-pr", profile: .git) == nil)
        relaunched.saveQuickActionPreference(nil, rootID: "session-pr", profile: .review,
            workspaceGeneration: relaunched.workspaceGeneration - 1)
        #expect(relaunched.quickActionPreference(rootID: "session-pr", profile: .review) == review)
    }

    @Test func invalidReviewPreferenceDoesNotBlockOtherGitActions() async throws {
        let suite = "QuickActionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await model.adoptExistingAccount()
        model.saveQuickActionPreference(.init(agentConfigID: "codex", modelID: "removed"),
            rootID: "session-pr", profile: .review, workspaceGeneration: model.workspaceGeneration)
        let review = try await QuickActionConfigurationState.load(model: model, rootID: "session-pr", profile: .review)
        #expect(!review.isReady)
        #expect(review.preferenceIssue != nil)
        let git = try await QuickActionConfigurationState.load(model: model, rootID: "session-pr", profile: .git)
        #expect(git.isReady)
    }

    @Test func settingsOfferAvailableAgentsWithoutSilentlyReplacingARemovedAgent() async throws {
        let suite = "QuickActionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await model.adoptExistingAccount()
        let preference = QuickActionPreference(agentConfigID: "removed-agent", modelID: "removed-model")
        model.saveQuickActionPreference(preference, rootID: "session-pr", profile: .review,
            workspaceGeneration: model.workspaceGeneration)
        await #expect(throws: LodyClientError.notConnected) {
            try await QuickActionConfigurationState.load(model: model, rootID: "session-pr", profile: .review)
        }
        let settings = try await QuickActionConfigurationState.load(model: model, rootID: "session-pr", profile: .review,
            allowsAgentRecovery: true)
        #expect(!settings.isReady)
        #expect(settings.unavailableAgentID == "removed-agent")
        #expect(settings.options?.providers.contains { $0.value == "codex" } == true)
        #expect(settings.runConfig == nil)
        #expect(model.quickActionPreference(rootID: "session-pr", profile: .review) == preference)
        let selected = try await QuickActionConfigurationState.load(model: model, rootID: "session-pr", profile: .review,
            agentConfigID: "codex", allowsAgentRecovery: true)
        #expect(selected.isReady)
        #expect(selected.unavailableAgentID == nil)
        #expect(selected.options?.agentConfigID == "codex")
    }

    @Test func savedConfigurationIsCheckedAgainstCurrentModelCapabilities() throws {
        var config: NewSessionRunConfig? = .fixture
        let valid = QuickActionPreference(agentConfigID: "codex", modelID: "gpt-5.4-mini", reasoning: "low")
        try valid.apply(to: &config)
        #expect(config?.model?.value == "gpt-5.4-mini")
        #expect(config?.selectedReasoning?.value == "low")
        #expect(throws: QuickActionFailure.savedReasoningUnavailable) {
            try QuickActionPreference(agentConfigID: "codex", modelID: "gpt-5.4-mini", reasoning: "high").apply(to: &config)
        }
        #expect(throws: QuickActionFailure.savedModelUnavailable) {
            try QuickActionPreference(agentConfigID: "codex", modelID: "removed").apply(to: &config)
        }
    }

    @Test(.timeLimit(.minutes(1))) func concurrentProfilesShareInitialReadAndRefreshButApplyIndependentPreferences() async throws {
        let suite = "QuickActionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = ControlledQuickActionOptionsClient()
        let model = AppModel(client: client, quickActionDefaults: defaults)
        await model.adoptExistingAccount()
        model.saveQuickActionPreference(.init(agentConfigID: "codex", modelID: "gpt-5.5", reasoning: "high"),
            rootID: "session-pr", profile: .review, workspaceGeneration: model.workspaceGeneration)
        model.saveQuickActionPreference(.init(agentConfigID: "codex", modelID: "gpt-5.4-mini", reasoning: "low"),
            rootID: "session-pr", profile: .git, workspaceGeneration: model.workspaceGeneration)
        var requests = client.started.makeAsyncIterator()
        let review = await startLoad {
            try await QuickActionConfigurationState.load(model: model, rootID: "session-pr", profile: .review).runConfig
        }
        let initial = try #require(await requests.next())
        let git = await startLoad {
            try await QuickActionConfigurationState.load(model: model, rootID: "session-pr", profile: .git).runConfig
        }
        #expect(client.requests.count == 1)
        client.finish(initial)
        let refresh = try #require(await requests.next())
        #expect(refresh.refresh)
        client.finish(refresh)
        let reviewConfig = try await review.value
        let gitConfig = try await git.value
        #expect(reviewConfig?.model?.value == "gpt-5.5")
        #expect(reviewConfig?.selectedReasoning?.value == "high")
        #expect(gitConfig?.model?.value == "gpt-5.4-mini")
        #expect(gitConfig?.selectedReasoning?.value == "low")
        #expect(client.requests.map(\.refresh) == [false, true])

        // Sharing ends with the operation; a later visit still checks current options.
        client.reportsStaleOptions = false
        let later = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: "codex") }
        client.finish(try #require(await requests.next()))
        _ = try await later.value
        #expect(client.requests.count == 3)
    }

    @Test(.timeLimit(.minutes(1))) func inheritedAndExplicitAgentLoadsShareTheirResolvedRefresh() async throws {
        let client = ControlledQuickActionOptionsClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        var requests = client.started.makeAsyncIterator()
        let inherited = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: nil) }
        let inheritedRequest = try #require(await requests.next())
        let explicit = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: "codex") }
        let explicitRequest = try #require(await requests.next())
        client.finish(inheritedRequest)
        client.finish(explicitRequest)
        let refresh = try #require(await requests.next())
        #expect(client.requests.map(\.refresh) == [false, false, true])
        client.finish(refresh)
        #expect(try await inherited.value.agentConfigID == "codex")
        #expect(try await explicit.value.agentConfigID == "codex")
    }

    @Test(.timeLimit(.minutes(1))) func cancellingOneProfileDuringRefreshKeepsTheOtherWaiting() async throws {
        let client = ControlledQuickActionOptionsClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        var requests = client.started.makeAsyncIterator()
        let first = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: nil) }
        let initial = try #require(await requests.next())
        let second = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: nil) }
        client.finish(initial)
        let refresh = try #require(await requests.next())
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(client.cancelledRequests.isEmpty)
        client.finish(refresh)
        #expect(try await second.value.agentConfigID == "codex")
        #expect(client.requests.count == 2)
    }

    @Test(.timeLimit(.minutes(1))) func cancellingLastWaiterStopsRefreshAndAllowsANewLoad() async throws {
        let client = ControlledQuickActionOptionsClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        var requests = client.started.makeAsyncIterator()
        var cancellations = client.cancelled.makeAsyncIterator()
        let first = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: "codex") }
        client.finish(try #require(await requests.next()))
        let refresh = try #require(await requests.next())
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await cancellations.next() == refresh)
        client.reportsStaleOptions = false
        let retry = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: "codex") }
        let next = try #require(await requests.next())
        #expect(!next.refresh)
        client.finish(next)
        #expect(try await retry.value.agentConfigID == "codex")
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["agent", "root", "refresh"])
    func distinctQuickActionRequestsDoNotShareOptions(difference: String) async throws {
        let client = ControlledQuickActionOptionsClient()
        client.reportsStaleOptions = false
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        var requests = client.started.makeAsyncIterator()
        let first = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: "codex") }
        let firstRequest = try #require(await requests.next())
        let second = await startLoad {
            try await model.quickActionOptions(rootID: difference == "root" ? "session-long" : "session-pr",
                agentConfigID: difference == "agent" ? "claude" : "codex", refresh: difference == "refresh")
        }
        let secondRequest = try #require(await requests.next())
        #expect(client.requests.count == 2)
        client.finish(firstRequest)
        client.finish(secondRequest)
        #expect(try await first.value.agentConfigID == "codex")
        #expect(try await second.value.agentConfigID == (difference == "agent" ? "claude" : "codex"))
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["workspace", "sign-out"])
    func contextChangesReleaseWaitersAndIgnoreLateOptions(change: String) async throws {
        let client = ControlledQuickActionOptionsClient()
        client.ignoresCancellation = true
        client.reportsStaleOptions = false
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        var requests = client.started.makeAsyncIterator()
        var cancellations = client.cancelled.makeAsyncIterator()
        let old = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: "codex") }
        let oldRequest = try #require(await requests.next())
        if change == "workspace" { await model.selectWorkspace("ws-other") }
        else { model.signOut() }
        await #expect(throws: CancellationError.self) { try await old.value }
        #expect(await cancellations.next() == oldRequest)

        if change == "workspace" {
            let current = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: "codex") }
            let currentRequest = try #require(await requests.next())
            #expect(currentRequest.workspaceID == "ws-other")
            client.finish(oldRequest)
            client.finish(currentRequest)
            _ = try await current.value
        } else {
            client.finish(oldRequest)
            #expect(!model.isSignedIn)
        }
    }

    @Test(.timeLimit(.minutes(1))) func failedSharedRefreshReleasesBothWaitersAndCanRetry() async throws {
        let client = ControlledQuickActionOptionsClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        var requests = client.started.makeAsyncIterator()
        let first = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: "codex") }
        let initial = try #require(await requests.next())
        let second = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: "codex") }
        client.finish(initial)
        client.finish(try #require(await requests.next()), error: LodyClientError.unreachable)
        await #expect(throws: LodyClientError.unreachable) { try await first.value }
        await #expect(throws: LodyClientError.unreachable) { try await second.value }
        client.reportsStaleOptions = false
        let retry = await startLoad { try await model.quickActionOptions(rootID: "session-pr", agentConfigID: "codex") }
        client.finish(try #require(await requests.next()))
        _ = try await retry.value
        #expect(client.requests.map(\.refresh) == [false, true, false])
    }

    private func startLoad<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async -> Task<Value, Error> {
        let (started, signal) = AsyncStream<Void>.makeStream()
        let task = Task {
            signal.yield(())
            return try await operation()
        }
        // The main-actor operation registers its waiter before yielding back here.
        var events = started.makeAsyncIterator()
        await events.next()
        return task
    }
}

@MainActor
private final class ControlledQuickActionOptionsClient: LodyClient {
    struct Request: Equatable, Sendable {
        let id: Int
        let workspaceID: String
        let refresh: Bool
    }
    private let fixture = FixtureLodyClient(startsSignedIn: true, workspaceSummaries: [
        WorkspaceSummary(id: "ws-demo", name: "Demo", slug: "demo"),
        WorkspaceSummary(id: "ws-other", name: "Other", slug: "other"),
    ])
    private var gates: [Int: CheckedContinuation<Void, Error>] = [:]
    private let startedSignal: AsyncStream<Request>.Continuation
    private let cancelledSignal: AsyncStream<Request>.Continuation
    let started: AsyncStream<Request>
    let cancelled: AsyncStream<Request>
    private(set) var requests: [Request] = []
    private(set) var cancelledRequests: [Request] = []
    var reportsStaleOptions = true
    var ignoresCancellation = false
    var account: Account? { fixture.account }

    init() {
        (started, startedSignal) = AsyncStream.makeStream()
        (cancelled, cancelledSignal) = AsyncStream.makeStream()
    }

    func finish(_ request: Request, error: Error? = nil) {
        guard let gate = gates.removeValue(forKey: request.id) else { return }
        if let error { gate.resume(throwing: error) }
        else { gate.resume() }
    }

    func newSessionOptions(templateSessionID: String, agentConfigID: String?, projectID: String?,
                           isTab: Bool, refresh: Bool, workspaceID: String) async throws -> NewSessionOptions {
        let request = Request(id: requests.count, workspaceID: workspaceID, refresh: refresh)
        requests.append(request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (gate: CheckedContinuation<Void, Error>) in
                gates[request.id] = gate
                startedSignal.yield(request)
            }
        } onCancel: {
            Task { @MainActor in
                guard self.gates[request.id] != nil else { return }
                self.cancelledRequests.append(request)
                self.cancelledSignal.yield(request)
                if !self.ignoresCancellation { self.finish(request, error: CancellationError()) }
            }
        }
        return NewSessionOptions(machineName: "Fixture", agentConfigID: agentConfigID ?? "codex", providers: [],
            runConfig: .fixture, needsRefresh: reportsStaleOptions && !refresh)
    }

    func restoreSession() async -> Account? { await fixture.restoreSession() }
    func workspaces() async throws -> [WorkspaceSummary] { try await fixture.workspaces() }
    func sessions(workspaceID: String) async throws -> [SessionSummary] { try await fixture.sessions(workspaceID: workspaceID) }
    func signOut() { fixture.signOut() }
    func beginDeviceAuthorization() async throws -> DeviceAuthorization { try await fixture.beginDeviceAuthorization() }
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws { try await fixture.finishDeviceAuthorization(authorization) }
    func conversation(sessionID: String, workspaceID: String) async throws -> Conversation { throw LodyClientError.notConnected }
    func send(_ text: String, attachments: [ComposerAttachment], runConfig: RunConfigChoice?, turnID: String,
              sessionID: String, workspaceID: String) async throws -> RunConfigChoice? { throw LodyClientError.notConnected }
    func cancelSession(sessionID: String, workspaceID: String) async throws { throw LodyClientError.notConnected }
    func respond(_ decision: PermissionDecision, requestID: String, sessionID: String, workspaceID: String) async throws { throw LodyClientError.notConnected }
}
