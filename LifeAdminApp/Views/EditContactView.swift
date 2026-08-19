import SwiftUI
import LifeAdminCore

struct EditContactView: View {
    @EnvironmentObject var store: ItemStore
    @Environment(\.dismiss) var dismiss
    let item: LifeAdminItem
    @State private var name: String
    @State private var company: String
    @State private var email: String

    init(item: LifeAdminItem) {
        self.item = item
        _name = State(initialValue: item.contact?.name ?? "")
        _company = State(initialValue: item.contact?.company ?? "")
        _email = State(initialValue: item.contact?.email ?? "")
    }

    var body: some View {
        Form {
            Section(String(localized: "editContact.section")) {
                TextField(String(localized: "editContact.name"), text: $name)
                TextField(String(localized: "editContact.company"), text: $company)
                TextField(String(localized: "editContact.email"), text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button(String(localized: "common.save")) {
                    save()
                    dismiss()
                }
            }
        }
        .navigationTitle(item.title)
    }

    private func save() {
        var updated = item
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.contact = ContactInfo(
            name: trimmedName.isEmpty ? nil : trimmedName,
            company: trimmedCompany.isEmpty ? nil : trimmedCompany,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail
        )
        store.update(updated)
    }
}
