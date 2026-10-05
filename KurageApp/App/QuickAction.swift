import Foundation

enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    case reviewChanges = "review-changes"
    case createBranch = "create-branch"
    case commit
    case createBranchAndCommit = "create-branch-and-commit"
    case createPR = "create-pr"
    case createDraftPR = "create-draft-pr"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .reviewChanges: "Review Changes"
        case .createBranch: "Create Branch"
        case .commit: "Commit"
        case .createBranchAndCommit: "Create Branch & Commit"
        case .createPR: "Create PR"
        case .createDraftPR: "Create Draft PR"
        }
    }

    var symbol: String {
        switch self {
        case .reviewChanges: "doc.text.magnifyingglass"
        case .createBranch: "arrow.triangle.branch"
        case .commit: "checkmark.circle"
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
        case .createBranchAndCommit:
            "Inspect the repository and review the current diff. Choose a concise, descriptive, unused branch name and create and switch to it from the current HEAD, preserving all current work. If files are already staged, commit only those files. Otherwise stage and commit the current project changes, excluding secrets, generated build artifacts, and unrelated files. Write a concise commit message describing the actual changes. If the tree is clean, create the branch and report that there is nothing to commit."
        case .createPR, .createDraftPR:
            "Inspect the repository, current branch, remotes, and committed changes. Create \(self == .createDraftPR ? "a draft" : "a regular") pull request for the current branch using the machine's available GitHub tooling and existing authentication. Preserve all staged, unstaged, and untracked changes; do not create commits or switch branches. Uncommitted changes are not part of this PR. Verify the intended repository, head branch, and base branch before publishing. If the branch is the default branch, there are no committed changes to propose, authentication is unavailable, or the target is ambiguous, stop and explain what is needed. Check for an existing open PR for this branch and return its URL instead of creating a duplicate. Push only the current branch, without force, when necessary, and verify that the PR head matches the local commit. Report the PR URL, base/head branches, and any local changes excluded from the PR. Do not merge, change an existing PR's readiness, or enable automatic commit/push behavior for later turns."
        }
        let publishingConstraint = switch self {
        case .createPR, .createDraftPR:
            "Publishing the current committed branch and creating the requested PR are allowed only for this action."
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
    case unavailable, busy, pending, savedModelUnavailable, savedReasoningUnavailable

    var message: LocalizedStringResource {
        switch self {
        case .unavailable: "Quick Actions require a local project and an available root session."
        case .busy: "A session in this project is running. Stop it before starting a Git action."
        case .pending: "A session in this project has an unconfirmed start. Resolve it before starting a Git action."
        case .savedModelUnavailable: "The saved model is no longer available. Update Quick Actions in Settings or use session defaults."
        case .savedReasoningUnavailable: "The saved reasoning level is no longer available. Update Quick Actions in Settings or use session defaults."
        }
    }

    var errorDescription: String? { String(localized: message) }
}
