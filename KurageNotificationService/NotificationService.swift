import OneSignalExtension
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var request: UNNotificationRequest?
    private var content: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.request = request
        self.contentHandler = contentHandler
        content = request.content.mutableCopy() as? UNMutableNotificationContent
        guard let content else { contentHandler(request.content); return }
        OneSignalExtension.didReceiveNotificationExtensionRequest(request, with: content,
                                                                 withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        guard let contentHandler, let request, let content else { return }
        OneSignalExtension.serviceExtensionTimeWillExpireRequest(request, with: content)
        contentHandler(content)
    }
}
