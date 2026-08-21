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
    case added(LifeAdminItem)
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
        self.aiService = LifeAdminAIService(client: ProxyAIClient(endpoint: AppConfig.geminiProxyEndpoint), reachability: NetworkPathReachability())
        load()
        observeNotificationActions()
    }

    private func observeNotificationActions() {
        NotificationCenter.default.addObserver(forName: NotificationActionHandler.actionReceived, object: nil, queue: .main) { [weak self] note in
            guard let itemID = note.userInfo?["itemID"] as? UUID, let actionIdentifier = note.userInfo?["actionIdentifier"] as? String else { return }
            Task { [weak self] in
                await self?.handleNotificationAction(itemID: itemID, actionIdentifier: actionIdentifier)
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
            item.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: item.dueDate ?? Date())
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
    /// than one at a time the first time each feature is actually used.
    func requestAllPermissionsUpfront() async {
        await NotificationScheduler.shared.requestAuthorizationIfNeeded()
        await CalendarSyncService.shared.requestAuthorizationIfNeeded()
        await ContactsAccessService.shared.requestAuthorizationIfNeeded()
        await refreshDigest()
    }

    @discardableResult
    func add(text: String, attachments: [Attachment] = []) async -> AddOutcome {
        let mode = autonomyMode
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
        item.tags.append(contentsOf: LifeEventDetector().detectedTags(in: text))
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
            return mode == .askEveryTime ? .pendingReview(merged) : .added(merged)
        }

        // A recurring bill mentioned again months later rarely repeats the contact info the user
        // already gave once — carry it forward instead of leaving it blank again.
        if item.contact == nil, let priorMatch = items.first(where: { $0.title.caseInsensitiveCompare(item.title) == .orderedSame && $0.contact != nil }) {
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

        await refreshDigest()
        return mode == .askEveryTime ? .pendingReview(item) : .added(item)
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

        await NotificationScheduler.shared.schedule(for: item)
        await refreshDigest()
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

    /// Restoring a backup (new phone, or handing a JSON export to someone else) should be as safe
    /// to repeat as it is to run once — skip anything whose ID is already present instead of
    /// duplicating every item on a second import of the same file.
    func importItems(_ imported: [LifeAdminItem]) async {
        let existingIDs = Set(items.map(\.id))
        let newItems = imported.filter { existingIDs.contains($0.id) == false }
        guard newItems.isEmpty == false else { return }

        await NotificationScheduler.shared.requestAuthorizationIfNeeded()
        await CalendarSyncService.shared.requestAuthorizationIfNeeded()
        for var item in newItems {
            // An attachment's `localPath` points inside this specific install's sandbox
            // container — a backup restored on a new phone (or a fresh reinstall, which gets a
            // new container) can never have that file. Keeping the reference would leave a
            // permanently-broken row with no way for the user to know why it never loads.
            item.attachments = item.attachments.filter { FileManager.default.fileExists(atPath: $0.localPath) }
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
