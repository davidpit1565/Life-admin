import SwiftUI
import VisionKit
import LifeAdminCore
struct RootTabView: View {
    @EnvironmentObject var store: ItemStore
    @State private var adding = false
    @AppStorage("aiConsentDecision") private var aiConsentDecision = ""
    @State private var showingAIConsent = false

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
            if aiConsentDecision.isEmpty {
                showingAIConsent = true
            }
            await store.requestAllPermissionsUpfront()
        }
        .fullScreenCover(isPresented: $showingAIConsent) {
            AIConsentView { decision in
                aiConsentDecision = decision
                showingAIConsent = false
            }
            .interactiveDismissDisabled()
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
    @State private var selectedCategories: Set<LifeCategory> = []
    @State private var selectedPriorities: Set<Priority> = []

    private var filteredItems: [LifeAdminItem] {
        var filter = SearchFilter()
        filter.query = query
        filter.categories = selectedCategories
        filter.priorities = selectedPriorities
        return SearchEngine().search(store.items, filter: filter)
    }

    private var hasActiveFilters: Bool {
        selectedCategories.isEmpty == false || selectedPriorities.isEmpty == false
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
                    if query.isEmpty && hasActiveFilters == false {
                        ContentUnavailableView(
                            String(localized: "empty.allClear"),
                            systemImage: "folder",
                            description: Text(String(localized: "empty.noAttention"))
                        )
                    } else if query.isEmpty {
                        ContentUnavailableView(
                            String(localized: "items.noFilterMatches"),
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle(String(localized: "tab.items"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Menu(String(localized: "items.filterByCategory")) {
                            ForEach(LifeCategory.allCases, id: \.self) { category in
                                Button {
                                    toggleCategory(category)
                                } label: {
                                    if selectedCategories.contains(category) {
                                        Label(category.rawValue.capitalized, systemImage: "checkmark")
                                    } else {
                                        Text(category.rawValue.capitalized)
                                    }
                                }
                            }
                        }
                        Menu(String(localized: "items.filterByPriority")) {
                            ForEach(Priority.allCases, id: \.self) { priority in
                                Button {
                                    togglePriority(priority)
                                } label: {
                                    if selectedPriorities.contains(priority) {
                                        Label(priority.rawValue.capitalized, systemImage: "checkmark")
                                    } else {
                                        Text(priority.rawValue.capitalized)
                                    }
                                }
                            }
                        }
                        if hasActiveFilters {
                            Button(String(localized: "items.clearFilters"), role: .destructive) {
                                selectedCategories = []
                                selectedPriorities = []
                            }
                        }
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(String(localized: "items.filter"))
                }
            }
        }
    }

    private func toggleCategory(_ category: LifeCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    private func togglePriority(_ priority: Priority) {
        if selectedPriorities.contains(priority) {
            selectedPriorities.remove(priority)
        } else {
            selectedPriorities.insert(priority)
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

    // Reuses DigestEngine instead of re-deriving this — the hand-rolled version here compared
    // dueDate against only the upper bound of the week, so an item overdue by months satisfied
    // "<= horizon" too and never stopped counting as "due this week".
    private var upcomingWeekCount: Int {
        DigestEngine().summary(for: store.items).dueThisWeekCount
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
    @AppStorage("aiConsentDecision") private var aiConsentDecision = ""
    @State private var showingAIConsentReview = false

    private var aiProcessingMode: AIProcessingMode {
        AIProcessingMode(rawValue: aiProcessingModeRaw) ?? .allowAutomatically
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "settings.general")) {
                    Picker(String(localized: "settings.language"), selection: $language) {
                        ForEach(SupportedLanguage.allCases, id: \.rawValue) {
                            Text(displayName(for: $0)).tag($0.rawValue)
                        }
                    }
                    NavigationLink(String(localized: "settings.addressChange")) {
                        AddressChangeView()
                    }
                }
                Section(String(localized: "settings.ai")) {
                    if aiConsentDecision == "granted" {
                        Picker(String(localized: "settings.aiAutonomy"), selection: $aiProcessingModeRaw) {
                            Text(String(localized: "settings.aiAutonomy.auto")).tag(AIProcessingMode.allowAutomatically.rawValue)
                            Text(String(localized: "settings.aiAutonomy.askFirst")).tag(AIProcessingMode.askEveryTime.rawValue)
                            Text(String(localized: "settings.aiAutonomy.off")).tag(AIProcessingMode.disabled.rawValue)
                        }
                        Text(aiProcessingModeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(String(localized: "settings.aiConsent.revoke"), role: .destructive) {
                            aiConsentDecision = "declined"
                        }
                    } else {
                        Text(String(localized: "settings.aiConsent.declinedNotice"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(String(localized: "settings.aiConsent.review")) {
                            showingAIConsentReview = true
                        }
                    }
                    NavigationLink(String(localized: "activityLog.title")) {
                        ActivityLogView()
                    }
                }
                Section(String(localized: "settings.privacy")) {
                    Button(String(localized: "settings.deleteAIData"), role: .destructive) {}
                }
            }.navigationTitle(String(localized: "tab.settings"))
            .sheet(isPresented: $showingAIConsentReview) {
                AIConsentView { decision in
                    aiConsentDecision = decision
                    showingAIConsentReview = false
                }
            }
        }
    }

    private func displayName(for language: SupportedLanguage) -> String {
        guard language != .system else { return String(localized: "settings.language.system") }
        let identifier = language.localeIdentifier
        return Locale(identifier: identifier).localizedString(forIdentifier: identifier)?.localizedCapitalized ?? language.rawValue
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
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            if let item = itemPendingReview {
                ItemDetailView(item: item)
            } else {
                Form {
                    Section(String(localized: "add.justTellMe")) {
                        TextEditor(text: $text).frame(minHeight: 140).accessibilityLabel(String(localized: "add.prompt"))
                    }
                    if VNDocumentCameraViewController.isSupported {
                        Section {
                            Button {
                                showingScanner = true
                            } label: {
                                Label(String(localized: "add.scanDocument"), systemImage: "doc.viewfinder")
                            }
                        }
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
                .fullScreenCover(isPresented: $showingScanner) {
                    DocumentScannerView(
                        onRecognizedText: { recognized in
                            showingScanner = false
                            guard recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
                            text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? recognized : text + "\n" + recognized
                        },
                        onCancel: { showingScanner = false }
                    )
                    .ignoresSafeArea()
                }
            }
        }
    }
}
