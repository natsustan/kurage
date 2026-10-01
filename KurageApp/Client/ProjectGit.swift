import Foundation

struct ProjectBranch: Equatable, Sendable {
    let id: String

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

    var branchName: String { currentBranch.map { ProjectBranch(id: $0).name } ?? "Detached HEAD" }
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
