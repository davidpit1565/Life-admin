import SwiftUI
import SwiftData
import UserNotifications
import LifeAdminCore

@main
struct LifeAdminApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var store: ItemStore

    init() {
        UNUserNotificationCenter.current().delegate = NotificationActionHandler.shared
        let container = Self.makeModelContainer()
        modelContainer = container
        _store = StateObject(wrappedValue: ItemStore(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView().environmentObject(store)
        }
        .modelContainer(modelContainer)
    }

    /// A `try!` here means every future launch crashes identically if the on-disk store is ever
    /// corrupted (disk issues, an interrupted write, an incompatible schema change) — the user's
    /// only way out would be deleting and reinstalling, losing everything anyway. Falls back to a
    /// fresh on-disk store (wiping the corrupted one) and, if even that fails, to an in-memory
    /// store so the app can still open rather than crash-loop forever.
    private static func makeModelContainer() -> ModelContainer {
        if UITestSupport.isCapturingScreenshots {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: PersistedItem.self, configurations: configuration)
        }

        if let container = try? ModelContainer(for: PersistedItem.self) {
            protectDefaultStore()
            return container
        }

        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        if let container = try? ModelContainer(for: PersistedItem.self) {
            protectDefaultStore()
            return container
        }

        let inMemoryConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: PersistedItem.self, configurations: inMemoryConfiguration)
    }

    /// SwiftData gives this store no explicit protection level of its own — with no custom
    /// `ModelConfiguration`, it sits at iOS's default (`.completeUntilFirstUserAuthentication`:
    /// readable once the device has been unlocked even a single time since boot), even though it
    /// holds the same titles, notes, amounts, and contact emails `AttachmentStore` already treats
    /// as needing better than that. Matches AttachmentStore's own choice — unreadable whenever the
    /// device itself is locked, not merely before its first unlock since a reboot — applied after
    /// the fact via `FileManager.setAttributes`, since (unlike `AttachmentStore`'s own files,
    /// written directly with `Data.WritingOptions.completeFileProtection`) SwiftData creates and
    /// writes this file itself; the -wal/-shm siblings are SQLite's write-ahead-log files, which
    /// hold the same uncommitted row data and need the same protection.
    private static func protectDefaultStore() {
        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        for suffix in ["", "-wal", "-shm"] {
            let path = storeURL.path + suffix
            guard FileManager.default.fileExists(atPath: path) else { continue }
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        }
    }
}

/// Whether a just-added item needs the user's eyes on it before it's final ("Ask me first" mode)
/// or was already saved as-is — AddItemView uses this to decide whether to show a review screen
/// or a brief "here's what we understood" confirmation before closing.
enum AddOutcome {
    /// `isNewDraft` is true when this is a brand new, never-persisted item (so the review screen
    /// must persist it for the first time on Save); false when it's a preview of merging into an
    /// existing active item that already exists in `ItemStore.items` (so Save should update that
    /// real item in place instead). Either way nothing is written to SwiftData, scheduled, or
    /// synced to the calendar until the review screen's own Save/Mark Done actually runs — unlike
    /// every other outcome below, which is already fully committed by the time AddItemView sees
    /// it. Swiping this review sheet away without saving must leave no trace behind.
    case pendingReview(LifeAdminItem, isNewDraft: Bool)
    /// `merged` is true when this text matched an existing active item closely enough to update
    /// it in place instead of creating a near-duplicate — the confirmation banner says so instead
    /// of looking indistinguishable from a brand new item.
    case added(LifeAdminItem, merged: Bool)
    /// A multi-line paste ("Rent $1200\nGym $40\nNetflix $17") became more than one item — each
    /// one goes straight in rather than pending review, since a per-item confirmation step for
    /// every line in a pasted list would be more friction than the paste was meant to save.
    case addedMultiple([LifeAdminItem])
}

@MainActor
final class ItemStore: ObservableObject {
    @Published var items: [LifeAdminItem] = []
    private let modelContext: ModelContext
    private let aiService: LifeAdminAIService

    /// Read directly from UserDefaults (rather than @AppStorage, which only works in views) so
    /// the setting in Settings > AI takes effect on the very next add without any extra plumbing.
    /// Falls back to local-only whenever AI consent hasn't been explicitly granted (declined, or
    /// not yet asked) — this is the actual enforcement point for the consent screen in
    /// AIConsentView, not just its UI. No consent, no Gemini calls, regardless of this setting.
    private var autonomyMode: AIProcessingMode {
        guard UserDefaults.standard.string(forKey: "aiConsentDecision") == "granted" else { return .disabled }
        return AIProcessingMode(rawValue: UserDefaults.standard.string(forKey: "aiProcessingMode") ?? "") ?? .allowAutomatically
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.aiService = LifeAdminAIService(client: ProxyAIClient(endpoint: AppConfig.geminiProxyEndpoint, sharedSecret: AppConfig.geminiProxySharedSecret), reachability: NetworkPathReachability())
        if UITestSupport.isCapturingScreenshots {
            seedDemoDataForScreenshots()
        }
        load()
        observeNotificationActions()
    }

    /// Populates the in-memory store (see `makeModelContainer`) with a fixed, varied set of items
    /// so the screenshot UI test always has something worth photographing — an overdue bill, an
    /// upcoming insurance renewal, two same-category subscriptions (so Insights' overlap card has
    /// something to show), a passport with document fields, and an item due today for Calendar.
    /// Dates are relative to `Date()` so screenshots never show a stale "3 days ago" months later.
    private func seedDemoDataForScreenshots() {
        let calendar = Calendar.current
        func daysFromNow(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
        }

        let demoItems = [
            LifeAdminItem(title: "Electric Bill", category: .bills, priority: .high, dueDate: daysFromNow(-3), amount: 145, currency: "USD", recurrence: .monthly),
            LifeAdminItem(title: "Car Insurance Renewal", category: .insurance, priority: .high, dueDate: daysFromNow(12), amount: 1200, currency: "USD", recurrence: .yearly),
            LifeAdminItem(title: "Netflix", category: .subscriptions, priority: .low, dueDate: daysFromNow(5), amount: 17.99, currency: "USD", recurrence: .monthly),
            LifeAdminItem(title: "Spotify", category: .subscriptions, priority: .low, dueDate: daysFromNow(20), amount: 10.99, currency: "USD", recurrence: .monthly),
            LifeAdminItem(title: "Passport Renewal", category: .documents, priority: .medium, dueDate: daysFromNow(200), recurrence: .none, documentFields: [DocumentField(label: "Passport Number", value: "X1234567"), DocumentField(label: "Expiry Date", value: "2027-03-15")]),
            LifeAdminItem(title: "Credit Card Renewal", category: .money, priority: .medium, dueDate: daysFromNow(45), recurrence: .yearly, documentFields: [DocumentField(label: "Card Number", value: "•••• 4242"), DocumentField(label: "Expiry", value: "09/29")]),
            LifeAdminItem(title: "Car Service", category: .car, priority: .medium, dueDate: daysFromNow(0), amount: 220, currency: "USD", recurrence: .none)
        ]

        for item in demoItems {
            modelContext.insert(PersistedItem(item: item))
        }
        try? modelContext.save()
    }

    private func observeNotificationActions() {
        NotificationCenter.default.addObserver(forName: NotificationActionHandler.actionReceived, object: nil, queue: .main) { [weak self] note in
            let completion = note.userInfo?["completion"] as? () -> Void
            guard let itemID = note.userInfo?["itemID"] as? UUID, let actionIdentifier = note.userInfo?["actionIdentifier"] as? String else {
                completion?()
                return
            }
            Task { [weak self] in
                await self?.handleNotificationAction(itemID: itemID, actionIdentifier: actionIdentifier)
                completion?()
            }
        }
    }

    /// Lets the reminder notification itself act as a two-way interface — "Mark Done" or "Snooze"
    /// right from the banner — instead of requiring the user to open the app to close the loop.
    func handleNotificationAction(itemID: UUID, actionIdentifier: String) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items[index]
        switch actionIdentifier {
        case NotificationActionHandler.markDoneIdentifier:
            ActivityLog.shared.record(String(format: String(localized: "activityLog.markedDoneFromNotification"), item.title))
            await markCompleted(item)
        case NotificationActionHandler.snoozeIdentifier:
            // An item already well overdue (say, 10 days) snoozed from its own stale due date
            // would land 9 days in the past — still overdue, and ReminderEngine won't schedule a
            // notification for a past date, so the button would appear to work but silently do
            // nothing. Snoozing from "now" instead always produces a real future reminder.
            item.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: max(item.dueDate ?? Date(), Date()))
            ActivityLog.shared.record(String(format: String(localized: "activityLog.snoozedFromNotification"), item.title))
            await update(item)
        default:
            break
        }
    }

    private func load() {
        let descriptor = FetchDescriptor<PersistedItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        items = ((try? modelContext.fetch(descriptor)) ?? []).map { $0.asItem }
    }

    /// Requests every permission the app can use, all at once, right when it opens — rather
    /// than one at a time the first time each feature is actually used. Contacts isn't part of
    /// this: linking a contact only ever goes through the system contact picker (`ItemDetailView`),
    /// which needs no `CNContactStore` authorization at all — asking for it here would be an
    /// upfront request the app has no use for.
    func requestAllPermissionsUpfront() async {
        guard !UITestSupport.isCapturingScreenshots else { return }
        await NotificationScheduler.shared.requestAuthorizationIfNeeded()
        await CalendarSyncService.shared.requestAuthorizationIfNeeded()
        await refreshDigest()
    }

    /// Read-only extraction — parses `text` into structured fields without creating or persisting
    /// any item, for a caller that already has an item open and only wants to fill in its blank
    /// fields (`ItemDetailView`'s attachment auto-fill: OCR text from a just-added passport/
    /// insurance photo). Goes through the exact same `autonomyMode`/consent gate as every other
    /// AI use in the app — "Off" never reaches Gemini here either, and "Ask me first" still means
    /// only the local parser runs, same as `buildCandidate`.
    func extractFields(from text: String) async -> ExtractedItem {
        let mode = autonomyMode
        let decision = mode == .disabled ? aiService.extractLocalOnly(text) : await aiService.extract(text)
        return decision.item
    }

    /// When `true`, forces local-only processing for this add regardless of the user's AI
    /// Autonomy setting — the one enforcement point for what the AI consent screen promises
    /// ("nothing else: not your contacts, calendar, or photos"). A scanned passport/ID's
    /// recognized OCR text (full name, document number, date of birth, MRZ line) landing in this
    /// same free-text field as ordinary typed input would otherwise escalate to Gemini exactly
    /// like any other text whenever the local parser can't fully understand it on its own — which
    /// a scan almost always can't, since it rarely contains an obvious due date or amount.
    @discardableResult
    func add(text: String, attachments: [Attachment] = [], containsScannedText: Bool = false) async -> AddOutcome {
        let mode = containsScannedText ? .disabled : autonomyMode
        let entries = NaturalLanguageParser.splitEntries(text)
        guard entries.count > 1 else {
            // "Ask every time" builds the candidate but deliberately stops short of persisting it
            // — see the comment on `AddOutcome.pendingReview`. Every other mode commits right away,
            // exactly like before.
            let candidate = await buildCandidate(text: text, attachments: attachments, mode: mode)
            if mode == .askEveryTime {
                switch candidate {
                case .new(let item): return .pendingReview(item, isNewDraft: true)
                case .merge(let merged): return .pendingReview(merged, isNewDraft: false)
                }
            }
            let result = await commitCandidate(candidate)
            return .added(result.item, merged: result.wasMerged)
        }
        // A pasted list ("Rent $1200\nGym $40\nNetflix $17") always saves every line directly,
        // regardless of "ask every time" — reviewing N pasted items one at a time would be more
        // friction than the paste was meant to save. Only the first line keeps any attachment
        // (a scan), so it doesn't silently duplicate onto every split line.
        var addedItems: [LifeAdminItem] = []
        for (index, entry) in entries.enumerated() {
            let entryAttachments = index == 0 ? attachments : []
            let candidate = await buildCandidate(text: entry, attachments: entryAttachments, mode: mode)
            addedItems.append(await commitCandidate(candidate).item)
        }
        return .addedMultiple(addedItems)
    }

    private struct AddOneEntryResult {
        let item: LifeAdminItem
        let wasMerged: Bool
    }

    /// Everything `add(text:)` used to decide about one line of input before committing anything:
    /// either a brand new item, or a computed merge into an existing active item (same `id` as
    /// that existing item). Building this never touches SwiftData, notifications, or the calendar
    /// — see `commitCandidate`, the only place that actually does.
    private enum AddCandidate {
        case new(LifeAdminItem)
        case merge(LifeAdminItem)
    }

    private func buildCandidate(text: String, attachments: [Attachment], mode: AIProcessingMode) async -> AddCandidate {
        let decision = mode == .disabled ? aiService.extractLocalOnly(text) : await aiService.extract(text)
        let extracted = decision.item
        var item = LifeAdminItem(
            title: extracted.title ?? String(localized: "item.untitled"),
            category: extracted.category ?? .other,
            dueDate: extracted.date,
            amount: extracted.amount,
            currency: extracted.currency,
            recurrence: extracted.recurring ?? .none,
            reminderOffsets: extracted.reminderOffsets ?? ReminderEngine.defaultOffsets(for: extracted.category ?? .other),
            documentFields: (extracted.documentFields ?? []).map { DocumentField(label: $0.label, value: $0.value) }
        )
        item.priority = PriorityEngine().priority(for: item)
        item.attachments = attachments
        if FeatureFlags.moveDetectionEnabled {
            item.tags.append(contentsOf: LifeEventDetector().detectedTags(in: text))
        }
        // Not gated behind a feature flag, unlike moveDetectionEnabled above — this is a safety
        // signal, not a nice-to-have, so it should always be active rather than held back for a
        // later release.
        if extracted.scamRiskDetected == true {
            item.tags.append(NaturalLanguageParser.scamRiskTag)
        }
        if decision.usedAI {
            ActivityLog.shared.record(String(format: String(localized: "activityLog.aiHelped"), item.title))
        }

        // The user re-describing something they already logged (a repeated bill, a double-tapped
        // Save) should update that item in place rather than clutter the list with a near-copy.
        if let duplicate = items.first(where: { $0.status == .active && DuplicateDetector().isLikelyDuplicate($0, item) }) {
            var merged = duplicate
            merged.dueDate = item.dueDate ?? duplicate.dueDate
            merged.amount = item.amount ?? duplicate.amount
            merged.currency = item.currency ?? duplicate.currency
            merged.recurrence = item.recurrence != .none ? item.recurrence : duplicate.recurrence
            merged.attachments += item.attachments
            // Additive rather than a straight overwrite, unlike the scalar fields above: a second
            // scan of the same item (a renewed passport's new page, a card's back after its front)
            // should add to what's already known, not force a choice between keeping the old
            // details or losing them. Only genuinely new labels are added, so re-scanning the same
            // document twice doesn't pile up duplicate rows.
            let existingLabels = Set(merged.documentFields.map { $0.label.lowercased() })
            merged.documentFields += item.documentFields.filter { existingLabels.contains($0.label.lowercased()) == false }
            merged.updatedAt = Date()
            merged.priority = PriorityEngine().priority(for: merged)
            return .merge(merged)
        }

        // A recurring bill mentioned again months later rarely repeats the contact info the user
        // already gave once — carry it forward instead of leaving it blank again.
        if FeatureFlags.contactContinuityAutoFillEnabled, item.contact == nil, let priorMatch = items.first(where: { $0.title.caseInsensitiveCompare(item.title) == .orderedSame && $0.contact != nil }) {
            item.contact = priorMatch.contact
            ActivityLog.shared.record(String(format: String(localized: "activityLog.contactAutoFilled"), item.title))
        }

        return .new(item)
    }

    private func commitCandidate(_ candidate: AddCandidate) async -> AddOneEntryResult {
        switch candidate {
        case .merge(let merged):
            ActivityLog.shared.record(String(format: String(localized: "activityLog.merged"), merged.title))
            await update(merged)
            return AddOneEntryResult(item: merged, wasMerged: true)
        case .new(let item):
            return AddOneEntryResult(item: await persistNewItem(item), wasMerged: false)
        }
    }

    /// The second half of adding an item once its title/category/recurrence/etc. are already
    /// decided — shared by `commitCandidate` (decided by AI/local NL parsing) and `ItemDetailView`
    /// (saving a checklist-suggested or "ask every time" draft for the first time) so persistence,
    /// scheduling, and calendar sync only exist in one place.
    func persistNewItem(_ item: LifeAdminItem) async -> LifeAdminItem {
        let persisted = PersistedItem(item: item)
        modelContext.insert(persisted)
        try? modelContext.save()
        items.insert(item, at: 0)

        await NotificationScheduler.shared.requestAuthorizationIfNeeded()
        await NotificationScheduler.shared.schedule(for: item)

        await CalendarSyncService.shared.requestAuthorizationIfNeeded()
        let sync = CalendarSyncService.shared.sync(item: item, existingEventID: nil, existingReminderID: nil)
        persisted.calendarEventIdentifier = sync.eventIdentifier
        persisted.reminderIdentifier = sync.reminderIdentifier
        try? modelContext.save()
        flagCalendarSyncIssueIfNeeded(dueDate: item.dueDate, eventIdentifier: sync.eventIdentifier)

        await refreshDigest()
        return item
    }

    /// Builds an item straight from a tapped checklist suggestion — bypasses AI/local NL parsing
    /// entirely, unlike `add(text:)`, since the category and recurrence are already known from the
    /// suggestion itself. That's not just simpler: NaturalLanguageParser only deeply understands
    /// recurrence phrasing in English/Hebrew/Spanish/French, so generating a sentence and parsing
    /// it back would silently lose the intended recurrence in the app's other locales.
    ///
    /// Deliberately does NOT persist: the returned item is only a draft handed to the review
    /// sheet. Persisting here would leave a blank, hard-to-find item behind whenever the user
    /// dismisses that sheet without saving — `ItemDetailView` persists it (via `persistNewItem`)
    /// only once the user actually taps Save or Mark Done.
    func draftItem(for suggestion: ChecklistSuggestion) -> LifeAdminItem {
        var item = LifeAdminItem(
            title: NSLocalizedString(suggestion.titleKey, comment: ""),
            category: suggestion.category,
            recurrence: suggestion.suggestedRecurrence,
            reminderOffsets: ReminderEngine.defaultOffsets(for: suggestion.category)
        )
        item.priority = PriorityEngine().priority(for: item)
        // Logged here rather than once the draft is actually saved: it's a purely informational
        // log entry (unlike persistence, scheduling, or calendar sync, it has no real-world
        // effect to undo), and the alternative — threading "this came from the checklist" all the
        // way through ItemDetailView's save()/markDone(), which also serves the unrelated "ask
        // every time" AI review draft — would risk misattributing the wrong entry to the wrong
        // source.
        ActivityLog.shared.record(String(format: String(localized: "activityLog.addedFromChecklist"), item.title))
        return item
    }

    private func refreshDigest() async {
        await NotificationScheduler.shared.scheduleDailyDigest(items: items)
        // Reads the same UserDefaults key ChecklistView's own @AppStorage writes to — ItemStore
        // isn't a View and can't use the property wrapper itself, but it's the identical
        // underlying storage, so the two always agree on what's been dismissed.
        let dismissedIDs = Set((UserDefaults.standard.string(forKey: "checklistDismissedIDs") ?? "").split(separator: ",").map(String.init))
        let hasOutstanding = ChecklistEngine().outstandingSuggestions(items: items, dismissedIDs: dismissedIDs).isEmpty == false
        await NotificationScheduler.shared.scheduleChecklistNudge(hasOutstandingSuggestions: hasOutstanding)
    }

    func update(_ item: LifeAdminItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        // Self-heal rather than silently drop the edit: if the persisted record can't be found
        // (it shouldn't normally happen, but a mismatch here would otherwise make the in-memory
        // change look like it saved while actually vanishing on the next launch), recreate it
        // instead of returning early.
        let persisted = fetchPersisted(item.id) ?? {
            let created = PersistedItem(item: item)
            modelContext.insert(created)
            return created
        }()
        persisted.apply(item)

        let sync = CalendarSyncService.shared.sync(item: item, existingEventID: persisted.calendarEventIdentifier, existingReminderID: persisted.reminderIdentifier)
        persisted.calendarEventIdentifier = sync.eventIdentifier
        persisted.reminderIdentifier = sync.reminderIdentifier
        try? modelContext.save()
        flagCalendarSyncIssueIfNeeded(dueDate: item.dueDate, eventIdentifier: sync.eventIdentifier)

        await NotificationScheduler.shared.schedule(for: item)
        await refreshDigest()
    }

    /// Non-blocking, self-dismissing notice (rendered by RootTabView) for the one case that used
    /// to fail in total silence: a sync just ran for an item with a due date, produced no calendar
    /// event, and Calendar access genuinely isn't fully granted. Never fires for an item with no
    /// due date, or once access is fully granted, so it can't nag someone who never wanted this
    /// feature synced in the first place.
    private func flagCalendarSyncIssueIfNeeded(dueDate: Date?, eventIdentifier: String?) {
        guard dueDate != nil, eventIdentifier == nil, CalendarSyncService.hasFullCalendarAccess() == false else { return }
        calendarSyncWarningTask?.cancel()
        calendarSyncWarningVisible = true
        calendarSyncWarningTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard Task.isCancelled == false else { return }
            self?.calendarSyncWarningVisible = false
        }
    }

    private func fetchPersisted(_ id: UUID) -> PersistedItem? {
        let descriptor = FetchDescriptor<PersistedItem>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    /// The single place every "mark done" path (the detail screen's button, a swipe action, or
    /// the notification action) goes through, so a recurring item's whole point — that it keeps
    /// coming back — actually happens, instead of only ever firing once before the reminder is
    /// gone for good.
    func markCompleted(_ item: LifeAdminItem) async {
        // A stale already-delivered notification tapped after the item was already completed
        // elsewhere (or any other double "Mark Done" — two taps on the same row, a notification
        // action racing the Save button) would otherwise create a second "next occurrence" below
        // for a recurring item — a duplicate bill/reminder that isn't actually due yet. Checking
        // `items` (the live, current store state) rather than `item.status` (the caller's own
        // possibly-stale snapshot, always still `.active` at this point on the normal call path)
        // is what actually makes that guard work: two overlapping calls each capture their own
        // `item` before either one runs, so both would see `.active` and both proceed if this
        // checked the parameter instead. Safe against the race precisely because everything here
        // up to and including `update()`'s own synchronous prefix runs without yielding the main
        // actor, so whichever call's Task body starts first fully applies its own completion
        // before the second one's guard ever gets a chance to run.
        guard items.first(where: { $0.id == item.id })?.status == .active else { return }
        var completed = item
        completed.status = .completed
        await update(completed)
        // `update()` above still syncs a calendar event/reminder off the (now completed) item's
        // own dueDate — the event/reminder already did its job of surfacing the due date, and a
        // completed item has no business still sitting on the system Calendar (often iCloud-
        // shared with family) or in Reminders. Previously only `archive()` did this; a paid bill
        // or renewed passport marked done left its event there permanently, and for a recurring
        // item this repeated every single cycle since RecurrenceEngine.nextOccurrence always
        // allocates a fresh id that never touches the completed occurrence's own event again.
        clearCalendarSync(for: completed)

        guard let next = RecurrenceEngine().nextOccurrence(of: completed) else { return }
        await createRecurringOccurrence(next)
    }

    /// Distinct from `delete`: keeps the record (and its history/attachments) around, just off
    /// every everyday list — `.archived` is an `ItemStatus` case the data model already had, with
    /// nothing that ever actually set it until now.
    func archive(_ item: LifeAdminItem) async {
        var archived = item
        archived.status = .archived
        await update(archived)
        clearCalendarSync(for: archived)
    }

    /// Removes any calendar event/reminder synced for `item`'s own dueDate — shared by
    /// `markCompleted` and `archive`, the two places an item stops needing to show up on the
    /// system Calendar/Reminders while it's still allowed to exist (unlike `delete`, which
    /// removes the item's own row entirely and already does its own cleanup there). Works on a
    /// transient local copy with `dueDate` cleared, not `item` itself, so the item's own dueDate
    /// stays intact (in memory and persisted) for if it's ever reopened/unarchived later.
    private func clearCalendarSync(for item: LifeAdminItem) {
        guard let persisted = fetchPersisted(item.id) else { return }
        var cleared = item
        cleared.dueDate = nil
        let sync = CalendarSyncService.shared.sync(item: cleared, existingEventID: persisted.calendarEventIdentifier, existingReminderID: persisted.reminderIdentifier)
        persisted.calendarEventIdentifier = sync.eventIdentifier
        persisted.reminderIdentifier = sync.reminderIdentifier
        try? modelContext.save()
    }

    private func createRecurringOccurrence(_ item: LifeAdminItem) async {
        var newItem = item
        newItem.priority = PriorityEngine().priority(for: newItem)
        let persisted = PersistedItem(item: newItem)
        modelContext.insert(persisted)
        try? modelContext.save()
        items.insert(newItem, at: 0)

        await NotificationScheduler.shared.schedule(for: newItem)
        let sync = CalendarSyncService.shared.sync(item: newItem, existingEventID: nil, existingReminderID: nil)
        persisted.calendarEventIdentifier = sync.eventIdentifier
        persisted.reminderIdentifier = sync.reminderIdentifier
        try? modelContext.save()

        ActivityLog.shared.record(String(format: String(localized: "activityLog.recurrenceCreated"), newItem.title))
        await refreshDigest()
    }

    @Published var pendingUndo: LifeAdminItem?
    private var pendingDeletions: [UUID: Task<Void, Never>] = [:]

    /// Drives the brief, self-dismissing "not added to your calendar" banner in RootTabView —
    /// see `flagCalendarSyncIssueIfNeeded` below.
    @Published var calendarSyncWarningVisible = false
    private var calendarSyncWarningTask: Task<Void, Never>?

    /// Removes `item` from view immediately, so a swipe-to-delete feels instant, but defers the
    /// destructive part — freeing attachment files, canceling notifications, removing the
    /// SwiftData record — for a few seconds, so `undoDelete` can put it back with nothing lost.
    func scheduleDelete(_ item: LifeAdminItem) {
        // Guards against a second scheduleDelete call for the same id ever orphaning the first
        // Task — without cancelling it here, an earlier still-running deletion would carry out
        // its own delete(item) after its 4s regardless of anything this second call or a later
        // undo does.
        pendingDeletions[item.id]?.cancel()
        items.removeAll { $0.id == item.id }
        pendingUndo = item
        pendingDeletions[item.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard Task.isCancelled == false else { return }
            await self?.delete(item)
            if self?.pendingUndo?.id == item.id { self?.pendingUndo = nil }
            self?.pendingDeletions[item.id] = nil
        }
    }

    func undoDelete() {
        guard let item = pendingUndo else { return }
        pendingDeletions[item.id]?.cancel()
        pendingDeletions[item.id] = nil
        pendingUndo = nil
        items.insert(item, at: 0)
    }

    func delete(_ item: LifeAdminItem) async {
        // Always remove from the in-memory list and cancel notifications, even if the persisted
        // record can't be found — otherwise a lookup mismatch would make "Delete" silently do
        // nothing visible, leaving the item sitting right where it was.
        if let persisted = fetchPersisted(item.id) {
            var cleared = item
            cleared.dueDate = nil
            _ = CalendarSyncService.shared.sync(item: cleared, existingEventID: persisted.calendarEventIdentifier, existingReminderID: persisted.reminderIdentifier)
            modelContext.delete(persisted)
            try? modelContext.save()
        }
        // A deleted item's scanned files have nowhere left to be shown — leaving them on disk
        // would just accumulate orphaned files forever.
        item.attachments.forEach(AttachmentStore.shared.delete)
        await NotificationScheduler.shared.cancel(for: item.id)
        items.removeAll { $0.id == item.id }
        await refreshDigest()
    }

    /// Settings > "Delete All My Data" — a full, irreversible wipe of every item, unlike
    /// `delete(_:)`/`scheduleDelete(_:)` there is no undo. Runs the same per-item cleanup
    /// `delete(_:)` already does (calendar event/reminder removal, notification cancellation,
    /// attachment files) for every item, then sweeps the model context directly so every
    /// `PersistedItem` is gone even if it somehow drifted out of sync with `items`.
    func deleteAllData() async {
        // A delete already in its undo window would otherwise still fire after this finishes and
        // look up a persisted row that's already gone — harmless (its own guards no-op), but
        // cancelling it here avoids any latent Task outliving a full wipe.
        pendingDeletions.values.forEach { $0.cancel() }
        pendingDeletions = [:]
        pendingUndo = nil

        for item in items {
            if let persisted = fetchPersisted(item.id) {
                var cleared = item
                cleared.dueDate = nil
                _ = CalendarSyncService.shared.sync(item: cleared, existingEventID: persisted.calendarEventIdentifier, existingReminderID: persisted.reminderIdentifier)
            }
            item.attachments.forEach(AttachmentStore.shared.delete)
            await NotificationScheduler.shared.cancel(for: item.id)
        }

        let allPersisted = (try? modelContext.fetch(FetchDescriptor<PersistedItem>())) ?? []
        allPersisted.forEach(modelContext.delete)
        try? modelContext.save()

        items = []
        await refreshDigest()
    }

    /// Restoring a backup (new phone, or handing a JSON export to someone else) should be as safe
    /// to repeat as it is to run once — skip anything whose ID is already present instead of
    /// duplicating every item on a second import of the same file.
    func importItems(_ imported: [LifeAdminItem]) async {
        // scheduleDelete removes an item from `items` immediately but leaves its PersistedItem
        // row on disk for a few seconds (so undo can restore it) — without also excluding those
        // IDs here, importing a backup containing that same item during that window would insert
        // a second row with the same @Attribute(.unique) id, and the delayed deletion would then
        // go on to remove the row (and its attachments) the import had just recreated.
        let existingIDs = Set(items.map(\.id)).union(pendingDeletions.keys)
        let newItems = imported.filter { existingIDs.contains($0.id) == false }
        guard newItems.isEmpty == false else { return }

        await NotificationScheduler.shared.requestAuthorizationIfNeeded()
        await CalendarSyncService.shared.requestAuthorizationIfNeeded()
        var processedItems: [LifeAdminItem] = []
        for var item in newItems {
            // A JSON export carries only the attachment's metadata, never the file bytes — an
            // item imported on a different install can never actually have that file (unlike an
            // OS-level backup restore, which AttachmentStore.url(for:) already handles). Keeping
            // the reference would leave a permanently-broken row with no way to know why it never
            // loads.
            item.attachments = item.attachments.filter { AttachmentStore.shared.exists($0) }
            let persisted = PersistedItem(item: item)
            modelContext.insert(persisted)
            await NotificationScheduler.shared.schedule(for: item)
            let sync = CalendarSyncService.shared.sync(item: item, existingEventID: nil, existingReminderID: nil)
            persisted.calendarEventIdentifier = sync.eventIdentifier
            persisted.reminderIdentifier = sync.reminderIdentifier
            processedItems.append(item)
        }
        // One bulk insert at the front rather than `items.insert(item, at: 0)` inside the loop
        // above — repeating a front-insert once per item is O(existing items) every time, making
        // a large backup restore against an already-large library quadratic for no real reason.
        // Reversed so the result preserves the same "most-recently-imported first" order the old
        // per-item insert produced.
        items.insert(contentsOf: processedItems.reversed(), at: 0)
        try? modelContext.save()
        ActivityLog.shared.record(String(format: String(localized: "activityLog.imported"), newItems.count))
        await refreshDigest()
    }

    func markAddressSynced(_ itemID: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items[index]
        if item.tags.contains(AddressChangeEngine.syncedTag) == false {
            item.tags.append(AddressChangeEngine.syncedTag)
            ActivityLog.shared.record(String(format: String(localized: "activityLog.addressUpdateSent"), item.title))
        }
        await update(item)
    }
}
