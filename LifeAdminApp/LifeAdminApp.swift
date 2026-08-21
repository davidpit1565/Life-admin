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
        let container = try! ModelContainer(for: PersistedItem.self)
        modelContainer = container
        _store = StateObject(wrappedValue: ItemStore(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView().environmentObject(store)
        }
        .modelContainer(modelContainer)
    }
}

@MainActor
final class ItemStore: ObservableObject {
    @Published var items: [LifeAdminItem] = []
    @Published var lastAddedItemID: UUID?
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
        self.aiService = LifeAdminAIService(client: ProxyAIClient(endpoint: AppConfig.geminiProxyEndpoint))
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
            item.status = .completed
            ActivityLog.shared.record(String(format: String(localized: "activityLog.markedDoneFromNotification"), item.title))
            await update(item)
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

    func add(text: String) async {
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
            merged.updatedAt = Date()
            merged.priority = PriorityEngine().priority(for: merged)
            ActivityLog.shared.record(String(format: String(localized: "activityLog.merged"), merged.title))
            if mode == .askEveryTime { lastAddedItemID = merged.id }
            await update(merged)
            return
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
        if mode == .askEveryTime { lastAddedItemID = item.id }

        await NotificationScheduler.shared.requestAuthorizationIfNeeded()
        await NotificationScheduler.shared.schedule(for: item)

        await CalendarSyncService.shared.requestAuthorizationIfNeeded()
        let sync = CalendarSyncService.shared.sync(item: item, existingEventID: nil, existingReminderID: nil)
        persisted.calendarEventIdentifier = sync.eventIdentifier
        persisted.reminderIdentifier = sync.reminderIdentifier
        try? modelContext.save()

        await refreshDigest()
    }

    private func refreshDigest() async {
        await NotificationScheduler.shared.scheduleDailyDigest(items: items)
    }

    func update(_ item: LifeAdminItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        guard let persisted = fetchPersisted(item.id) else { return }
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

    func delete(_ item: LifeAdminItem) async {
        guard let persisted = fetchPersisted(item.id) else { return }
        var cleared = item
        cleared.dueDate = nil
        _ = CalendarSyncService.shared.sync(item: cleared, existingEventID: persisted.calendarEventIdentifier, existingReminderID: persisted.reminderIdentifier)
        await NotificationScheduler.shared.cancel(for: item.id)
        modelContext.delete(persisted)
        try? modelContext.save()
        items.removeAll { $0.id == item.id }
        await refreshDigest()
    }

    func markAddressSynced(_ itemID: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = items[index]
        if item.tags.contains(AddressChangeEngine.syncedTag) == false {
            item.tags.append(AddressChangeEngine.syncedTag)
        }
        await update(item)
    }
}
