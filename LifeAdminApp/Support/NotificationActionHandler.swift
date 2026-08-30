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
        guard let idString = response.notification.request.content.userInfo["itemID"] as? String,
              let itemID = UUID(uuidString: idString) else {
            completionHandler()
            return
        }
        // ItemStore's handler does its work asynchronously (SwiftData save, calendar/reminder
        // sync) after this posts. Calling completionHandler before that finishes tells iOS the
        // notification is fully handled — if the app was only launched in the background to
        // process this tap, the system is then free to suspend it before the action it promised
        // (Mark Done, Snooze) actually persists. Passing the handler along and firing it only
        // once that work completes keeps the process alive long enough for it to really happen.
        NotificationCenter.default.post(
            name: Self.actionReceived,
            object: nil,
            userInfo: ["itemID": itemID, "actionIdentifier": response.actionIdentifier, "completion": completionHandler]
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
