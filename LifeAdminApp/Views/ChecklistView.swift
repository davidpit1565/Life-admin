import SwiftUI
import LifeAdminCore

/// The starter checklist of commonly-forgotten reminders (passport, car insurance, ...), shown
/// from Settings and teased on Home whenever something is still outstanding. Dismissing a
/// suggestion as "not relevant" is permanent — someone without a car or a pet must never keep
/// seeing that reminder again — stored the same lightweight way as every other simple app-wide
/// preference in this app (`@AppStorage`), just as a comma-joined list of suggestion ids rather
/// than one more scalar.
struct ChecklistView: View {
    @EnvironmentObject var store: ItemStore
    @AppStorage("checklistDismissedIDs") private var dismissedIDsRaw = ""
    // A suggestion carries no due date of its own (a passport or a car insurance renewal has no
    // single obvious date the way typed free text often does) — `draftItem(for:)` builds the item
    // but deliberately doesn't persist it yet, so ReminderEngine.notificationDates has nothing to
    // schedule against until this review screen actually saves it. Reviewing it here immediately,
    // the same way "ask every time" AI mode already reviews a freshly-added item before
    // considering it done, is what gets a real reminder set — and, since the draft is only
    // persisted once Save/Mark Done is tapped, dismissing this sheet without either just discards
    // it instead of leaving a blank, unreachable item behind.
    @State private var itemPendingReview: LifeAdminItem?

    private var dismissedIDs: Set<String> {
        Set(dismissedIDsRaw.split(separator: ",").map(String.init))
    }

    private func dismiss(_ suggestion: ChecklistSuggestion) {
        var ids = dismissedIDs
        ids.insert(suggestion.id)
        dismissedIDsRaw = ids.sorted().joined(separator: ",")
        // Dismissing the very last outstanding suggestion should cancel the weekly nudge right
        // away rather than leaving it scheduled until the next item add/edit happens to
        // re-evaluate it (ItemStore only re-checks this as a side effect of its own changes, and
        // dismissing here never goes through ItemStore at all).
        let stillOutstanding = ChecklistEngine().outstandingSuggestions(items: store.items, dismissedIDs: ids).isEmpty == false
        Task { await NotificationScheduler.shared.scheduleChecklistNudge(hasOutstandingSuggestions: stillOutstanding) }
    }

    private var outstanding: [ChecklistSuggestion] {
        ChecklistEngine().outstandingSuggestions(items: store.items, dismissedIDs: dismissedIDs)
    }

    private var covered: [ChecklistSuggestion] {
        ChecklistSuggestion.defaults.filter { suggestion in
            dismissedIDs.contains(suggestion.id) == false && ChecklistEngine().isCovered(suggestion, by: store.items)
        }
    }

    var body: some View {
        List {
            if outstanding.isEmpty && covered.isEmpty {
                ContentUnavailableView(
                    String(localized: "checklist.allDone"),
                    systemImage: "checkmark.seal.fill",
                    description: Text(String(localized: "checklist.allDoneDescription"))
                )
            }
            if outstanding.isEmpty == false {
                Section {
                    ForEach(outstanding) { suggestion in
                        row(for: suggestion, isCovered: false)
                    }
                } header: {
                    Text(String(localized: "checklist.stillNeeded"))
                } footer: {
                    Text(String(localized: "checklist.swipeToDismissHint"))
                }
            }
            if covered.isEmpty == false {
                Section(String(localized: "checklist.alreadyAdded")) {
                    ForEach(covered) { suggestion in
                        row(for: suggestion, isCovered: true)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "checklist.title"))
        .sheet(item: $itemPendingReview) { item in
            NavigationStack {
                ItemDetailView(item: item, isNewDraft: true)
            }
        }
    }

    @ViewBuilder
    private func row(for suggestion: ChecklistSuggestion, isCovered: Bool) -> some View {
        let suggestionTitle = NSLocalizedString(suggestion.titleKey, comment: "")
        HStack(spacing: 12) {
            Image(systemName: isCovered ? "checkmark.circle.fill" : suggestion.systemImage)
                .foregroundStyle(isCovered ? .green : .accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(suggestionTitle)
            Spacer()
            if isCovered == false {
                Button {
                    itemPendingReview = store.draftItem(for: suggestion)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: String(localized: "checklist.addSuggestion"), suggestionTitle))
            }
        }
        .swipeActions(edge: .trailing) {
            if isCovered == false {
                Button {
                    dismiss(suggestion)
                } label: {
                    Label(String(localized: "checklist.notRelevant"), systemImage: "xmark.circle")
                }
                .tint(.gray)
            }
        }
    }
}
