import Foundation
import UserNotifications
import LifeAdminCore

// An actor, not a plain struct: `schedule(for:)` does cancel-then-add-fresh, and `cancel(for:)`
// itself does two separate awaited system calls in between — real suspension points. Two
// overlapping calls for the same item (e.g. the notification-action handler's "Mark Done" racing
// a Save from ItemDetailView, both routing through ItemStore.update → schedule) could interleave:
// call B's cancel() running before call A finished adding its own requests would leave some of
// A's requests never removed by B, even though B computed a different/shorter date list — stale
// notifications that don't match the item's current state, firing at the wrong time later. An
// actor serializes every call into and out of this type, closing that window; every existing call
// site already used `await NotificationScheduler.shared.…`, which is exactly what a cross-actor
// call already requires, so nothing downstream needed to change.
actor NotificationScheduler {
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
        let actions: [UNNotificationAction]
        if FeatureFlags.notificationActionButtonsEnabled {
            let markDone = UNNotificationAction(identifier: NotificationActionHandler.markDoneIdentifier, title: String(localized: "notification.action.markDone"), options: [])
            let snooze = UNNotificationAction(identifier: NotificationActionHandler.snoozeIdentifier, title: String(localized: "notification.action.snooze"), options: [])
            actions = [markDone, snooze]
        } else {
            actions = []
        }
        let category = UNNotificationCategory(identifier: NotificationActionHandler.categoryIdentifier, actions: actions, intentIdentifiers: [], options: [])
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
            content.body = item.category.isSensitive ? String(localized: "notification.reminderBodyGeneric") : item.title
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
        let prefix = Self.identifierPrefix(itemID: itemID)
        let pending = await center.pendingNotificationRequests()
        let pendingIDsToRemove = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if pendingIDsToRemove.isEmpty == false {
            center.removePendingNotificationRequests(withIdentifiers: pendingIDsToRemove)
        }
        // A reminder already showing in the Notification Center or on the lock screen isn't
        // touched by removePendingNotificationRequests above (that only stops *future* triggers) —
        // left alone, it would stay fully tappable after the item it points to was completed or
        // deleted elsewhere, including its "Mark Done"/"Snooze" action buttons once those ship.
        let delivered = await center.deliveredNotifications()
        let deliveredIDsToRemove = delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        if deliveredIDsToRemove.isEmpty == false {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDsToRemove)
        }
    }

    /// Re-derives and reschedules the once-a-day "here's what actually needs you" summary from
    /// the current items, so the app proactively surfaces what matters instead of waiting for the
    /// user to open it and check. Skipped entirely when nothing is overdue or due today, so it
    /// never nags when there's nothing to say.
    func scheduleDailyDigest(items: [LifeAdminItem], calendar: Calendar = .current, now: Date = Date()) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.digestIdentifier])
        guard FeatureFlags.dailyDigestEnabled else { return }

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

    /// A weekly, genuinely repeating nudge for outstanding checklist suggestions — deliberately
    /// not daily (nobody wants to be reminded every day about a passport reminder they haven't
    /// added yet), and deliberately a fixed `repeats: true` weekday/hour trigger rather than the
    /// one-shot-rescheduled-on-every-change approach `scheduleDailyDigest` uses above: recomputing
    /// this every time any item changes would keep pushing "next week" further away for an active
    /// user, and it would never actually fire. The trade-off is that its body can't safely name a
    /// live count (a repeating trigger's content is fixed at schedule time, so a number here would
    /// go stale) — it stays generic, and the app itself shows the real, current list.
    private static let checklistNudgeIdentifier = "checklist-nudge"

    func scheduleChecklistNudge(hasOutstandingSuggestions: Bool) async {
        guard hasOutstandingSuggestions else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.checklistNudgeIdentifier])
            return
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.checklistNudgeTitle")
        content.body = String(localized: "notification.checklistNudgeBody")
        content.sound = .default

        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = 10
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: Self.checklistNudgeIdentifier, content: content, trigger: trigger)
        // Re-adding under the same identifier each time this runs is idempotent — a
        // weekday/hour-only trigger always resolves to the same next occurrence regardless of how
        // often it's (re)scheduled, unlike a relative "N days from now" trigger would.
        try? await center.add(request)
    }

    private func digestBody(_ summary: DigestEngine.Summary) -> String {
        let countPhrase: String
        if summary.overdueCount > 0 {
            countPhrase = String(format: String(localized: "notification.digestOverdue"), summary.overdueCount)
        } else {
            countPhrase = String(format: String(localized: "notification.digestDueToday"), summary.dueTodayCount)
        }
        // Rank by consequence, not just chronology: name the single most urgent item so the
        // notification is a decision, not just a count — but only when it's safe to show on a
        // lock screen (see LifeCategory.isSensitive).
        guard let top = summary.topItem, top.category.isSensitive == false else { return countPhrase }
        return String(format: String(localized: "notification.digestBodyWithTopItem"), countPhrase, top.title)
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
