import Foundation
import UserNotifications

/// Routes taps on a reminder notification's action buttons back to `ItemStore` via
/// `NotificationCenter`, since `UNUserNotificationCenter`'s delegate has no direct line to
/// SwiftUI state. Registered once, on launch, as `UNUserNotificationCenter.current().delegate`.
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationActionHandler()

    static let actionReceived = Notification.Name("LifeAdminNotificationActionReceived")
    static let markDoneIdentifier = "MARK_DONE"
    static let snoozeIdentifier = "SNOOZE_1_DAY"
    static let categoryIdentifier = "item-reminder"

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let idString = response.notification.request.content.userInfo["itemID"] as? String,
              let itemID = UUID(uuidString: idString) else { return }
        NotificationCenter.default.post(
            name: Self.actionReceived,
            object: nil,
            userInfo: ["itemID": itemID, "actionIdentifier": response.actionIdentifier]
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
