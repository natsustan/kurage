import Foundation

@MainActor
@Observable
final class NotificationModel {
    private let service: any PushNotificationService
    private let defaults: UserDefaults?
    private static let preferenceKey = "pushNotificationsEnabled"
    private var wantsNotifications: Bool
    private var generation = 0
    private var recentClickIDs: [String] = []
    private var acceptsColdStartClicks = true
    private var visibilityOwner: UUID?
    private(set) var userID: String?
    private(set) var status = PushNotificationStatus()
    private(set) var isUpdating = false
    private(set) var pendingClick: NotificationClick?
    var routingError: String?
    var routingErrorPresented: Bool {
        get { routingError != nil }
        set { if !newValue { routingError = nil } }
    }
    var isConfigured: Bool { service.isConfigured }
    var isEnabled: Bool { wantsNotifications && userID != nil && status.authorization == .authorized }

    init(service: any PushNotificationService, defaults: UserDefaults? = nil) {
        self.service = service
        self.defaults = defaults
        wantsNotifications = defaults?.bool(forKey: Self.preferenceKey) ?? false
        service.onClick = { [weak self] click in self?.receive(click) }
        service.onStatusChange = { [weak self] in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    func identify(_ id: String?) {
        guard userID != id else { return }
        generation += 1
        isUpdating = false
        userID = id
        if id != nil { acceptsColdStartClicks = false }
        visibilityOwner = nil
        service.setVisibleSession(workspace: nil, sessionID: nil)
        if let click = pendingClick, click.userID != id { pendingClick = nil }
        service.identify(id, enabled: wantsNotifications)
        Task { await refresh() }
    }

    func signOut() {
        generation += 1
        isUpdating = false
        userID = nil
        acceptsColdStartClicks = false
        pendingClick = nil
        recentClickIDs = []
        routingError = nil
        visibilityOwner = nil
        service.setVisibleSession(workspace: nil, sessionID: nil)
        service.identify(nil, enabled: false)
        service.clearDelivered()
        status = PushNotificationStatus()
    }

    func refresh() async {
        let expected = generation
        let value = await service.status()
        guard !Task.isCancelled, generation == expected else { return }
        status = value
    }

    func setEnabled(_ enabled: Bool) async {
        guard isConfigured, userID != nil, !isUpdating else { return }
        let expected = generation
        isUpdating = true
        defer { if generation == expected { isUpdating = false } }
        if enabled {
            let allowed = await service.requestAuthorization()
            guard !Task.isCancelled, generation == expected else { return }
            if !allowed {
                await refresh()
                return
            }
        }
        guard !Task.isCancelled, generation == expected else { return }
        wantsNotifications = enabled
        defaults?.set(enabled, forKey: Self.preferenceKey)
        service.setSubscribed(enabled)
        await refresh()
    }

    func receive(_ click: NotificationClick) {
        guard (userID == click.userID || (userID == nil && acceptsColdStartClicks)),
              !recentClickIDs.contains(click.id) else { return }
        recentClickIDs.append(click.id)
        if recentClickIDs.count > 32 { recentClickIDs.removeFirst() }
        pendingClick = click
        routingError = nil
    }

    func acknowledge(_ id: String) {
        if pendingClick?.id == id { pendingClick = nil }
    }

    func setVisibleSession(owner: UUID, workspace: WorkspaceSummary?, sessionID: String?) {
        if sessionID != nil {
            visibilityOwner = owner
            service.setVisibleSession(workspace: workspace, sessionID: sessionID)
        } else if visibilityOwner == owner {
            visibilityOwner = nil
            service.setVisibleSession(workspace: nil, sessionID: nil)
        }
    }
}
