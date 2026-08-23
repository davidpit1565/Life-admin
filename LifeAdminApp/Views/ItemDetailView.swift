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
                        for index in offsets { AttachmentStore.shared.delete(attachments[index]) }
                        attachments.remove(atOffsets: offsets)
                    }
                }
            }

            if item.status == .active {
                Section {
                    Button {
                        Task {
                            await markDone()
                            dismiss()
                        }
                    } label: {
                        Label(String(localized: "itemDetail.markDone"), systemImage: "checkmark.circle.fill")
                    }
                    // Only meaningful with a due date to push forward — the notification banner's
                    // own "Snooze" button always adds a fixed 1 day; this gives the same idea a
                    // few real durations from inside the item itself.
                    if hasDueDate {
                        Menu {
                            ForEach(Self.snoozeOptions) { option in
                                Button(option.label) {
                                    Task {
                                        dueDate = Calendar.current.date(byAdding: .day, value: option.days, to: dueDate) ?? dueDate
                                        await save()
                                        dismiss()
                                    }
                                }
                            }
                        } label: {
                            Label(String(localized: "itemDetail.snooze"), systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            }

            Section {
                Button(String(localized: "common.save")) {
                    Task {
                        await save()
                        dismiss()
                    }
                }
                Button(String(localized: "itemDetail.delete"), role: .destructive) {
                    showingDeleteConfirmation = true
                }
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

    private var currencyOptions: [String] {
        var options = Self.commonCurrencyCodes
        if currency.isEmpty == false && options.contains(currency) == false {
            options.append(currency)
        }
        return options
    }

    private func currencyLabel(_ code: String) -> String {
        guard let name = Locale.current.localizedString(forCurrencyCode: code) else { return code }
        return "\(code) – \(name)"
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
        updated.title = trimmedTitle.isEmpty ? item.title : trimmedTitle
        updated.category = category
        updated.dueDate = hasDueDate ? dueDate : nil
        // Recurrence is meaningless without a due date to recur from — the picker itself is
        // already hidden in that case, but the state variable could otherwise still hold a
        // stale value from before "Has due date" was turned off.
        updated.recurrence = hasDueDate ? recurrence : .none
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

    private func save() async {
        var updated = fieldsApplied(to: item)
        updated.priority = PriorityEngine().priority(for: updated)
        await store.update(updated)
    }

    private func markDone() async {
        var updated = fieldsApplied(to: item)
        updated.priority = PriorityEngine().priority(for: updated)
        await store.markCompleted(updated)
    }
}
