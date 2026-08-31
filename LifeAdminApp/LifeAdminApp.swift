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
        if let container = try? ModelContainer(for: PersistedItem.self) {
            return container
        }

        let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        if let container = try? ModelContainer(for: PersistedItem.self) {
            return container
        }

        let inMemoryConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: PersistedItem.self, configurations: inMemoryConfiguration)
    }
}

/// Whether a just-added item needs the user's eyes on it before it's final ("Ask me first" mode)
/// or was already saved as-is — AddItemView uses this to decide whether to show a review screen
/// or a brief "here's what we understood" confirmation before closing.
enum AddOutcome {
    case pendingReview(LifeAdminItem)
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
        load()
        observeNotificationActions()
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
        await NotificationScheduler.shared.requestAuthorizationIfNeeded()
        await CalendarSyncService.shared.requestAuthorizationIfNeeded()
        await refreshDigest()
    }

    @discardableResult
    func add(text: String, attachments: [Attachment] = []) async -> AddOutcome {
        let mode = autonomyMode
        let entries = NaturalLanguageParser.splitEntries(text)
        guard entries.count > 1 else {
            let result = await addOneEntry(text: text, attachments: attachments, mode: mode)
            return mode == .askEveryTime ? .pendingReview(result.item) : .added(result.item, merged: result.wasMerged)
        }
        // A pasted list ("Rent $1200\nGym $40\nNetflix $17") always saves every line directly,
        // regardless of "ask every time" — reviewing N pasted items one at a time would be more
        // friction than the paste was meant to save. Only the first line keeps any attachment
        // (a scan), so it doesn't silently duplicate onto every split line.
        var addedItems: [LifeAdminItem] = []
        for (index, entry) in entries.enumerated() {
            let entryAttachments = index == 0 ? attachments : []
            addedItems.append(await addOneEntry(text: entry, attachments: entryAttachments, mode: mode).item)
        }
        return .addedMultiple(addedItems)
    }

    private struct AddOneEntryResult {
        let item: LifeAdminItem
        let wasMerged: Bool
    }

    private func addOneEntry(text: String, attachments: [Attachment], mode: AIProcessingMode) async -> AddOneEntryResult {
        let decision = mode == .disabled ? aiService.extractLocalOnly(text) : await aiService.extract(text)
        let extracted = decision.item
        var item = LifeAdminItem(
            title: extracted.title ?? String(localized: "item.untitled"),
            category: extracted.category ?? .other,
            dueDate: extracted.date,
            amount: extracted.amount,
            currency: extracted.currency,
            recurrence: extracted.recurring ?? .none,
            reminderOffsets: extracted.reminderOffsets ?? [30]
        )
        item.priority = PriorityEngine().priority(for: item)
        item.attachments = attachments
        if FeatureFlags.moveDetectionEnabled {
            item.tags.append(contentsOf: LifeEventDetector().detectedTags(in: text))
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
            merged.updatedAt = Date()
            merged.priority = PriorityEngine().priority(for: merged)
            ActivityLog.shared.record(String(format: String(localized: "activityLog.merged"), merged.title))
            await update(merged)
            return AddOneEntryResult(item: merged, wasMerged: true)
        }

        // A recurring bill mentioned again months later rarely repeats the contact info the user
        // already gave once — carry it forward instead of leaving it blank again.
        if FeatureFlags.contactContinuityAutoFillEnabled, item.contact == nil, let priorMatch = items.first(where: { $0.title.caseInsensitiveCompare(item.title) == .orderedSame && $0.contact != nil }) {
            item.contact = priorMatch.contact
            ActivityLog.shared.record(String(format: String(localized: "activityLog.contactAutoFilled"), item.title))
        }

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
        return AddOneEntryResult(item: item, wasMerged: false)
    }

    private func refreshDigest() async {
        await NotificationScheduler.shared.scheduleDailyDigest(items: items)
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
        // elsewhere (or any other double "Mark Done") would otherwise create a second "next
        // occurrence" below for a recurring item — a duplicate bill/reminder that isn't actually
        // due yet.
        guard item.status == .active else { return }
        var completed = item
        completed.status = .completed
        await update(completed)

        guard let next = RecurrenceEngine().nextOccurrence(of: completed) else { return }
        await createRecurringOccurrence(next)
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
        for var item in newItems {
            // A JSON export carries only the attachment's metadata, never the file bytes — an
            // item imported on a different install can never actually have that file (unlike an
            // OS-level backup restore, which AttachmentStore.url(for:) already handles). Keeping
            // the reference would leave a permanently-broken row with no way to know why it never
            // loads.
            item.attachments = item.attachments.filter { AttachmentStore.shared.exists($0) }
            let persisted = PersistedItem(item: item)
            modelContext.insert(persisted)
            items.insert(item, at: 0)
            await NotificationScheduler.shared.schedule(for: item)
            let sync = CalendarSyncService.shared.sync(item: item, existingEventID: nil, existingReminderID: nil)
            persisted.calendarEventIdentifier = sync.eventIdentifier
            persisted.reminderIdentifier = sync.reminderIdentifier
        }
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
