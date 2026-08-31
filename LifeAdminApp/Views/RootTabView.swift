import SwiftUI
import VisionKit
import UIKit
import UniformTypeIdentifiers
import LifeAdminCore
private enum FirstRunStep: Identifiable {
    case onboarding
    case aiConsent
    var id: Self { self }
}

/// Shared geometry for the floating "+" button: its own size/position, the clearance every
/// scrollable list reserves at its bottom so the button can never sit over the last row or an
/// empty-state message, and how far above it the undo banner sits. These previously lived as
/// four separate magic numbers repeated across this file — the exact way the button once ended
/// up visually overlapping "Nothing due on this day" was one of those numbers drifting out of
/// sync with the others.
private enum FABLayout {
    static let buttonDiameter: CGFloat = 60
    static let bottomPadding: CGFloat = 58
    static let listClearance: CGFloat = 80
    static let undoBannerBottomPadding: CGFloat = 140
}

struct RootTabView: View {
    @EnvironmentObject var store: ItemStore
    @State private var adding = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("aiConsentDecision") private var aiConsentDecision = ""
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var firstRunStep: FirstRunStep?
    @State private var isLocked = false
    @Environment(\.scenePhase) private var scenePhase

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
                    .frame(width: FABLayout.buttonDiameter, height: FABLayout.buttonDiameter)
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .shadow(radius: 8)
            }
            .accessibilityLabel(String(localized: "add.anything"))
            .padding(.bottom, FABLayout.bottomPadding)
        }
        .overlay(alignment: .bottom) {
            if let pendingUndo = store.pendingUndo {
                UndoDeleteBanner(item: pendingUndo) { store.undoDelete() }
                    .padding(.bottom, FABLayout.undoBannerBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if store.calendarSyncWarningVisible {
                CalendarSyncWarningBanner()
                    .padding(.bottom, FABLayout.undoBannerBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: store.pendingUndo?.id)
        .animation(.default, value: store.calendarSyncWarningVisible)
        .sheet(isPresented: $adding) {
            AddItemView()
        }
        .task {
            if hasSeenOnboarding == false {
                firstRunStep = .onboarding
            } else if aiConsentDecision.isEmpty {
                firstRunStep = .aiConsent
            } else {
                await store.requestAllPermissionsUpfront()
            }
        }
        .fullScreenCover(item: $firstRunStep) { step in
            Group {
                switch step {
                case .onboarding:
                    OnboardingView {
                        hasSeenOnboarding = true
                        if aiConsentDecision.isEmpty {
                            firstRunStep = .aiConsent
                        } else {
                            firstRunStep = nil
                            Task { await store.requestAllPermissionsUpfront() }
                        }
                    }
                case .aiConsent:
                    AIConsentView { decision in
                        aiConsentDecision = decision
                        firstRunStep = nil
                        Task { await store.requestAllPermissionsUpfront() }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
        // A bill/insurance tracker is exactly the kind of app where "someone else picks up my
        // unlocked phone" matters, so this is opt-in in Settings — locking on by default with no
        // way to check first would be its own kind of broken. Locks going to the background (not
        // just quitting) so a quick app-switch away and back still re-prompts.
        // Only ever triggered from the one spot below (LockScreenView's own appearance) — having
        // this .task and the scenePhase handler each also fire their own authenticate() call
        // raced multiple concurrent LAContext evaluations against each other, which is exactly
        // the kind of thing that silently no-ops and leaves nothing but an inert-looking screen.
        .task {
            if appLockEnabled { isLocked = true }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard appLockEnabled, newPhase == .background else { return }
            isLocked = true
        }
        .fullScreenCover(isPresented: $isLocked) {
            LockScreenView {
                Task {
                    let authenticated = await AppLockService.shared.authenticate()
                    if authenticated == true {
                        isLocked = false
                    } else if authenticated == nil {
                        // Device can no longer verify identity at all (e.g. its passcode was
                        // removed after App Lock was turned on) — don't stand between the user
                        // and their own data with a lock that can never open again.
                        appLockEnabled = false
                        isLocked = false
                    }
                    // authenticated == false: failed or cancelled — stay locked, the button retries.
                }
            }
            .interactiveDismissDisabled()
        }
    }
}

private struct LockScreenView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "appLock.title"))
                .font(.title2.bold())
            Button(String(localized: "appLock.unlock"), action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear(perform: onRetry)
    }
}
struct HomeView: View {
    @EnvironmentObject var store: ItemStore
    @AppStorage("checklistDismissedIDs") private var dismissedIDsRaw = ""
    @State private var dismissedMovingBanner = false

    // Completed items (e.g. via "Mark Done" on a notification) stay in store.items rather than
    // being deleted, so Home must filter them out itself — otherwise a done item just sits here
    // forever, indistinguishable from an active one, and "Mark Done" accomplishes nothing visible.
    private var upcomingItems: [LifeAdminItem] {
        store.items.filter { $0.status == .active }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var hasMovingEvent: Bool {
        store.items.contains { $0.status == .active && $0.tags.contains(LifeEventDetector.movingTag) }
    }

    // No per-session dismiss for this one, unlike the moving banner below — it's meant to keep
    // being visible on Home until the user genuinely resolves it (adds the item or marks it not
    // relevant in the checklist itself), which is what "surface this again from time to time"
    // means for a screen someone actually opens often, instead of a one-off popup they close once
    // and never see again.
    private var outstandingChecklistCount: Int {
        let dismissedIDs = Set(dismissedIDsRaw.split(separator: ",").map(String.init))
        return ChecklistEngine().outstandingSuggestions(items: store.items, dismissedIDs: dismissedIDs).count
    }

    var body: some View {
        NavigationStack {
            List {
                if outstandingChecklistCount > 0 {
                    Section {
                        NavigationLink {
                            ChecklistView()
                        } label: {
                            Label(String(format: String(localized: "home.checklistTeaser"), outstandingChecklistCount), systemImage: "checklist")
                        }
                    }
                }
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
                                    // The icon itself is well under the ~44pt tap target Apple's
                                    // HIG calls for — this expands the tappable area without
                                    // changing how it looks.
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "common.dismiss"))
                        }
                    }
                }
                if upcomingItems.isEmpty {
                    ContentUnavailableView(
                        String(localized: "empty.allClear"),
                        systemImage: "checkmark.seal.fill",
                        description: Text(String(localized: "empty.noAttention"))
                    )
                } else {
                    Section(String(localized: "home.upcoming")) {
                        ForEach(upcomingItems) { item in
                            ItemRowLink(item: item)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "app.name"))
            // The floating "+" button lives in an .overlay on the shared TabView, positioned by
            // padding alone — it has no idea how tall this List's own content is, so without this
            // the last row (or, worse, empty-state text) can render right behind it. Reserving
            // real bottom space in the scroll content, rather than just visually floating the
            // button on top, is what actually guarantees no overlap on any device.
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: FABLayout.listClearance) }
        }
    }
}
/// Shared by every list that shows items (Home, Items, Calendar's day list) so swipe-to-complete
/// and swipe-to-delete — the single biggest everyday time-saver for someone managing more than a
/// couple of items — only has to be written, and gotten right, once.
private struct ItemRowLink: View {
    @EnvironmentObject var store: ItemStore
    let item: LifeAdminItem

    var body: some View {
        NavigationLink {
            ItemDetailView(item: item)
        } label: {
            ItemRow(item: item)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.scheduleDelete(item)
            } label: {
                Label(String(localized: "itemDetail.delete"), systemImage: "trash")
            }
            if item.status == .active {
                Button {
                    Task { await store.markCompleted(item) }
                } label: {
                    Label(String(localized: "itemDetail.markDone"), systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            }
        }
        // The same three actions as the swipe gesture, for anyone who didn't know to swipe (or
        // is holding the phone in a way that makes swiping awkward) — a long press is the other
        // standard iOS discovery path for row actions.
        .contextMenu {
            if item.status == .active {
                Button {
                    Task { await store.markCompleted(item) }
                } label: {
                    Label(String(localized: "itemDetail.markDone"), systemImage: "checkmark.circle.fill")
                }
            }
            Button(role: .destructive) {
                store.scheduleDelete(item)
            } label: {
                Label(String(localized: "itemDetail.delete"), systemImage: "trash")
            }
        }
    }
}
private enum DateRangeFilter: String, CaseIterable {
    case overdue, thisWeek, thisMonth

    var localizedLabel: String {
        switch self {
        case .overdue: return String(localized: "items.filterByDate.overdue")
        case .thisWeek: return String(localized: "items.filterByDate.thisWeek")
        case .thisMonth: return String(localized: "items.filterByDate.thisMonth")
        }
    }

    /// `nil` bounds are deliberately open-ended: "overdue" has no lower bound (anything, no
    /// matter how old), and none of these need an upper bound below distantFuture.
    func bounds(now: Date, calendar: Calendar) -> (from: Date?, to: Date?) {
        switch self {
        case .overdue: return (nil, calendar.startOfDay(for: now))
        case .thisWeek: return (now, calendar.date(byAdding: .day, value: 7, to: now))
        case .thisMonth: return (now, calendar.date(byAdding: .month, value: 1, to: now))
        }
    }
}

private enum ItemSortOrder: String, CaseIterable {
    case dueDate, alphabetical, amount

    var localizedLabel: String {
        switch self {
        case .dueDate: return String(localized: "items.sort.dueDate")
        case .alphabetical: return String(localized: "items.sort.alphabetical")
        case .amount: return String(localized: "items.sort.amount")
        }
    }

    /// Items with no due date/amount sort last rather than first — they're not "most urgent",
    /// they're simply unset, and burying real deadlines under unset ones would defeat the sort.
    func sorted(_ items: [LifeAdminItem]) -> [LifeAdminItem] {
        switch self {
        case .dueDate: return items.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case .alphabetical: return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .amount: return items.sorted { ($0.amount ?? -1) > ($1.amount ?? -1) }
        }
    }
}

struct ItemsView: View {
    @EnvironmentObject var store: ItemStore
    @State private var query = ""
    @State private var selectedCategories: Set<LifeCategory> = []
    @State private var selectedPriorities: Set<Priority> = []
    @State private var selectedStatuses: Set<ItemStatus> = []
    @State private var dateRangeFilter: DateRangeFilter?
    @State private var sortOrder: ItemSortOrder = .dueDate
    @State private var selection = Set<UUID>()
    @State private var showingBulkDeleteConfirmation = false

    private var filteredItems: [LifeAdminItem] {
        var filter = SearchFilter()
        filter.query = query
        filter.categories = selectedCategories
        filter.priorities = selectedPriorities
        // Default to active-only — a completed/archived item shouldn't clutter the everyday list
        // unless the user explicitly asks to see it via the status filter.
        filter.statuses = selectedStatuses.isEmpty ? [.active] : selectedStatuses
        if let dateRangeFilter {
            let bounds = dateRangeFilter.bounds(now: Date(), calendar: .current)
            filter.dueFrom = bounds.from
            filter.dueTo = bounds.to
        }
        // SearchEngine only filters — without sorting here too, this list showed items in
        // whatever order they were created, not by what's actually coming up next, unlike Home's
        // own "upcoming" list right next to it.
        return sortOrder.sorted(SearchEngine().search(store.items, filter: filter))
    }

    private var hasActiveFilters: Bool {
        selectedCategories.isEmpty == false || selectedPriorities.isEmpty == false || selectedStatuses.isEmpty == false || dateRangeFilter != nil
    }

    var body: some View {
        NavigationStack {
            List(filteredItems, selection: $selection) { item in
                ItemRowLink(item: item)
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
            // See HomeView's identical modifier — reserves real space so the floating "+" button
            // (positioned by an .overlay on the shared TabView) can't render on top of this list's
            // own last row or empty-state text.
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: FABLayout.listClearance) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                if selection.isEmpty == false {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            Task { await completeSelected() }
                        } label: {
                            Label(String(localized: "itemDetail.markDone"), systemImage: "checkmark.circle")
                        }
                        Spacer()
                        Button(role: .destructive) {
                            showingBulkDeleteConfirmation = true
                        } label: {
                            Label(String(localized: "itemDetail.delete"), systemImage: "trash")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(ItemSortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                if sortOrder == order {
                                    Label(order.localizedLabel, systemImage: "checkmark")
                                } else {
                                    Text(order.localizedLabel)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(String(localized: "items.sort"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Menu(String(localized: "items.filterByCategory")) {
                            ForEach(LifeCategory.allCases, id: \.self) { category in
                                Button {
                                    toggleCategory(category)
                                } label: {
                                    if selectedCategories.contains(category) {
                                        Label(category.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(category.displayName)
                                    }
                                }
                            }
                        }
                        Menu(String(localized: "items.filterByDate")) {
                            ForEach(DateRangeFilter.allCases, id: \.self) { range in
                                Button {
                                    dateRangeFilter = dateRangeFilter == range ? nil : range
                                } label: {
                                    if dateRangeFilter == range {
                                        Label(range.localizedLabel, systemImage: "checkmark")
                                    } else {
                                        Text(range.localizedLabel)
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
                                        Label(priority.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(priority.displayName)
                                    }
                                }
                            }
                        }
                        Menu(String(localized: "items.filterByStatus")) {
                            // .snoozed and .archived are part of the data model but nothing in the
                            // app ever sets an item to either — offering them here would let
                            // someone filter for "Snoozed" and get zero results forever, with no
                            // way to tell that from "nothing happens to be snoozed right now".
                            ForEach([ItemStatus.active, .completed], id: \.self) { status in
                                Button {
                                    toggleStatus(status)
                                } label: {
                                    if selectedStatuses.contains(status) {
                                        Label(status.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(status.displayName)
                                    }
                                }
                            }
                        }
                        if hasActiveFilters {
                            Button(String(localized: "items.clearFilters"), role: .destructive) {
                                selectedCategories = []
                                selectedPriorities = []
                                selectedStatuses = []
                                dateRangeFilter = nil
                            }
                        }
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(String(localized: "items.filter"))
                }
            }
            .confirmationDialog(
                String(format: String(localized: "items.deleteSelectedConfirm"), selection.count),
                isPresented: $showingBulkDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "itemDetail.delete"), role: .destructive) {
                    deleteSelected()
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

    private func toggleStatus(_ status: ItemStatus) {
        if selectedStatuses.contains(status) {
            selectedStatuses.remove(status)
        } else {
            selectedStatuses.insert(status)
        }
    }

    private func completeSelected() async {
        for item in store.items where selection.contains(item.id) {
            await store.markCompleted(item)
        }
        selection = []
    }

    private func deleteSelected() {
        // A bulk delete confirms up front instead of offering Undo per item — with several
        // items at once, store.scheduleDelete's single-item Undo banner would only ever be able
        // to restore the last one, silently leaving the rest gone.
        let toDelete = store.items.filter { selection.contains($0.id) }
        selection = []
        Task {
            for item in toDelete {
                await store.delete(item)
            }
        }
    }
}
struct CalendarView: View {
    @EnvironmentObject var store: ItemStore
    @State private var selectedDate = Date()

    private var itemsByDay: [DateComponents: [LifeAdminItem]] {
        Dictionary(grouping: store.items.filter { $0.status == .active && $0.dueDate != nil }) { item in
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
                // A hardcoded height clipped whichever week row didn't fit — reported directly by
                // a user whose July had its last row (27-31) cut off entirely, with no way to
                // even scroll to it. UICalendarView already reports its own correct intrinsic
                // height for however many rows the visible month actually needs (4, 5, or 6);
                // fixedSize lets that size through instead of forcing a fixed number.
                CalendarGridView(selectedDate: $selectedDate, markedDays: Set(itemsByDay.keys))
                    .fixedSize(horizontal: false, vertical: true)
                List {
                    if selectedDayItems.isEmpty {
                        ContentUnavailableView(
                            String(localized: "calendar.noItemsThisDay"),
                            systemImage: "calendar"
                        )
                    } else {
                        ForEach(selectedDayItems) { item in
                            ItemRowLink(item: item)
                        }
                    }
                }
                // See HomeView's identical modifier — without it, the floating "+" button (an
                // .overlay on the shared TabView, unaware of this List's own content) rendered
                // directly on top of "Nothing due on this day", confirmed on-device.
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: FABLayout.listClearance) }
            }
            .navigationTitle(String(localized: "tab.calendar"))
        }
    }
}
struct InsightsView: View {
    @EnvironmentObject var store: ItemStore

    private var urgentCount: Int {
        store.items.filter { $0.status == .active && ($0.priority == .critical || $0.priority == .high) }.count
    }

    // Reuses DigestEngine instead of re-deriving this — the hand-rolled version here compared
    // dueDate against only the upper bound of the week, so an item overdue by months satisfied
    // "<= horizon" too and never stopped counting as "due this week".
    private var upcomingWeekCount: Int {
        DigestEngine().summary(for: store.items).dueThisWeekCount
    }

    /// Grouped by currency, not summed together — adding a USD amount to an ILS amount would
    /// just be a wrong number dressed up as a real one. Sorted so the display order is stable
    /// across re-renders instead of following Dictionary's undefined iteration order.
    private var monthlyTotals: [(currency: String, amount: Decimal)] {
        let now = Date()
        let monthEnd = Calendar.current.date(byAdding: .month, value: 1, to: now) ?? now
        let totals = SpendEngine().totalsByCurrency(for: store.items, from: now, to: monthEnd)
        return totals.sorted { $0.key < $1.key }.map { (currency: $0.key, amount: $0.value) }
    }

    private func formatted(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        if currency.isEmpty == false { formatter.currencyCode = currency }
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
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
                // Hiding this section entirely whenever nothing has both an amount and a due
                // date this month looked exactly like the feature didn't exist at all, rather
                // than like it correctly found nothing to total — showing it with an explicit
                // zero removes that ambiguity.
                Section(String(localized: "insights.dueThisMonth")) {
                    if monthlyTotals.isEmpty {
                        Text(String(localized: "insights.dueThisMonth.none"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monthlyTotals, id: \.currency) { entry in
                            LabeledContent(entry.currency.isEmpty ? String(localized: "itemDetail.currency.none") : entry.currency) {
                                Text(formatted(entry.amount, currency: entry.currency))
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "tab.insights"))
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: FABLayout.listClearance) }
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: ItemStore
    @AppStorage("language") var language = "system"
    @AppStorage("aiProcessingMode") var aiProcessingModeRaw = AIProcessingMode.allowAutomatically.rawValue
    @AppStorage("aiConsentDecision") private var aiConsentDecision = ""
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var showingAIConsentReview = false
    @State private var showingDeleteAIDataConfirmation = false
    @State private var showingDeleteAllDataConfirmation = false
    @State private var exportFileURL: URL?
    @State private var showingShareSheet = false
    @State private var showingImporter = false
    @State private var importAlertMessage: String?
    @State private var showingRestartNotice = false

    private var aiProcessingMode: AIProcessingMode {
        AIProcessingMode(rawValue: aiProcessingModeRaw) ?? .allowAutomatically
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "settings.general")) {
                    // Offering all 14 SupportedLanguage cases here would be worse than offering
                    // none: only .en, .he, .es, and .fr have real translations, the other 9
                    // locale files are English-placeholder copies (lower priority, no clear
                    // audience yet) — picking a language that lands on English text now that
                    // switching actually works (see below) would read as broken, not untranslated.
                    Picker(String(localized: "settings.language"), selection: $language) {
                        ForEach([SupportedLanguage.system, .en, .he, .es, .fr], id: \.rawValue) {
                            Text(displayName(for: $0)).tag($0.rawValue)
                        }
                    }
                    // The picker previously changed nothing: iOS decides which .lproj to load
                    // from the system language, and nothing here ever overrode that — picking
                    // "Hebrew" while the phone itself is in English silently did nothing at all.
                    .onChange(of: language) { _, newValue in
                        applyLanguageOverride(newValue)
                        showingRestartNotice = true
                    }
                    NavigationLink(String(localized: "settings.addressChange")) {
                        AddressChangeView()
                    }
                    NavigationLink(String(localized: "checklist.title")) {
                        ChecklistView()
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
                Section(String(localized: "settings.data")) {
                    Button {
                        if let url = Self.writeExportFile(items: store.items) {
                            exportFileURL = url
                            showingShareSheet = true
                        }
                    } label: {
                        Label(String(localized: "settings.exportData"), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        if let url = Self.writeCSVExportFile(items: store.items) {
                            exportFileURL = url
                            showingShareSheet = true
                        }
                    } label: {
                        Label(String(localized: "settings.exportCSV"), systemImage: "tablecells")
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label(String(localized: "settings.importData"), systemImage: "square.and.arrow.down")
                    }
                }
                Section(String(localized: "settings.privacy")) {
                    // Only offered when the device can actually back it up (Face ID, Touch ID,
                    // or at least a passcode) — a toggle that turns on and then never actually
                    // locks anything would be worse than not offering it at all.
                    if AppLockService.shared.canUseBiometrics() {
                        Toggle(String(localized: "appLock.toggle"), isOn: $appLockEnabled)
                    }
                    Button(String(localized: "settings.deleteAIData"), role: .destructive) {
                        showingDeleteAIDataConfirmation = true
                    }
                    Button(String(localized: "settings.deleteAllData"), role: .destructive) {
                        showingDeleteAllDataConfirmation = true
                    }
                }
            }.navigationTitle(String(localized: "tab.settings"))
            .sheet(isPresented: $showingAIConsentReview) {
                AIConsentView { decision in
                    aiConsentDecision = decision
                    showingAIConsentReview = false
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    Task { await importFile(at: url) }
                case .failure:
                    importAlertMessage = String(localized: "settings.importFailed")
                }
            }
            .alert(String(localized: "settings.importResult"), isPresented: Binding(
                get: { importAlertMessage != nil },
                set: { if $0 == false { importAlertMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(importAlertMessage ?? "")
            }
            .confirmationDialog(
                String(localized: "settings.deleteAIData.confirm"),
                isPresented: $showingDeleteAIDataConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "settings.deleteAIData"), role: .destructive) {
                    ActivityLog.shared.clear()
                }
            }
            .confirmationDialog(
                String(localized: "settings.deleteAllData.confirmTitle"),
                isPresented: $showingDeleteAllDataConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "settings.deleteAllData"), role: .destructive) {
                    Task { await store.deleteAllData() }
                }
            } message: {
                Text(String(localized: "settings.deleteAllData.confirmMessage"))
            }
            .alert(String(localized: "settings.language.restartTitle"), isPresented: $showingRestartNotice) {
                Button(String(localized: "settings.language.restartNow"), role: .destructive) {
                    exit(0)
                }
                Button(String(localized: "settings.language.later"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.language.restartMessage"))
            }
        }
    }

    /// iOS decides which .lproj to load from `AppleLanguages` in UserDefaults, which normally
    /// just mirrors the system language — overriding that key here is the standard (if slightly
    /// low-level) way to let a single app show a different language than the rest of the phone.
    /// Only takes effect on the next launch, hence the restart prompt.
    private func applyLanguageOverride(_ rawValue: String) {
        if rawValue == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else if let language = SupportedLanguage(rawValue: rawValue) {
            UserDefaults.standard.set([language.localeIdentifier], forKey: "AppleLanguages")
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

    /// A backup someone can hand to family, keep for themselves, or restore from on a new phone —
    /// without this, deleting the app (or losing the device) meant losing every item for good.
    private static func writeExportFile(items: [LifeAdminItem]) -> URL? {
        guard let data = try? ImportExportEngine().exportJSON(items) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "LifeAdmin-Backup-\(Date().ISO8601Format()).json")
        guard (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    /// A spreadsheet a user can actually open and sum in Numbers/Excel/Sheets — the JSON export
    /// above is a backup format meant for re-import, not for glancing at what you're spending.
    /// ImportExportEngine.exportCSV already existed but nothing in the app ever called it.
    private static func writeCSVExportFile(items: [LifeAdminItem]) -> URL? {
        let csv = ImportExportEngine().exportCSV(items)
        guard let data = csv.data(using: .utf8) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "LifeAdmin-Export-\(Date().ISO8601Format()).csv")
        guard (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    private func importFile(at url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let imported = try? ImportExportEngine().importJSON(data) else {
            importAlertMessage = String(localized: "settings.importFailed")
            return
        }
        let beforeCount = store.items.count
        await store.importItems(imported)
        let addedCount = store.items.count - beforeCount
        importAlertMessage = addedCount > 0
            ? String(format: String(localized: "settings.importSucceeded"), addedCount)
            : String(localized: "settings.importNothingNew")
    }
}
struct AddItemView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: ItemStore
    @State var text = ""
    @State private var isSaving = false
    @State private var itemPendingReview: LifeAdminItem?
    @State private var showingScanner = false
    @State private var pendingAttachments: [Attachment] = []
    @State private var confirmedItem: LifeAdminItem?
    @State private var confirmedItemWasMerged = false
    @State private var confirmedCount: Int?

    /// A handful of ready-made examples spanning different categories — tapping one fills the
    /// text box with exactly what to type, so a first-time (or simply overwhelmed) user can see
    /// the whole point of this screen without having to invent an example themselves.
    private static let quickExamples = [
        "add.example.insurance",
        "add.example.subscription",
        "add.example.appointment",
    ]

    var body: some View {
        NavigationStack {
            if let item = itemPendingReview {
                ItemDetailView(item: item)
            } else {
                Form {
                    Section(String(localized: "add.justTellMe")) {
                        TextEditor(text: $text)
                            .frame(minHeight: 140)
                            .accessibilityLabel(String(localized: "add.prompt"))
                            .overlay(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text(String(localized: "add.placeholderExample"))
                                        .foregroundStyle(Color(uiColor: .placeholderText))
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Self.quickExamples, id: \.self) { key in
                                    let example = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
                                    Button(example) {
                                        text = example
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        Text(String(localized: "add.multiLineHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if FeatureFlags.documentScanningEnabled && VNDocumentCameraViewController.isSupported {
                        Section {
                            Button {
                                showingScanner = true
                            } label: {
                                Label(String(localized: "add.scanDocument"), systemImage: "doc.viewfinder")
                            }
                            if pendingAttachments.isEmpty == false {
                                ScrollView(.horizontal) {
                                    HStack {
                                        ForEach(pendingAttachments) { attachment in
                                            ZStack(alignment: .topTrailing) {
                                                if let uiImage = UIImage(contentsOfFile: AttachmentStore.shared.url(for: attachment).path) {
                                                    Image(uiImage: uiImage).resizable().scaledToFill()
                                                        .frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
                                                }
                                                Button {
                                                    AttachmentStore.shared.delete(attachment)
                                                    pendingAttachments.removeAll { $0.id == attachment.id }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
                                                        // Full 44pt HIG sizing here would start
                                                        // overlapping the next thumbnail in this
                                                        // tightly packed row — 32pt meaningfully
                                                        // grows the glyph's own tiny hit area
                                                        // without that collision risk.
                                                        .frame(width: 32, height: 32)
                                                        .contentShape(Rectangle())
                                                }
                                                .accessibilityLabel(String(format: String(localized: "add.removeAttachment"), attachment.filename))
                                                .offset(x: 6, y: -6)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        Button {
                            isSaving = true
                            Task {
                                let outcome = await store.add(text: text, attachments: pendingAttachments)
                                isSaving = false
                                switch outcome {
                                case .pendingReview(let item):
                                    // "Ask every time" mode leaves the new item in place but
                                    // pending review — swap this same sheet over to editing it
                                    // instead of dismissing, rather than silently trusting the
                                    // AI's guess.
                                    itemPendingReview = item
                                case .added(let item, let merged):
                                    // Auto mode saves instantly with no review step — without a
                                    // visible "here's what we understood" moment, tapping Save
                                    // just closes the screen with no sign anything happened at
                                    // all, which reads as broken rather than automatic.
                                    withAnimation {
                                        confirmedItem = item
                                        confirmedItemWasMerged = merged
                                    }
                                    try? await Task.sleep(for: .seconds(1.2))
                                    dismiss()
                                case .addedMultiple(let addedItems):
                                    withAnimation { confirmedCount = addedItems.count }
                                    try? await Task.sleep(for: .seconds(1.2))
                                    dismiss()
                                }
                            }
                        } label: {
                            // The AI call behind this can take a few seconds — a button that just
                            // sits there disabled with no other feedback reads as frozen/broken,
                            // not "working on it".
                            if isSaving {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text(String(localized: "common.save"))
                                }
                            } else {
                                Text(String(localized: "common.save"))
                            }
                        }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    }
                }.navigationTitle(String(localized: "add.anything"))
                .overlay(alignment: .bottom) {
                    if let confirmedItem {
                        AddConfirmationBanner(item: confirmedItem, wasMerged: confirmedItemWasMerged)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let confirmedCount {
                        MultiAddConfirmationBanner(count: confirmedCount)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .fullScreenCover(isPresented: $showingScanner) {
                    DocumentScannerView(
                        onScanned: { recognized, pageImages in
                            showingScanner = false
                            if recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                                text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? recognized : text + "\n" + recognized
                            }
                            for (index, image) in pageImages.enumerated() {
                                let filename = String(format: String(localized: "add.scannedPageFilename"), pendingAttachments.count + index + 1)
                                if let attachment = AttachmentStore.shared.saveJPEG(image, filename: filename) {
                                    pendingAttachments.append(attachment)
                                }
                            }
                        },
                        onCancel: { showingScanner = false }
                    )
                    .ignoresSafeArea()
                }
            }
        }
    }
}

private struct AddConfirmationBanner: View {
    let item: LifeAdminItem
    var wasMerged: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                // Purely decorative next to text that already says the same thing — without
                // this, VoiceOver announces "Checkmark, circle, fill, image" before ever getting
                // to the actual confirmation message.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // A merge silently updating an existing item read exactly like a brand new one —
                // saying so here is the only place that distinction was ever visible outside the
                // Activity Log.
                Text(String(localized: wasMerged ? "add.confirmation.merged" : "add.confirmation.label"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.title)
                    .font(.headline)
                if let due = item.dueDate {
                    Text(due, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .shadow(radius: 4)
    }
}

private struct MultiAddConfirmationBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(String(format: String(localized: "add.confirmation.multiple"), count))
                .font(.headline)
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .shadow(radius: 4)
    }
}

private struct CalendarSyncWarningBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(String(localized: "calendarSync.warning"))
                .font(.subheadline)
                .lineLimit(2)
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .shadow(radius: 4)
    }
}

private struct UndoDeleteBanner: View {
    let item: LifeAdminItem
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: String(localized: "items.deletedToast"), item.title))
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Button(String(localized: "common.undo"), action: onUndo)
                .font(.subheadline.bold())
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .shadow(radius: 4)
    }
}
