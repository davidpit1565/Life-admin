import SwiftUI
import MessageUI
import LifeAdminCore

struct AddressChangeView: View {
    @EnvironmentObject var store: ItemStore
    @State private var newAddress = ""
    @State private var selectedItemIDs = Set<UUID>()
    @State private var queue: [AddressChangeMessage] = []
    @State private var currentMessage: AddressChangeMessage?
    @State private var showMailUnavailableAlert = false

    private var affectedItems: [LifeAdminItem] {
        AddressChangeEngine().affectedItems(in: store.items)
    }

    var body: some View {
        Form {
            Section(String(localized: "addressChange.newAddressPrompt")) {
                TextField(String(localized: "addressChange.newAddressPlaceholder"), text: $newAddress, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section(String(localized: "addressChange.affectedItems")) {
                if affectedItems.isEmpty {
                    Text(String(localized: "addressChange.noAffectedItems"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(affectedItems) { item in
                        Button {
                            toggle(item.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.title)
                                    if let contact = item.contact {
                                        Text(contact.name ?? contact.company ?? contact.email ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedItemIDs.contains(item.id) ? Color.accentColor : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button(String(localized: "addressChange.reviewSend")) {
                    startSending()
                }
                .disabled(newAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedItemIDs.isEmpty)
            }
        }
        .navigationTitle(String(localized: "addressChange.title"))
        .onAppear {
            selectedItemIDs = Set(affectedItems.map(\.id))
        }
        .sheet(item: $currentMessage) { message in
            MailComposeView(message: message) { result in
                handleResult(result, for: message)
            }
        }
        .alert(String(localized: "addressChange.mailUnavailable"), isPresented: $showMailUnavailableAlert) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        }
    }

    private func toggle(_ id: UUID) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    private func startSending() {
        guard MFMailComposeViewController.canSendMail() else {
            showMailUnavailableAlert = true
            return
        }
        let selected = affectedItems.filter { selectedItemIDs.contains($0.id) }
        queue = AddressChangeDraftBuilder().drafts(for: selected, newAddress: newAddress)
        advanceQueue()
    }

    private func advanceQueue() {
        currentMessage = queue.first
    }

    private func handleResult(_ result: MFMailComposeResult, for message: AddressChangeMessage) {
        if result == .sent {
            store.markAddressSynced(message.itemID)
        }
        queue.removeAll { $0.itemID == message.itemID }
        currentMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            advanceQueue()
        }
    }
}
