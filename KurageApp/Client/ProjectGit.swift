import Foundation

struct ProjectBranch: Identifiable, Equatable, Sendable {
    let id: String

    var isRemote: Bool { id.hasPrefix("lody:branch:remote:") }

    var name: String {
        let local = "lody:branch:local:"
        let remote = "lody:branch:remote:"
        if id.hasPrefix(local) {
            let value = String(id.dropFirst(local.count))
            return value.removingPercentEncoding ?? value
        }
        if id.hasPrefix(remote) {
            let value = id.dropFirst(remote.count)
            if let separator = value.firstIndex(of: ":") {
                let remoteName = String(value[..<separator])
                let branch = String(value[value.index(after: separator)...])
                return "\(remoteName.removingPercentEncoding ?? remoteName)/\(branch.removingPercentEncoding ?? branch)"
            }
        }
        return id
    }
}

struct ProjectGitState: Codable, Equatable, Sendable {
    struct WorkingTree: Codable, Equatable, Sendable {
        var clean: Bool
        var staged: Bool
        var unstaged: Bool
        var untracked: Bool
        var conflicted: Bool
    }

    var git: Bool
    var currentBranch: String? = nil
    var branches: [String]
    var workingTree: WorkingTree? = nil
    var observedAtMs: Double? = nil
    var busy: Bool

    var choices: [ProjectBranch] { branches.map { ProjectBranch(id: $0) } }
    var branchName: String { currentBranch.map { ProjectBranch(id: $0).name } ?? "Detached HEAD" }
    var canSwitch: Bool { git && !busy && workingTree?.clean == true }
}

enum ProjectGitFailure: String, Codable, Sendable {
    case unavailable, unsupported, busy
    case accessDenied = "access_denied"
    case localChanges = "local_changes"
    case branchMissing = "branch_missing"
    case notGit = "not_git"
    case switchFailed = "switch_failed"
    case switchUnconfirmed = "switch_unconfirmed"

    var message: String {
        switch self {
        case .unavailable: "Could not read branches. Check the machine and refresh."
        case .unsupported: "This machine does not support project branches."
        case .accessDenied: "You do not have access to this project's Git state."
        case .busy: "Finish this project's sessions before switching."
        case .localChanges: "Commit or stash local changes on the machine first."
        case .branchMissing: "Branch no longer available. Refresh and choose again."
        case .notGit: "This folder is not a Git repository."
        case .switchFailed: "Could not switch branches. Refresh and try again."
        case .switchUnconfirmed: "Switch not confirmed. Refresh before trying again."
        }
    }
}

struct ProjectGitResult: Codable, Equatable, Sendable {
    var state: ProjectGitState? = nil
    var failure: ProjectGitFailure? = nil
}
