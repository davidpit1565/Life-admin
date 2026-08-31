import Foundation
import EventKit
import LifeAdminCore

struct CalendarSyncService {
    static let shared = CalendarSyncService()

    struct SyncResult {
        var eventIdentifier: String?
        var reminderIdentifier: String?
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
    /// Removes both and returns nil identifiers if the item no longer has a due date.
    func sync(item: LifeAdminItem, existingEventID: String?, existingReminderID: String?) -> SyncResult {
        guard let dueDate = item.dueDate else {
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
        }

        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            let existingReminder = existingReminderID.flatMap(store.calendarItem(withIdentifier:)) as? EKReminder
            let reminder = existingReminder ?? EKReminder(eventStore: store)
            if reminder.calendar == nil { reminder.calendar = store.defaultCalendarForNewReminders() }
            reminder.title = title
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.isCompleted = item.status == .completed
            if (try? store.save(reminder, commit: true)) != nil {
                result.reminderIdentifier = reminder.calendarItemIdentifier
            }
        }

        return result
    }

    /// Whether Calendar access is fully granted — lets a caller tell a genuine "sync produced no
    /// event because permission isn't there" apart from an item simply having no due date.
    /// Static since it only reads a system-wide authorization status, no store instance needed.
    static func hasFullCalendarAccess() -> Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
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
