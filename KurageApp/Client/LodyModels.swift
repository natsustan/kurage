import Foundation

struct Account: Codable, Equatable, Sendable {
    var email: String
    var id: String? = nil
}

enum SessionActivity: String, Codable, Equatable, Sendable {
    case running
    case idle
}

struct SessionSummary: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var agentName: String
    var activity: SessionActivity
    var preview: String
    var projectID: String? = nil
    var projectName: String? = nil
}

enum TurnAuthor: String, Codable, Equatable, Sendable {
    case user
    case agent
}

struct ConversationTurn: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var author: TurnAuthor
    var text: String
}

struct PermissionPrompt: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var detail: String
}

struct Conversation: Codable, Equatable, Sendable {
    var sessionID: SessionSummary.ID
    var turns: [ConversationTurn]
    var permission: PermissionPrompt?
}

enum PermissionDecision: Equatable, Sendable {
    case allow
    case deny
}

struct WorkspaceSummary: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var slug: String
}

struct DeviceAuthorization: Equatable, Sendable {
    var userCode: String
    var verificationURL: URL
    var deviceCode: String
    var expiresIn: TimeInterval
    var interval: TimeInterval
}

enum LodyClientError: Error, Equatable {
    case signedOut
    case sessionMissing
    case permissionMissing
    case emptyMessage
    case deliveryUnconfirmed
    case sendSuperseded
    case sessionBusy
    case notConnected
    case unreachable
    case signInFailed
    case accessDenied
    case codeExpired
}

struct ConversationUpdate: Equatable, Sendable {
    var conversation: Conversation
    var activity: SessionActivity?
    var syncState: ConversationSyncState
}

enum ConversationSyncState: String, Decodable, Sendable {
    case connecting
    case live
}

struct ConversationPatch: Decodable {
    let sessionID: String
    let order: [String]
    let changed: [ConversationTurn]
    let permission: PermissionPrompt?
    let activity: String
    let syncState: ConversationSyncState

    func applying(to previous: Conversation) throws -> ConversationUpdate {
        guard previous.sessionID == sessionID, Set(order).count == order.count else {
            throw LodyClientError.notConnected
        }
        var turns = Dictionary(uniqueKeysWithValues: previous.turns.map { ($0.id, $0) })
        for turn in changed { turns[turn.id] = turn }
        let ordered = try order.map { id in
            guard let turn = turns[id] else { throw LodyClientError.notConnected }
            return turn
        }
        return ConversationUpdate(
            conversation: Conversation(sessionID: sessionID, turns: ordered, permission: permission),
            activity: activity == "running" ? .running : .idle, syncState: syncState
        )
    }
}

/// Display data only; credentials remain in Keychain.
struct SessionCache: Codable, Equatable, Sendable {
    var account: Account
    var workspaces: [WorkspaceSummary] = []
    var selectedWorkspaceID: String?
    var sessionsByWorkspace: [String: [SessionSummary]] = [:]
}
