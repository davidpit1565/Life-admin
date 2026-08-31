import SwiftUI
import ContactsUI
import UIKit
import LifeAdminCore

struct ItemDetailView: View {
    @EnvironmentObject var store: ItemStore
    @Environment(\.dismiss) var dismiss
    let item: LifeAdminItem

    @State private var title: String
    @State private var category: LifeCategory
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var recurrence: Recurrence
    @State private var amountText: String
    @State private var currency: String
    @State private var notes: String
    @State private var name: String
    @State private var company: String
    @State private var email: String
    @State private var attachments: [Attachment]
    @State private var showingContactPicker = false
    @State private var showingDeleteConfirmation = false
    @State private var isSaving = false

    init(item: LifeAdminItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _category = State(initialValue: item.category)
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: item.dueDate ?? Date())
        _recurrence = State(initialValue: item.recurrence)
        _amountText = State(initialValue: item.amount.map { "\($0)" } ?? "")
        _currency = State(initialValue: item.currency ?? "")
        _notes = State(initialValue: item.notes ?? "")
        _name = State(initialValue: item.contact?.name ?? "")
        _company = State(initialValue: item.contact?.company ?? "")
        _email = State(initialValue: item.contact?.email ?? "")
        _attachments = State(initialValue: item.attachments)
    }

    var body: some View {
        Form {
            Section(String(localized: "itemDetail.details")) {
                TextField(String(localized: "itemDetail.title"), text: $title)
                Picker(String(localized: "itemDetail.category"), selection: $category) {
                    ForEach(LifeCategory.allCases, id: \.self) { cat in
                        Label(cat.displayName, systemImage: cat.symbolName).tag(cat)
                    }
                }
            }

            Section(String(localized: "itemDetail.dueDate")) {
                Toggle(String(localized: "itemDetail.hasDueDate"), isOn: $hasDueDate.animation())
                if hasDueDate {
                    DatePicker(String(localized: "itemDetail.dueDate"), selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    // Recurrence with no due date to recur from is exactly the same trap as
                    // .custom above: RecurrenceEngine.nextOccurrence requires a dueDate, so
                    // "Repeat: Monthly" on an item with no due date would silently never fire —
                    // gating this alongside the date picker keeps it from ever being offered
                    // without the one thing it needs to mean anything.
                    Picker(String(localized: "itemDetail.recurrence"), selection: $recurrence) {
                        // .custom is excluded deliberately: there's no UI anywhere to actually
                        // define a custom rule, and RecurrenceEngine treats it exactly like .none
                        // (never recurs) — offering it would let someone pick "Custom", assume
                        // they've set up a schedule, and never find out it silently does nothing.
                        ForEach(Recurrence.allCases.filter { $0 != .custom }, id: \.self) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    // Committing to "every month" sight-unseen is a leap of faith — showing where
                    // it actually lands lets someone catch a wrong choice (e.g. weekly instead of
                    // biweekly) before saving, instead of discovering it three occurrences later.
                    if recurrence != .none, upcomingOccurrences.isEmpty == false {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "itemDetail.recurrence.preview"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(upcomingOccurrences.map { $0.formatted(date: .abbreviated, time: .omitted) }.joined(separator: "  •  "))
                                .font(.caption)
                        }
                    }
                }
            }

            Section(String(localized: "itemDetail.amount")) {
                TextField(String(localized: "itemDetail.amount"), text: $amountText)
                    .keyboardType(.decimalPad)
                // A free-text currency field meant typing a typo (or the wrong case) silently
                // dropped the whole currency on save with zero explanation — Locale.commonISOCurrencyCodes
                // doesn't match "usd" or "dolars". A picker can't produce an invalid value at all.
                // currencyOptions always includes whatever this item already has, even if it's
                // outside the common four, so an AI-detected currency never disappears just from
                // opening this screen.
                Picker(String(localized: "itemDetail.currency"), selection: $currency) {
                    Text(String(localized: "itemDetail.currency.none")).tag("")
                    ForEach(currencyOptions, id: \.self) { code in
                        Text(currencyLabel(code)).tag(code)
                    }
                }
            }

            Section {
                Button {
                    showingContactPicker = true
                } label: {
                    Label(String(localized: "editContact.chooseFromContacts"), systemImage: "person.crop.circle.badge.plus")
                }
            }
            Section(String(localized: "editContact.section")) {
                TextField(String(localized: "editContact.name"), text: $name)
                TextField(String(localized: "editContact.company"), text: $company)
                TextField(String(localized: "editContact.email"), text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section(String(localized: "itemDetail.notes")) {
                TextEditor(text: $notes).frame(minHeight: 80)
            }

            if attachments.isEmpty == false {
                Section(String(localized: "itemDetail.attachments")) {
                    ForEach(attachments) { attachment in
                        HStack {
                            if let uiImage = UIImage(contentsOfFile: AttachmentStore.shared.url(for: attachment).path) {
                                Image(uiImage: uiImage).resizable().scaledToFill()
                                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "doc.fill").foregroundStyle(.secondary)
                            }
                            Text(attachment.filename)
                        }
                    }
                    .onDelete { offsets in
                        // Only remove from this screen's own draft state here — the file on disk
                        // isn't deleted until Save/Mark Done actually commits the change (see
                        // deleteFilesForRemovedAttachments()). Deleting it immediately meant
                        // backing out without saving still permanently destroyed the photo, unlike
                        // every other edit on this screen (title, notes, category, …), which stays
                        // safely discardable until Save is tapped.
                        attachments.remove(atOffsets: offsets)
                    }
                }
            }

            if item.status == .active {
                Section {
                    Button {
                        isSaving = true
                        Task {
                            await markDone()
                            dismiss()
                        }
                    } label: {
                        Label(String(localized: "itemDetail.markDone"), systemImage: "checkmark.circle.fill")
                    }
                    .disabled(isSaving)
                    // Only meaningful with a due date to push forward — the notification banner's
                    // own "Snooze" button always adds a fixed 1 day; this gives the same idea a
                    // few real durations from inside the item itself.
                    if hasDueDate {
                        Menu {
                            ForEach(Self.snoozeOptions) { option in
                                Button(option.label) {
                                    isSaving = true
                                    Task {
                                        // Snoozing an already-overdue item from its own stale due
                                        // date can still land in the past (e.g. 10 days overdue,
                                        // +1 day snooze = 9 days overdue) — snoozing from "now"
                                        // guarantees a real future date the reminder can fire on.
                                        let base = max(dueDate, Date())
                                        dueDate = Calendar.current.date(byAdding: .day, value: option.days, to: base) ?? dueDate
                                        await save()
                                        dismiss()
                                    }
                                }
                            }
                        } label: {
                            Label(String(localized: "itemDetail.snooze"), systemImage: "clock.arrow.circlepath")
                        }
                        .disabled(isSaving)
                    }
                }
            }

            Section {
                Button {
                    isSaving = true
                    Task {
                        await save()
                        dismiss()
                    }
                } label: {
                    // Save/Mark Done/Snooze all call the same async store methods as AddItemView's
                    // Save button, which already learned this lesson: with nothing disabled and no
                    // feedback, a second tap before the first finishes fires a second concurrent
                    // write, and a slow save just looks like the tap did nothing at all.
                    if isSaving {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(String(localized: "common.save"))
                        }
                    } else {
                        Text(String(localized: "common.save"))
                    }
                }
                .disabled(isSaving)
                Button(String(localized: "itemDetail.delete"), role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle(title.isEmpty ? item.title : title)
        .sheet(isPresented: $showingContactPicker) {
            ContactPickerView { contact in
                apply(contact)
            }
        }
        .confirmationDialog(
            String(localized: "itemDetail.deleteConfirm"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "itemDetail.delete"), role: .destructive) {
                Task {
                    await store.delete(item)
                    dismiss()
                }
            }
        }
    }

    private static let commonCurrencyCodes = ["USD", "EUR", "ILS", "GBP"]

    private struct SnoozeOption: Identifiable { let days: Int; let label: String; var id: Int { days } }

    private static let snoozeOptions: [SnoozeOption] = [
        SnoozeOption(days: 1, label: String(localized: "itemDetail.snooze.1day")),
        SnoozeOption(days: 3, label: String(localized: "itemDetail.snooze.3days")),
        SnoozeOption(days: 7, label: String(localized: "itemDetail.snooze.1week"))
    ]

    /// The next 3 dates this recurrence would actually land on, chained from the current due
    /// date — reuses RecurrenceEngine.nextDueDate directly rather than a second implementation
    /// of the same schedule math that could quietly drift out of sync with it. The anchor day is
    /// fixed once from the due date shown here, not re-derived from each chained date in turn —
    /// otherwise a monthly recurrence anchored on the 31st would clamp to the 30th at the first
    /// short month and never show the 31st again, the same drift RecurrenceEngine itself guards
    /// against for the item's real, persisted occurrences.
    private var upcomingOccurrences: [Date] {
        var dates: [Date] = []
        var current = dueDate
        let anchorDay = Calendar.current.component(.day, from: dueDate)
        for _ in 0..<3 {
            guard let next = RecurrenceEngine().nextDueDate(after: current, recurrence: recurrence, anchorDay: anchorDay) else { break }
            dates.append(next)
            current = next
        }
        return dates
    }

    private var currencyOptions: [String] {
        var options = Self.commonCurrencyCodes
        if currency.isEmpty == false && options.contains(currency) == false {
            options.append(currency)
        }
        return options
    }

    private func currencyLabel(_ code: String) -> String {
        guard let name = Locale.current.localizedString(forCurrencyCode: code) else { return code }
        // A Latin currency code stitched to a Hebrew/Arabic name with a plain dash is exactly the
        // mixed-direction case that makes the dash (and whatever follows it) jump to the wrong
        // side — wrapping the code in explicit directional isolates keeps it as a self-contained
        // LTR run no matter which way the rest of the string flows.
        let isolatedCode = "\u{2066}\(code)\u{2069}"
        return "\(isolatedCode) – \(name)"
    }

    private func apply(_ contact: CNContact) {
        let fullName = [contact.givenName, contact.familyName].filter { $0.isEmpty == false }.joined(separator: " ")
        if fullName.isEmpty == false { name = fullName }
        if contact.organizationName.isEmpty == false { company = contact.organizationName }
        if let firstEmail = contact.emailAddresses.first?.value as String? { email = firstEmail }
    }

    private func fieldsApplied(to base: LifeAdminItem) -> LifeAdminItem {
        var updated = base
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmedTitle.isEmpty ? base.title : trimmedTitle
        updated.category = category
        updated.dueDate = hasDueDate ? dueDate : nil
        // Recurrence is meaningless without a due date to recur from — the picker itself is
        // already hidden in that case, but the state variable could otherwise still hold a
        // stale value from before "Has due date" was turned off.
        updated.recurrence = hasDueDate ? recurrence : .none
        // Re-derived from whatever due date is on screen right now rather than left as
        // whatever it was on `base` — otherwise editing an existing recurring item's due date
        // to a different day of the month would silently keep recurring on the OLD day, since
        // RecurrenceEngine only re-derives this itself the first time it's nil.
        updated.recurrenceAnchorDay = hasDueDate ? Calendar.current.component(.day, from: dueDate) : nil
        // .decimalPad shows the device's own locale-appropriate separator (e.g. "," in many
        // European locales) — parsing with Decimal(string:) alone only ever accepts ".", silently
        // dropping the amount entirely for anyone whose keyboard shows anything else.
        updated.amount = Decimal(string: amountText.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale.current)
        // currency is a Picker now (see currencyOptions) — it can only ever hold "" or a code
        // that's either one of the common four or the item's own pre-existing value, so there's
        // nothing left here to trim, uppercase, or validate.
        updated.currency = currency.isEmpty ? nil : currency
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        updated.attachments = attachments
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.contact = (trimmedName.isEmpty && trimmedCompany.isEmpty && trimmedEmail.isEmpty) ? nil : ContactInfo(
            name: trimmedName.isEmpty ? nil : trimmedName,
            company: trimmedCompany.isEmpty ? nil : trimmedCompany,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail
        )
        updated.updatedAt = Date()
        return updated
    }

    // `item` is only ever the snapshot this view was created with — if a notification action
    // (e.g. "Mark Done" tapped on this same item's own banner) mutates the store while this
    // screen is still open, building on that stale snapshot would silently overwrite whatever
    // just happened (reviving a just-completed item back to active, dropping a snooze) the
    // moment this screen's own Save/Mark Done runs. Basing edits on the store's current copy
    // instead means only fields this form actually touches change; anything else reflects
    // whatever most recently happened elsewhere.
    private var currentItem: LifeAdminItem {
        store.items.first(where: { $0.id == item.id }) ?? item
    }

    /// Deletes the on-disk file for any attachment the user swiped away on this screen — deferred
    /// until here (rather than at the moment of the swipe) so the removal only actually happens
    /// once it's committed via Save/Mark Done, matching every other edit on this form.
    private func deleteFilesForRemovedAttachments() {
        let removed = item.attachments.filter { attachments.contains($0) == false }
        for attachment in removed {
            AttachmentStore.shared.delete(attachment)
        }
    }

    private func save() async {
        deleteFilesForRemovedAttachments()
        var updated = fieldsApplied(to: currentItem)
        updated.priority = PriorityEngine().priority(for: updated)
        await store.update(updated)
    }

    private func markDone() async {
        deleteFilesForRemovedAttachments()
        var updated = fieldsApplied(to: currentItem)
        updated.priority = PriorityEngine().priority(for: updated)
        await store.markCompleted(updated)
    }
}
