import Foundation

public struct ProjectBranch: Equatable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }

    /// Compare local and remote selectors by their branch component.
    public var localName: String {
        let remote = "lody:branch:remote:"
        if id.hasPrefix(remote), let separator = id.dropFirst(remote.count).firstIndex(of: ":") {
            let branch = String(id[id.index(after: separator)...])
            return branch.removingPercentEncoding ?? branch
        }
        return name
    }

    public var name: String {
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

public struct ProjectGitState: Codable, Equatable, Sendable {
    public var git: Bool
    public var currentBranch: String? = nil
    public var defaultBranch: String? = nil
    public var githubRepoFullName: String? = nil
    public var workingTree: ProjectWorkingTree? = nil
    /// These optional hints come from the directory owner's synchronized metadata,
    /// and are omitted when its project or branch does not match the live Git read.
    public var hasUnpushedCommits: Bool? = nil
    /// Zero line-count statistics leave this unknown because non-text changes may exist.
    public var hasBranchChanges: Bool? = nil
    public var hasOpenPR: Bool? = nil
    public var sessionDirectoryMatchesProject: Bool? = nil

    public init(
        git: Bool,
        currentBranch: String? = nil,
        defaultBranch: String? = nil,
        githubRepoFullName: String? = nil,
        workingTree: ProjectWorkingTree? = nil,
        hasUnpushedCommits: Bool? = nil,
        hasBranchChanges: Bool? = nil,
        hasOpenPR: Bool? = nil,
        sessionDirectoryMatchesProject: Bool? = nil
    ) {
        self.git = git
        self.currentBranch = currentBranch
        self.defaultBranch = defaultBranch
        self.githubRepoFullName = githubRepoFullName
        self.workingTree = workingTree
        self.hasUnpushedCommits = hasUnpushedCommits
        self.hasBranchChanges = hasBranchChanges
        self.hasOpenPR = hasOpenPR
        self.sessionDirectoryMatchesProject = sessionDirectoryMatchesProject
    }

    public var branchName: String { currentBranch.map { ProjectBranch(id: $0).name } ?? "Detached HEAD" }
}

public struct ProjectWorkingTree: Codable, Equatable, Sendable {
    public var clean: Bool
    public var staged = false
    public var unstaged = false
    public var untracked = false
    public var conflicted = false

    public init(clean: Bool, staged: Bool = false, unstaged: Bool = false, untracked: Bool = false, conflicted: Bool = false) {
        self.clean = clean
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
        self.conflicted = conflicted
    }
}

public enum ProjectGitFailure: String, Codable, Sendable {
    case unavailable, unsupported
    case accessDenied = "access_denied"

    public var message: LocalizedStringResource {
        switch self {
        case .unavailable: "Could not read branch. Tap to retry."
        case .unsupported: "Branch reading unavailable on this machine."
        case .accessDenied: "No access to this project's Git state."
        }
    }
}

public struct ProjectGitResult: Codable, Equatable, Sendable {
    public var state: ProjectGitState? = nil
    public var failure: ProjectGitFailure? = nil

    public init(state: ProjectGitState? = nil, failure: ProjectGitFailure? = nil) {
        self.state = state
        self.failure = failure
    }
}
