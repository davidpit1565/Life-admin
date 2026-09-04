import Foundation
import EventKit
import LifeAdminCore

struct CalendarSyncService {
    static let shared = CalendarSyncService()

    struct SyncResult {
        var eventIdentifier: String?
        var reminderIdentifier: String?
        /// True exactly when this item needed a calendar event (active/snoozed, with a due date)
        /// but Calendar access wasn't fully granted on this attempt — distinct from
        /// `eventIdentifier` merely being nil, which also happens with nothing wrong before
        /// access was ever granted the first time. Confirmed bug this closes: `eventIdentifier`
        /// used to default to the *previous* identifier and was never reset once access was
        /// revoked mid-use, so the caller's own "warn if eventIdentifier == nil" check could
        /// never fire — an item's calendar event silently went stale (stuck on its old due date)
        /// with no warning shown, ever, after the user revoked Calendar access in iOS Settings.
        var eventNeedsAccess = false
    }

    private let store = EKEventStore()

    func requestAuthorizationIfNeeded() async {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
    }

    /// Creates or updates a calendar event and a reminder for `item`'s due date, reusing
    /// `existingEventID`/`existingReminderID` when present instead of creating duplicates.
    /// Removes both and returns nil identifiers if the item no longer has a due date, or if the
    /// item isn't active/snoozed.
    ///
    /// The status check matters on its own, separately from any due date: `ItemStore.update(_:)`
    /// runs on every edit, including editing a completed or archived item's notes/title long
    /// after `markCompleted`/`archive` already cleared its calendar entry — without this guard,
    /// that edit passed the item's still-intact `dueDate` straight through and silently recreated
    /// the very event/reminder that completing or archiving the item was supposed to remove for
    /// good, making it reappear on every subsequent edit.
    func sync(item: LifeAdminItem, existingEventID: String?, existingReminderID: String?) -> SyncResult {
        let isActiveOrSnoozed = item.status == .active || item.status == .snoozed
        guard isActiveOrSnoozed, let dueDate = item.dueDate else {
            removeEvent(identifier: existingEventID)
            removeReminder(identifier: existingReminderID)
            return SyncResult(eventIdentifier: nil, reminderIdentifier: nil)
        }

        var result = SyncResult(eventIdentifier: existingEventID, reminderIdentifier: existingReminderID)
        // The same "don't show this verbatim outside the app" rule NotificationScheduler already
        // applies to a sensitive category's lock-screen notification — a synced system Calendar
        // (often iCloud-shared with family) and Reminders list are just as much "outside the app"
        // as a lock screen, and neither gets any file-protection or App Lock guard of its own.
        let title = item.category.isSensitive ? String(localized: "notification.reminderTitle") : item.title

        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let event = existingEventID.flatMap(store.event(withIdentifier:)) ?? EKEvent(eventStore: store)
            if event.calendar == nil { event.calendar = store.defaultCalendarForNewEvents }
            event.title = title
            event.startDate = dueDate
            event.endDate = dueDate.addingTimeInterval(3600)
            if (try? store.save(event, span: .thisEvent, commit: true)) != nil {
                result.eventIdentifier = event.eventIdentifier
            }
        } else {
            result.eventNeedsAccess = true
        }

        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            let existingReminder = existingReminderID.flatMap(store.calendarItem(withIdentifier:)) as? EKReminder
            let reminder = existingReminder ?? EKReminder(eventStore: store)
            if reminder.calendar == nil { reminder.calendar = store.defaultCalendarForNewReminders() }
            reminder.title = title
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.isCompleted = item.status == .completed
            // Without this, the reminder shows a due date in the Reminders app but never actually
            // alerts at any of it — a due date alone doesn't schedule a notification the way an
            // alarm does. Replaced wholesale on every sync (this runs on every edit, not just
            // once), the same recompute-and-replace pattern NotificationScheduler.schedule(for:)
            // already uses for this app's own local notifications, from the identical source of
            // truth (ReminderEngine.notificationDates) so both stay in agreement.
            reminder.alarms = ReminderEngine().notificationDates(for: item).map { EKAlarm(absoluteDate: $0) }
            if (try? store.save(reminder, commit: true)) != nil {
                result.reminderIdentifier = reminder.calendarItemIdentifier
            }
        }

        return result
    }

    private func removeEvent(identifier: String?) {
        guard let identifier, let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    private func removeReminder(identifier: String?) {
        guard let identifier, let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        try? store.remove(reminder, commit: true)
    }
}
