import Foundation
import UserNotifications
import LifeAdminCore

struct NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() async {
        registerActionCategories()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Lets a reminder's own notification banner act as a two-way interface — the buttons are
    /// wired up in `NotificationActionHandler`. Registering categories doesn't require
    /// authorization, so this runs every launch regardless of the user's permission choice.
    private func registerActionCategories() {
        let markDone = UNNotificationAction(identifier: NotificationActionHandler.markDoneIdentifier, title: String(localized: "notification.action.markDone"), options: [])
        let snooze = UNNotificationAction(identifier: NotificationActionHandler.snoozeIdentifier, title: String(localized: "notification.action.snooze"), options: [])
        let category = UNNotificationCategory(identifier: NotificationActionHandler.categoryIdentifier, actions: [markDone, snooze], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
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
            content.categoryIdentifier = NotificationActionHandler.categoryIdentifier
            content.userInfo = ["itemID": item.id.uuidString]

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

    /// Re-derives and reschedules the once-a-day "here's what actually needs you" summary from
    /// the current items, so the app proactively surfaces what matters instead of waiting for the
    /// user to open it and check. Skipped entirely when nothing is overdue or due today, so it
    /// never nags when there's nothing to say.
    func scheduleDailyDigest(items: [LifeAdminItem], calendar: Calendar = .current, now: Date = Date()) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.digestIdentifier])

        let summary = DigestEngine().summary(for: items, now: now, calendar: calendar)
        guard DigestEngine().shouldNotify(summary) else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        guard let fireDate = Self.nextDigestFireDate(after: now, calendar: calendar) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.digestTitle")
        content.body = digestBody(summary)
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Self.digestIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func digestBody(_ summary: DigestEngine.Summary) -> String {
        if summary.overdueCount > 0 {
            return String(format: String(localized: "notification.digestOverdue"), summary.overdueCount)
        }
        return String(format: String(localized: "notification.digestDueToday"), summary.dueTodayCount)
    }

    private static let digestIdentifier = "daily-digest"

    private static func nextDigestFireDate(after now: Date, calendar: Calendar, hour: Int = 8, minute: Int = 0) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        guard let todayAtHour = calendar.date(from: components) else { return nil }
        if todayAtHour > now { return todayAtHour }
        return calendar.date(byAdding: .day, value: 1, to: todayAtHour)
    }

    private static func identifierPrefix(itemID: UUID) -> String {
        "item-\(itemID.uuidString)-"
    }

    private static func identifier(itemID: UUID, index: Int) -> String {
        "\(identifierPrefix(itemID: itemID))\(index)"
    }
}
