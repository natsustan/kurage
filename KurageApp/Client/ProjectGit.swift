import Foundation

struct ProjectBranch: Equatable, Sendable {
    let id: String

    /// Compare local and remote selectors by their branch component.
    var localName: String {
        let remote = "lody:branch:remote:"
        if id.hasPrefix(remote), let separator = id.dropFirst(remote.count).firstIndex(of: ":") {
            let branch = String(id[id.index(after: separator)...])
            return branch.removingPercentEncoding ?? branch
        }
        return name
    }

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
    var git: Bool
    var currentBranch: String? = nil
    var defaultBranch: String? = nil
    var githubRepoFullName: String? = nil
    var workingTree: ProjectWorkingTree? = nil
    /// These optional hints come from the directory owner's synchronized metadata,
    /// and are omitted when its project or branch does not match the live Git read.
    var hasUnpushedCommits: Bool? = nil
    var hasBranchChanges: Bool? = nil
    var hasOpenPR: Bool? = nil
    var sessionDirectoryMatchesProject: Bool? = nil

    var branchName: String { currentBranch.map { ProjectBranch(id: $0).name } ?? "Detached HEAD" }
}

struct ProjectWorkingTree: Codable, Equatable, Sendable {
    var clean: Bool
    var staged = false
    var unstaged = false
    var untracked = false
    var conflicted = false
}

enum ProjectGitFailure: String, Codable, Sendable {
    case unavailable, unsupported
    case accessDenied = "access_denied"

    var message: LocalizedStringResource {
        switch self {
        case .unavailable: "Could not read branch. Tap to retry."
        case .unsupported: "Branch reading unavailable on this machine."
        case .accessDenied: "No access to this project's Git state."
        }
    }
}

struct ProjectGitResult: Codable, Equatable, Sendable {
    var state: ProjectGitState? = nil
    var failure: ProjectGitFailure? = nil
}
