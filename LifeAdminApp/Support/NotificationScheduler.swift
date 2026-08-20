import Foundation
import UserNotifications
import LifeAdminCore

struct NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(for item: LifeAdminItem) async {
        await cancel(for: item.id)
        let dates = ReminderEngine().notificationDates(for: item)
        guard dates.isEmpty == false else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "notification.reminderTitle")
            content.body = item.title
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: Self.identifier(itemID: item.id, index: index), content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancel(for itemID: UUID) async {
        let pending = await center.pendingNotificationRequests()
        let prefix = Self.identifierPrefix(itemID: itemID)
        let idsToRemove = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard idsToRemove.isEmpty == false else { return }
        center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
    }

    private static func identifierPrefix(itemID: UUID) -> String {
        "item-\(itemID.uuidString)-"
    }

    private static func identifier(itemID: UUID, index: Int) -> String {
        "\(identifierPrefix(itemID: itemID))\(index)"
    }
}
