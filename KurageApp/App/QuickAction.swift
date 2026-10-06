import Foundation

enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    case reviewChanges = "review-changes"
    case createBranch = "create-branch"
    case commit
    case commitAndPush = "commit-and-push"
    case push
    case createBranchAndCommit = "create-branch-and-commit"
    case createPR = "create-pr"
    case createDraftPR = "create-draft-pr"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .reviewChanges: "Review Changes"
        case .createBranch: "Create Branch"
        case .commit: "Commit"
        case .commitAndPush: "Commit & Push"
        case .push: "Push"
        case .createBranchAndCommit: "Create Branch & Commit"
        case .createPR: "Create PR"
        case .createDraftPR: "Create Draft PR"
        }
    }

    var symbol: String {
        switch self {
        case .reviewChanges: "doc.text.magnifyingglass"
        case .createBranch: "arrow.triangle.branch"
        case .commit, .commitAndPush: "checkmark.circle"
        case .push: "arrow.up.circle"
        case .createBranchAndCommit: "arrow.triangle.branch"
        case .createPR, .createDraftPR: "arrow.triangle.pull"
        }
    }

    /// The task has its own context. Resolve everything from the shared directory,
    /// rather than assuming the parent conversation or its historical diff was copied.
    var prompt: String {
        let task = switch self {
        case .reviewChanges:
            "Inspect the repository instructions and review the staged and unstaged changes, including relevant untracked source files. If there are no working-tree changes, review the current branch's changes against a verified base branch and merge base. Focus on concrete bugs, regressions, security issues, and missing necessary validation. Return prioritized findings with file paths, line numbers, and specific failure scenarios; if there are none, say so and describe the validation limits. This is a read-only review: do not edit files, stage changes, create commits, switch branches, push, or publish review comments."
        case .createBranch:
            "Inspect the repository and current changes. Choose a concise, descriptive, unused branch name and create and switch to it from the current HEAD. Preserve all staged, unstaged, and untracked work. Do not commit."
        case .commit:
            "Inspect the repository and review the current diff. If files are already staged, commit only those files. Otherwise stage and commit the current project changes, excluding secrets, generated build artifacts, and unrelated files. Write a concise commit message describing the actual changes. If the tree is clean, report that there is nothing to commit."
        case .commitAndPush:
            "Inspect the repository, current branch, remotes, and current diff. Verify an unambiguous writable remote and the intended non-default branch before committing. If files are already staged, commit only those files. Otherwise stage and commit the current project changes, excluding secrets, generated build artifacts, and unrelated files. Write a concise commit message describing the actual changes. Push only the current branch, without force, using the machine's existing authentication; set its upstream only when the intended remote and branch are unambiguous. Preserve unrelated staged, unstaged, and untracked work. If authentication is unavailable, the branch is the default branch, the remote is ahead or diverged, or the target is ambiguous, stop and explain what is needed. Do not automatically pull, rebase, merge, create a PR, or enable automatic commit/push behavior for later turns. If the commit succeeds but push fails, report the local commit and the push failure separately."
        case .push:
            "Inspect the repository, current branch, remotes, upstream, and committed changes. Push only the current committed non-default branch, without force, using the machine's existing authentication. Preserve all staged, unstaged, and untracked changes; do not create commits or switch branches. Verify the intended repository, remote, and branch before publishing; set upstream only when the target is unambiguous. If there is nothing to push, report that. If authentication is unavailable, the branch is the default branch, the remote is ahead or diverged, or the target is ambiguous, stop and explain what is needed. Do not automatically pull, rebase, merge, create a PR, or enable automatic push behavior for later turns. Report the remote branch, published commit hash, and any local changes excluded from the push."
        case .createBranchAndCommit:
            "Inspect the repository and review the current diff. Choose a concise, descriptive, unused branch name and create and switch to it from the current HEAD, preserving all current work. If files are already staged, commit only those files. Otherwise stage and commit the current project changes, excluding secrets, generated build artifacts, and unrelated files. Write a concise commit message describing the actual changes. If the tree is clean, create the branch and report that there is nothing to commit."
        case .createPR, .createDraftPR:
            "Inspect the repository, current branch, remotes, and committed changes. Create \(self == .createDraftPR ? "a draft" : "a regular") pull request for the current branch using the machine's available GitHub tooling and existing authentication. Preserve all staged, unstaged, and untracked changes; do not create commits or switch branches. Uncommitted changes are not part of this PR. Verify the intended repository, head branch, and base branch before publishing. If the branch is the default branch, there are no committed changes to propose, authentication is unavailable, or the target is ambiguous, stop and explain what is needed. Check for an existing open PR for this branch and return its URL instead of creating a duplicate. Push only the current branch, without force, when necessary, and verify that the PR head matches the local commit. Report the PR URL, base/head branches, and any local changes excluded from the PR. Do not merge, change an existing PR's readiness, or enable automatic commit/push behavior for later turns."
        }
        let publishingConstraint = switch self {
        case .createPR, .createDraftPR:
            "Publishing the current committed branch and creating the requested PR are allowed only for this action."
        case .push, .commitAndPush:
            "Pushing the current branch is allowed only for this action. Do not open a pull request."
        default:
            "Do not push or open a pull request."
        }
        return """
        Run this Git quick action in this tab's inherited working directory:

        \(task)

        Follow the repository's instructions. Work only in the inherited directory; do not create a worktree. \(publishingConstraint) Do not amend existing commits, force push, force checkout, reset, or discard changes. Stop and explain any ambiguous scope or Git failure instead of taking destructive recovery steps. Return a short result. For branch and commit actions, include the branch name and, when created, the commit hash and a summary of committed files. Respect the agent's configured permission policy.
        """
    }
}

/// A small menu of next steps, derived from current Git data rather than chat diffs.
struct QuickActionAvailability: Equatable, Sendable {
    var primaryActions: [QuickAction] = []
    var allowsBranchCreation = false
    var allowsCommitAndPush = false
    var message: LocalizedStringResource?

    init(state: ProjectGitState) {
        guard state.git else {
            message = "Not a Git repository"
            return
        }
        guard state.sessionDirectoryMatchesProject == true, let tree = state.workingTree else {
            message = "Git actions are unavailable for this session's directory."
            return
        }
        let dirty = !tree.clean
        let branch = state.currentBranch.map { ProjectBranch(id: $0).localName }
        let base = state.defaultBranch.map { ProjectBranch(id: $0).localName }
        let onWorkingBranch = branch != nil && base != nil && branch != base
        let hasChanges = dirty || (onWorkingBranch && state.hasBranchChanges == true)
        if hasChanges { primaryActions.append(.reviewChanges) }
        guard !tree.conflicted else {
            message = "Resolve Git conflicts before committing or publishing."
            return
        }
        allowsBranchCreation = true
        if !onWorkingBranch {
            primaryActions.append(dirty ? .createBranchAndCommit : .createBranch)
        } else if dirty {
            primaryActions.append(.commit)
            allowsCommitAndPush = state.githubRepoFullName?.isEmpty == false || state.hasUnpushedCommits == true
        } else {
            if state.hasUnpushedCommits == true { primaryActions.append(.push) }
            if state.hasBranchChanges == true, state.githubRepoFullName?.isEmpty == false, state.hasOpenPR == false {
                primaryActions.append(.createPR)
            }
        }
        if primaryActions.isEmpty {
            message = state.hasUnpushedCommits == nil || state.hasBranchChanges == nil
                ? "Publishing status unavailable. Refresh Actions to retry."
                : "No Git actions needed right now."
        }
    }

    func allows(_ action: QuickAction) -> Bool {
        switch action {
        case .createBranch: allowsBranchCreation
        case .commitAndPush: allowsCommitAndPush
        case .createDraftPR: primaryActions.contains(.createPR)
        default: primaryActions.contains(action)
        }
    }
}

struct QuickActionPreference: Codable, Equatable, Sendable {
    var agentConfigID: String
    var modelID: String?
    var reasoning: String?

    static func storageKey(account: Account, workspaceID: String, machineID: String) -> String? {
        guard let scope = try? JSONEncoder().encode([account.id ?? account.email.lowercased(), workspaceID, machineID]) else {
            return nil
        }
        return "quickActions.v1.\(scope.base64EncodedString())"
    }

    init(options: NewSessionOptions, runConfig: NewSessionRunConfig?) {
        agentConfigID = options.agentConfigID
        modelID = runConfig?.model?.value
        reasoning = runConfig?.selectedReasoning?.value
    }

    init(agentConfigID: String, modelID: String? = nil, reasoning: String? = nil) {
        self.agentConfigID = agentConfigID
        self.modelID = modelID
        self.reasoning = reasoning
    }

    func apply(to config: inout NewSessionRunConfig?) throws {
        if let modelID {
            guard config?.model?.options.contains(where: { $0.value == modelID }) == true else {
                throw QuickActionFailure.savedModelUnavailable
            }
            config?.selectModel(modelID)
        }
        if let reasoning {
            guard config?.reasoningOptions.contains(where: { $0.value == reasoning }) == true else {
                throw QuickActionFailure.savedReasoningUnavailable
            }
            config?.selectReasoning(reasoning)
        }
    }
}

struct QuickActionMachine: Identifiable, Equatable {
    let id: String
    let name: String
    let templateSessionID: String

    static func machineID(projectID: String?) -> String? {
        guard let projectID else { return nil }
        let parts = projectID.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "local", !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        return String(parts[1])
    }
}

enum QuickActionFailure: Error, LocalizedError, Equatable {
    case unavailable, busy, pending, stateChanged, gitUnavailable, savedModelUnavailable, savedReasoningUnavailable

    var message: LocalizedStringResource {
        switch self {
        case .unavailable: "Quick Actions require a local project and an available root session."
        case .busy: "A session in this project is running. Stop it before starting a Git action."
        case .pending: "A session in this project has an unconfirmed start. Resolve it before starting a Git action."
        case .stateChanged: "The repository has changed. Refresh Quick Actions and choose an available action."
        case .gitUnavailable: "Could not read Git status. Refresh Quick Actions to retry."
        case .savedModelUnavailable: "The saved model is no longer available. Update Quick Actions in Settings or use session defaults."
        case .savedReasoningUnavailable: "The saved reasoning level is no longer available. Update Quick Actions in Settings or use session defaults."
        }
    }

    var errorDescription: String? { String(localized: message) }
}
