import SwiftUI
import ContactsUI
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
    }

    var body: some View {
        Form {
            Section(String(localized: "itemDetail.details")) {
                TextField(String(localized: "itemDetail.title"), text: $title)
                Picker(String(localized: "itemDetail.category"), selection: $category) {
                    ForEach(LifeCategory.allCases, id: \.self) { cat in
                        Label(cat.rawValue.capitalized, systemImage: cat.symbolName).tag(cat)
                    }
                }
            }

            Section(String(localized: "itemDetail.dueDate")) {
                Toggle(String(localized: "itemDetail.hasDueDate"), isOn: $hasDueDate.animation())
                if hasDueDate {
                    DatePicker(String(localized: "itemDetail.dueDate"), selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
                Picker(String(localized: "itemDetail.recurrence"), selection: $recurrence) {
                    ForEach(Recurrence.allCases, id: \.self) { r in
                        Text(r.rawValue.capitalized).tag(r)
                    }
                }
            }

            Section(String(localized: "itemDetail.amount")) {
                TextField(String(localized: "itemDetail.amount"), text: $amountText)
                    .keyboardType(.decimalPad)
                TextField(String(localized: "itemDetail.currency"), text: $currency)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
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
        updated.recurrence = recurrence
        // .decimalPad shows the device's own locale-appropriate separator (e.g. "," in many
        // European locales) — parsing with Decimal(string:) alone only ever accepts ".", silently
        // dropping the amount entirely for anyone whose keyboard shows anything else.
        updated.amount = Decimal(string: amountText.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale.current)
        // The AI-extraction path already rejects an invalid ISO currency code before it ever
        // reaches an item (see LifeAdminAIService.validateStructuredExtraction) — this free-text
        // field was the one place nothing checked it, so a typo here would silently save a
        // currency code that formats wrong (or not at all) everywhere the amount is shown.
        let trimmedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        updated.currency = Locale.commonISOCurrencyCodes.contains(trimmedCurrency) ? trimmedCurrency : nil
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
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
