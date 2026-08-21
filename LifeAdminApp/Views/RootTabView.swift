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

struct RootTabView: View {
    @EnvironmentObject var store: ItemStore
    @State private var adding = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("aiConsentDecision") private var aiConsentDecision = ""
    @State private var firstRunStep: FirstRunStep?

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
    }
}
struct HomeView: View {
    @EnvironmentObject var store: ItemStore
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
                Task { await store.delete(item) }
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
    }
}
struct ItemsView: View {
    @EnvironmentObject var store: ItemStore
    @State private var query = ""
    @State private var selectedCategories: Set<LifeCategory> = []
    @State private var selectedPriorities: Set<Priority> = []
    @State private var selectedStatuses: Set<ItemStatus> = []

    private var filteredItems: [LifeAdminItem] {
        var filter = SearchFilter()
        filter.query = query
        filter.categories = selectedCategories
        filter.priorities = selectedPriorities
        // Default to active-only — a completed/archived item shouldn't clutter the everyday list
        // unless the user explicitly asks to see it via the status filter.
        filter.statuses = selectedStatuses.isEmpty ? [.active] : selectedStatuses
        return SearchEngine().search(store.items, filter: filter)
    }

    private var hasActiveFilters: Bool {
        selectedCategories.isEmpty == false || selectedPriorities.isEmpty == false || selectedStatuses.isEmpty == false
    }

    var body: some View {
        NavigationStack {
            List(filteredItems) { item in
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
            .toolbar {
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

    private func toggleStatus(_ status: ItemStatus) {
        if selectedStatuses.contains(status) {
            selectedStatuses.remove(status)
        } else {
            selectedStatuses.insert(status)
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
                            ItemRowLink(item: item)
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
        store.items.filter { $0.status == .active && ($0.priority == .critical || $0.priority == .high) }.count
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
    @EnvironmentObject var store: ItemStore
    @AppStorage("language") var language = "system"
    @AppStorage("aiProcessingMode") var aiProcessingModeRaw = AIProcessingMode.allowAutomatically.rawValue
    @AppStorage("aiConsentDecision") private var aiConsentDecision = ""
    @State private var showingAIConsentReview = false
    @State private var showingDeleteAIDataConfirmation = false
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
                    // none: only .en and .he have real translations, the other 11 locale files
                    // are English-placeholder copies (lower priority, no clear audience yet) —
                    // picking "Français" and landing on English text now that switching actually
                    // works (see below) would read as broken, not just untranslated.
                    Picker(String(localized: "settings.language"), selection: $language) {
                        ForEach([SupportedLanguage.system, .en, .he], id: \.rawValue) {
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
                        showingImporter = true
                    } label: {
                        Label(String(localized: "settings.importData"), systemImage: "square.and.arrow.down")
                    }
                }
                Section(String(localized: "settings.privacy")) {
                    Button(String(localized: "settings.deleteAIData"), role: .destructive) {
                        showingDeleteAIDataConfirmation = true
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
                    }
                    if VNDocumentCameraViewController.isSupported {
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
                                                if let uiImage = UIImage(contentsOfFile: attachment.localPath) {
                                                    Image(uiImage: uiImage).resizable().scaledToFill()
                                                        .frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
                                                }
                                                Button {
                                                    AttachmentStore.shared.delete(attachment)
                                                    pendingAttachments.removeAll { $0.id == attachment.id }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
                                                }.offset(x: 6, y: -6)
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
                                case .added(let item):
                                    // Auto mode saves instantly with no review step — without a
                                    // visible "here's what we understood" moment, tapping Save
                                    // just closes the screen with no sign anything happened at
                                    // all, which reads as broken rather than automatic.
                                    withAnimation { confirmedItem = item }
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
                        AddConfirmationBanner(item: confirmedItem)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "add.confirmation.label"))
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
