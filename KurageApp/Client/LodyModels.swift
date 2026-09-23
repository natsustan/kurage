import Foundation

struct Account: Equatable, Sendable {
    var email: String
}

enum SessionActivity: Equatable, Sendable {
    case running
    case idle
}

struct SessionSummary: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var agentName: String
    var activity: SessionActivity
    var preview: String
}

enum TurnAuthor: Equatable, Sendable {
    case user
    case agent
}

struct ConversationTurn: Identifiable, Equatable, Sendable {
    let id: String
    var author: TurnAuthor
    var text: String
}

struct PermissionPrompt: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var detail: String
}

struct Conversation: Equatable, Sendable {
    var sessionID: SessionSummary.ID
    var turns: [ConversationTurn]
    var permission: PermissionPrompt?
}

enum PermissionDecision: Equatable, Sendable {
    case allow
    case deny
}

struct WorkspaceSummary: Identifiable, Equatable, Sendable {
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
    case notConnected
    case unreachable
    case signInFailed
    case accessDenied
    case codeExpired
}
