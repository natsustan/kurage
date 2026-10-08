import Foundation

public struct NotificationRoute: Equatable, Sendable {
    public let workspace: String
    public let sessionID: String

    public init?(_ route: String) {
        guard route.utf8.count <= 2048 else { return nil }
        let parts = route.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].isEmpty, parts[2] == "sessions",
              let workspace = Self.component(String(parts[1])),
              let sessionID = Self.component(String(parts[3])) else { return nil }
        self.workspace = workspace
        self.sessionID = sessionID
    }

    private static func component(_ value: String) -> String? {
        guard let decoded = value.removingPercentEncoding, !decoded.isEmpty,
              decoded != ".", decoded != "..",
              !decoded.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || "/\\?#".unicodeScalars.contains($0)
              }) else { return nil }
        return decoded
    }
}

public struct NotificationClick: Equatable, Sendable, Identifiable {
    public let id: String
    public let route: NotificationRoute
    public let userID: String

    public init(id: String, route: NotificationRoute, userID: String) {
        self.id = id
        self.route = route
        self.userID = userID
    }
}

public struct NotificationIdentity: Sendable {
    public private(set) var userID: String?
    public private(set) var legacyRecipientID: String?
    public private(set) var generation = 0

    public init(legacyRecipientID: String? = nil) {
        self.legacyRecipientID = legacyRecipientID?.isEmpty == false ? legacyRecipientID : nil
    }

    public mutating func identify(_ id: String?) {
        // An ownerless payload cannot be attributed after leaving the startup SDK identity.
        // Once discarded, the fallback stays unavailable until a new launch captures it.
        if id != legacyRecipientID { legacyRecipientID = nil }
        userID = id
        generation += 1
    }

    public func recipientUserID(_ recipient: String?) -> String? {
        guard let owner = recipient ?? legacyRecipientID, !owner.isEmpty else { return nil }
        return owner
    }

    public func acceptsClick(userID owner: String, capturedGeneration: Int) -> Bool {
        guard generation == 0 || userID == owner else { return false }
        return generation == capturedGeneration ||
            (capturedGeneration == 0 && generation == 1 && userID == owner)
    }
}

public struct NotificationSessionDestination: Codable, Equatable, Sendable {
    public let rootSessionID: String
    public let sessionID: String
    public let isTabClosed: Bool

    public init(rootSessionID: String, sessionID: String, isTabClosed: Bool) {
        self.rootSessionID = rootSessionID
        self.sessionID = sessionID
        self.isTabClosed = isTabClosed
    }
}

public struct NotificationNavigation: Equatable, Sendable {
    public let clickID: String
    public let workspaceID: String
    public let rootSessionID: String
    public let sessionID: String
}

public enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized
}

public struct PushNotificationStatus: Equatable, Sendable {
    public var authorization: NotificationAuthorization = .notDetermined
    public var isSubscribed = false
    public var isRegistered = false

    public init(
        authorization: NotificationAuthorization = .notDetermined,
        isSubscribed: Bool = false,
        isRegistered: Bool = false
    ) {
        self.authorization = authorization
        self.isSubscribed = isSubscribed
        self.isRegistered = isRegistered
    }
}

@MainActor
public protocol PushNotificationService: AnyObject {
    var isConfigured: Bool { get }
    var onClick: (@MainActor (NotificationClick) -> Void)? { get set }
    var onStatusChange: (@MainActor () -> Void)? { get set }
    func identify(_ userID: String?, enabled: Bool)
    func setSubscribed(_ enabled: Bool)
    func status() async -> PushNotificationStatus
    func requestAuthorization() async -> Bool
    func setVisibleSession(workspace: WorkspaceSummary?, sessionID: String?)
    func clearDelivered()
}

/// A deliberately unavailable notification backend for platforms without a live integration.
@MainActor
public final class DisabledNotificationService: PushNotificationService {
    public var isConfigured: Bool { false }
    public var onClick: (@MainActor (NotificationClick) -> Void)?
    public var onStatusChange: (@MainActor () -> Void)?

    public init() {}

    public func identify(_ userID: String?, enabled: Bool) {}
    public func setSubscribed(_ enabled: Bool) {}
    public func status() async -> PushNotificationStatus { PushNotificationStatus() }
    public func requestAuthorization() async -> Bool { false }
    public func setVisibleSession(workspace: WorkspaceSummary?, sessionID: String?) {}
    public func clearDelivered() {}
}

@MainActor
public final class FixturePushNotificationService: PushNotificationService {
    public var isConfigured: Bool
    public var onClick: (@MainActor (NotificationClick) -> Void)?
    public var onStatusChange: (@MainActor () -> Void)?
    public var currentStatus = PushNotificationStatus()
    public var userID: String?
    public var grantsAuthorization = true
    public var requestCount = 0

    public init(isConfigured: Bool = false) { self.isConfigured = isConfigured }
    public func identify(_ userID: String?, enabled: Bool) {
        self.userID = userID
        setSubscribed(userID != nil && enabled)
    }
    public func setSubscribed(_ enabled: Bool) {
        currentStatus.isSubscribed = enabled && currentStatus.authorization == .authorized
        currentStatus.isRegistered = currentStatus.isSubscribed
    }
    public func status() async -> PushNotificationStatus { currentStatus }
    public func requestAuthorization() async -> Bool {
        requestCount += 1
        currentStatus.authorization = grantsAuthorization ? .authorized : .denied
        return grantsAuthorization
    }
    public func setVisibleSession(workspace: WorkspaceSummary?, sessionID: String?) {}
    public func clearDelivered() {}
}
