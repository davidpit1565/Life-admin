import SwiftUI
import LifeAdminCore
struct RootTabView: View {
    @EnvironmentObject var store: ItemStore
    @State private var adding = false

    var body: some View {
        TabView {
            HomeView().tabItem { Label(String(localized: "tab.home"), systemImage: "house") }
            ItemsView().tabItem { Label(String(localized: "tab.items"), systemImage: "folder") }
            CalendarView().tabItem { Label(String(localized: "tab.calendar"), systemImage: "calendar") }
            InsightsView().tabItem { Label(String(localized: "tab.insights"), systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView().tabItem { Label(String(localized: "tab.settings"), systemImage: "gear") }
        }
        .overlay(alignment: .bottom) {
            Button {
                adding = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .frame(width: 60, height: 60)
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .shadow(radius: 8)
            }
            .accessibilityLabel(String(localized: "add.anything"))
            .padding(.bottom, 58)
        }
        .sheet(isPresented: $adding) {
            AddItemView()
        }
        .task {
            await store.requestAllPermissionsUpfront()
        }
    }
}
struct HomeView: View {
    @EnvironmentObject var store: ItemStore
    @State private var dismissedMovingBanner = false

    private var upcomingItems: [LifeAdminItem] {
        store.items.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var hasMovingEvent: Bool {
        store.items.contains { $0.status == .active && $0.tags.contains(LifeEventDetector.movingTag) }
    }

    var body: some View {
        NavigationStack {
            List {
                if hasMovingEvent && dismissedMovingBanner == false {
                    Section {
                        HStack {
                            NavigationLink {
                                AddressChangeView()
                            } label: {
                                Label(String(localized: "home.movingDetected"), systemImage: "shippingbox.fill")
                            }
                            Spacer()
                            Button {
                                dismissedMovingBanner = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if store.items.isEmpty {
                    ContentUnavailableView(
                        String(localized: "empty.allClear"),
                        systemImage: "checkmark.seal.fill",
                        description: Text(String(localized: "empty.noAttention"))
                    )
                } else {
                    Section(String(localized: "home.upcoming")) {
                        ForEach(upcomingItems) { item in
                            NavigationLink {
                                ItemDetailView(item: item)
                            } label: {
                                ItemRow(item: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "app.name"))
        }
    }
}
struct ItemsView: View {
    @EnvironmentObject var store: ItemStore
    @State private var query = ""

    private var filteredItems: [LifeAdminItem] {
        var filter = SearchFilter()
        filter.query = query
        return SearchEngine().search(store.items, filter: filter)
    }

    var body: some View {
        NavigationStack {
            List(filteredItems) { item in
                NavigationLink {
                    ItemDetailView(item: item)
                } label: {
                    ItemRow(item: item)
                }
            }
            .overlay {
                if filteredItems.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView(
                            String(localized: "empty.allClear"),
                            systemImage: "folder",
                            description: Text(String(localized: "empty.noAttention"))
                        )
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle(String(localized: "tab.items"))
        }
    }
}
struct CalendarView: View {
    @EnvironmentObject var store: ItemStore
    @State private var selectedDate = Date()

    private var itemsByDay: [DateComponents: [LifeAdminItem]] {
        Dictionary(grouping: store.items.filter { $0.dueDate != nil }) { item in
            Calendar.current.dateComponents([.year, .month, .day], from: item.dueDate!)
        }
    }

    private var selectedDayItems: [LifeAdminItem] {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        return itemsByDay[components] ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CalendarGridView(selectedDate: $selectedDate, markedDays: Set(itemsByDay.keys))
                    .frame(height: 360)
                List {
                    if selectedDayItems.isEmpty {
                        ContentUnavailableView(
                            String(localized: "calendar.noItemsThisDay"),
                            systemImage: "calendar"
                        )
                    } else {
                        ForEach(selectedDayItems) { item in
                            NavigationLink {
                                ItemDetailView(item: item)
                            } label: {
                                ItemRow(item: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "tab.calendar"))
        }
    }
}
struct InsightsView: View {
    @EnvironmentObject var store: ItemStore

    private var urgentCount: Int {
        store.items.filter { $0.priority == .critical || $0.priority == .high }.count
    }

    private var upcomingWeekCount: Int {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return store.items.filter { ($0.dueDate ?? .distantFuture) <= horizon }.count
    }

    var body: some View {
        NavigationStack {
            List {
                LabeledContent {
                    Text(store.items.count.formatted())
                } label: {
                    Label(String(localized: "insights.total"), systemImage: "tray.full.fill")
                }
                LabeledContent {
                    Text(urgentCount.formatted())
                        .foregroundStyle(urgentCount > 0 ? .red : .secondary)
                } label: {
                    Label(String(localized: "insights.urgent"), systemImage: "exclamationmark.triangle.fill")
                }
                LabeledContent {
                    Text(upcomingWeekCount.formatted())
                } label: {
                    Label(String(localized: "insights.dueThisWeek"), systemImage: "calendar.badge.clock")
                }
            }
            .navigationTitle(String(localized: "tab.insights"))
        }
    }
}
struct SettingsView: View {
    @AppStorage("language") var language = "system"
    @AppStorage("aiProcessingMode") var aiProcessingModeRaw = AIProcessingMode.allowAutomatically.rawValue

    private var aiProcessingMode: AIProcessingMode {
        AIProcessingMode(rawValue: aiProcessingModeRaw) ?? .allowAutomatically
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "settings.general")) {
                    Picker(String(localized: "settings.language"), selection: $language) {
                        ForEach(SupportedLanguage.allCases, id: \.rawValue) {
                            Text($0.rawValue).tag($0.rawValue)
                        }
                    }
                    NavigationLink(String(localized: "settings.addressChange")) {
                        AddressChangeView()
                    }
                }
                Section(String(localized: "settings.ai")) {
                    Picker(String(localized: "settings.aiAutonomy"), selection: $aiProcessingModeRaw) {
                        Text(String(localized: "settings.aiAutonomy.auto")).tag(AIProcessingMode.allowAutomatically.rawValue)
                        Text(String(localized: "settings.aiAutonomy.askFirst")).tag(AIProcessingMode.askEveryTime.rawValue)
                        Text(String(localized: "settings.aiAutonomy.off")).tag(AIProcessingMode.disabled.rawValue)
                    }
                    Text(aiProcessingModeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NavigationLink(String(localized: "activityLog.title")) {
                        ActivityLogView()
                    }
                }
                Section(String(localized: "settings.privacy")) {
                    Button(String(localized: "settings.deleteAIData"), role: .destructive) {}
                }
            }.navigationTitle(String(localized: "tab.settings"))
        }
    }

    private var aiProcessingModeDescription: String {
        switch aiProcessingMode {
        case .allowAutomatically: return String(localized: "settings.aiAutonomy.auto.description")
        case .askEveryTime: return String(localized: "settings.aiAutonomy.askFirst.description")
        case .disabled: return String(localized: "settings.aiAutonomy.off.description")
        }
    }
}
struct AddItemView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: ItemStore
    @State var text = ""
    @State private var isSaving = false
    @State private var itemPendingReview: LifeAdminItem?

    var body: some View {
        NavigationStack {
            if let item = itemPendingReview {
                ItemDetailView(item: item)
            } else {
                Form {
                    Section(String(localized: "add.justTellMe")) {
                        TextEditor(text: $text).frame(minHeight: 140).accessibilityLabel(String(localized: "add.prompt"))
                    }
                    Section {
                        Button(String(localized: "common.save")) {
                            isSaving = true
                            Task {
                                await store.add(text: text)
                                isSaving = false
                                // "Ask every time" mode leaves the new item in place but pending
                                // review — swap this same sheet over to editing it instead of
                                // dismissing, rather than silently trusting the AI's guess.
                                if let pendingID = store.lastAddedItemID, let added = store.items.first(where: { $0.id == pendingID }) {
                                    store.lastAddedItemID = nil
                                    itemPendingReview = added
                                } else {
                                    dismiss()
                                }
                            }
                        }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    }
                }.navigationTitle(String(localized: "add.anything"))
            }
        }
    }
}
