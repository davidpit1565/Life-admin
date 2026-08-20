import SwiftUI
import SwiftData
import LifeAdminCore

@main
struct LifeAdminApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var store: ItemStore

    init() {
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
    private let modelContext: ModelContext
    private let aiService: LifeAdminAIService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.aiService = LifeAdminAIService(client: ProxyAIClient(endpoint: AppConfig.geminiProxyEndpoint))
        load()
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
    }

    func add(text: String) async {
        let decision = await aiService.extract(text)
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
