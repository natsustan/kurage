import Foundation
import OneSignalFramework
import Synchronization
import UIKit
import UserNotifications
import KurageCore

/// SDK callbacks may arrive off the main actor. Only value snapshots cross that boundary.
@MainActor
final class OneSignalNotificationService: NSObject, PushNotificationService, OSNotificationClickListener,
    OSNotificationLifecycleListener, OSPushSubscriptionObserver {
    static let shared = OneSignalNotificationService()
    // Enable only after hosted Lody Cloud delivery to Kurage is confirmed.
    private static let isCloudDeliveryEnabled = false
    private(set) var isConfigured = false
    var onClick: (@MainActor (NotificationClick) -> Void)? {
        didSet {
            if let onClick {
                bufferedClicks.forEach(onClick)
                bufferedClicks.removeAll()
            }
        }
    }
    var onStatusChange: (@MainActor () -> Void)?
    private var bufferedClicks: [NotificationClick] = []
    private var userID: String?
    private var wantsSubscription = false
    private struct DisplayContext: Sendable {
        var identity = NotificationIdentity()
        var workspaceIDs: Set<String> = []
        var sessionID: String?
    }
    private nonisolated let displayContext = Mutex(DisplayContext())

    func start(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard Self.isCloudDeliveryEnabled, !isConfigured,
              !ProcessInfo.processInfo.arguments.contains("--fixture"),
              NSClassFromString("XCTestCase") == nil,
              let appID = Bundle.main.object(forInfoDictionaryKey: "KurageOneSignalAppID") as? String,
              UUID(uuidString: appID) != nil else { return }
        OneSignal.Debug.setLogLevel(.LL_NONE)
        OneSignal.initialize(appID, withLaunchOptions: launchOptions)
        // Account restoration must establish the native identity before subscribing.
        displayContext.withLock { $0.identity = NotificationIdentity(legacyRecipientID: OneSignal.User.externalId) }
        OneSignal.User.pushSubscription.optOut()
        OneSignal.Notifications.addClickListener(self)
        OneSignal.Notifications.addForegroundLifecycleListener(self)
        OneSignal.User.pushSubscription.addObserver(self)
        isConfigured = true
    }

    func identify(_ id: String?, enabled: Bool) {
        guard isConfigured else { return }
        let shouldClearDelivered = displayContext.withLock { context in
            let previousUserID = context.identity.userID ?? context.identity.legacyRecipientID
            context.identity.identify(id)
            context.workspaceIDs = []
            context.sessionID = nil
            return previousUserID != id
        }
        if shouldClearDelivered { clearDelivered() }
        OneSignal.User.pushSubscription.optOut()
        userID = id
        wantsSubscription = enabled && id != nil
        if let id, !id.isEmpty {
            OneSignal.login(id)
            if wantsSubscription && OneSignal.Notifications.permission { OneSignal.User.pushSubscription.optIn() }
        } else {
            OneSignal.logout()
            bufferedClicks.removeAll()
        }
    }

    func setSubscribed(_ enabled: Bool) {
        guard isConfigured else { return }
        wantsSubscription = enabled && userID != nil
        if wantsSubscription && OneSignal.Notifications.permission { OneSignal.User.pushSubscription.optIn() }
        else { OneSignal.User.pushSubscription.optOut() }
    }

    func status() async -> PushNotificationStatus {
        guard isConfigured else { return PushNotificationStatus() }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorization: NotificationAuthorization
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: authorization = .authorized
        case .denied: authorization = .denied
        default: authorization = .notDetermined
        }
        if authorization == .authorized, wantsSubscription, userID != nil,
           !OneSignal.User.pushSubscription.optedIn {
            OneSignal.User.pushSubscription.optIn()
        }
        let id = OneSignal.User.pushSubscription.id
        return PushNotificationStatus(authorization: authorization,
            isSubscribed: OneSignal.User.pushSubscription.optedIn,
            isRegistered: id?.isEmpty == false && id?.hasPrefix("local-") == false)
    }

    func requestAuthorization() async -> Bool {
        guard isConfigured else { return false }
        return await withCheckedContinuation { continuation in
            OneSignal.Notifications.requestPermission({ allowed in
                continuation.resume(returning: allowed)
            }, fallbackToSettings: false)
        }
    }

    func setVisibleSession(workspace: WorkspaceSummary?, sessionID: String?) {
        displayContext.withLock {
            $0.workspaceIDs = Set([workspace?.id, workspace?.slug].compactMap { $0 })
            $0.sessionID = sessionID
        }
    }

    func clearDelivered() {
        guard isConfigured else { return }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    nonisolated func onClick(event: OSNotificationClickEvent) {
        let context = displayContext.withLock { $0 }
        guard let id = event.notification.notificationId,
              let rawRoute = event.notification.additionalData?["route"] as? String,
              let route = NotificationRoute(rawRoute),
              let owner = context.identity.recipientUserID(
                event.notification.additionalData?["recipientUserId"] as? String) else { return }
        let click = NotificationClick(id: id, route: route, userID: owner)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let current = displayContext.withLock { $0 }
            guard current.identity.acceptsClick(userID: owner,
                capturedGeneration: context.identity.generation) else { return }
            if let onClick { onClick(click) }
            else { bufferedClicks = Array((bufferedClicks + [click]).suffix(8)) }
        }
    }

    nonisolated func onWillDisplay(event: OSNotificationWillDisplayEvent) {
        let recipient = event.notification.additionalData?["recipientUserId"] as? String
        let rawRoute = event.notification.additionalData?["route"] as? String
        let route = rawRoute.flatMap(NotificationRoute.init)
        let shouldDisplay = displayContext.withLock { context in
            guard let userID = context.identity.userID,
                  context.identity.recipientUserID(recipient) == userID else { return false }
            return route == nil || route?.sessionID != context.sessionID ||
                !context.workspaceIDs.contains(route?.workspace ?? "")
        }
        if !shouldDisplay { event.preventDefault() }
    }

    nonisolated func onPushSubscriptionDidChange(state: OSPushSubscriptionChangedState) {
        Task { @MainActor [weak self] in self?.onStatusChange?() }
    }
}

final class KurageAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        OneSignalNotificationService.shared.start(launchOptions: launchOptions)
        return true
    }
}
