import Foundation

struct NotificationRoute: Equatable, Sendable {
    let workspace: String
    let sessionID: String

    init?(_ route: String) {
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

struct NotificationClick: Equatable, Sendable, Identifiable {
    let id: String
    let route: NotificationRoute
    let userID: String
}

struct NotificationSessionDestination: Codable, Equatable, Sendable {
    let rootSessionID: String
    let sessionID: String
    let isTabClosed: Bool
}

struct NotificationNavigation: Equatable, Sendable {
    let clickID: String
    let workspaceID: String
    let rootSessionID: String
    let sessionID: String
}

enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized
}

struct PushNotificationStatus: Equatable, Sendable {
    var authorization: NotificationAuthorization = .notDetermined
    var isSubscribed = false
    var isRegistered = false
}

@MainActor
protocol PushNotificationService: AnyObject {
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

@MainActor
final class FixturePushNotificationService: PushNotificationService {
    var isConfigured: Bool
    var onClick: (@MainActor (NotificationClick) -> Void)?
    var onStatusChange: (@MainActor () -> Void)?
    var currentStatus = PushNotificationStatus()
    var userID: String?
    var grantsAuthorization = true
    var requestCount = 0

    init(isConfigured: Bool = false) { self.isConfigured = isConfigured }
    func identify(_ userID: String?, enabled: Bool) {
        self.userID = userID
        setSubscribed(userID != nil && enabled)
    }
    func setSubscribed(_ enabled: Bool) {
        currentStatus.isSubscribed = enabled && currentStatus.authorization == .authorized
        currentStatus.isRegistered = currentStatus.isSubscribed
    }
    func status() async -> PushNotificationStatus { currentStatus }
    func requestAuthorization() async -> Bool {
        requestCount += 1
        currentStatus.authorization = grantsAuthorization ? .authorized : .denied
        return grantsAuthorization
    }
    func setVisibleSession(workspace: WorkspaceSummary?, sessionID: String?) {}
    func clearDelivered() {}
}
