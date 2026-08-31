import SwiftUI
import MessageUI
import LifeAdminCore

struct AddressChangeView: View {
    @EnvironmentObject var store: ItemStore
    @State private var newAddress = ""
    @State private var selectedItemIDs = Set<UUID>()
    @State private var queue: [AddressChangeMessage] = []
    @State private var currentMessage: AddressChangeMessage?
    // Most users only ever use a third-party mail app (Gmail, Outlook) and have never configured
    // the native Mail app at all — MFMailComposeViewController.canSendMail() being false used to
    // just dead-end the entire feature behind an alert with no way to actually send anything.
    // Falling back to the system share sheet lets the exact same drafted subject/body go to
    // whatever the user actually uses (their mail app, Messages, or a plain copy).
    @State private var useShareFallback = false
    @State private var failedItemTitles: [String] = []
    @State private var showingSendSummary = false

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
                                    // Purely decorative: the selection state it shows is already
                                    // conveyed to VoiceOver via .isSelected below. Without this,
                                    // the symbol's own name ("Checkmark, circle, fill" / "Circle")
                                    // gets announced on every row on top of that.
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.plain)
                        // The checkmark/circle swap conveys selection visually but says nothing
                        // to VoiceOver on its own — the row's title is still the accessible label,
                        // this just adds the state that a sighted user gets from the icon alone.
                        .accessibilityAddTraits(selectedItemIDs.contains(item.id) ? .isSelected : [])
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
            if useShareFallback {
                ShareSheet(activityItems: [shareText(for: message)])
                    .onDisappear { advanceQueueAfterShare(message) }
            } else {
                MailComposeView(message: message) { result in
                    handleResult(result, for: message)
                }
            }
        }
        // A failed send was otherwise indistinguishable from the user simply cancelling that
        // one draft — silently advancing to the next item left no way to tell "I chose to skip
        // this one" from "this one actually didn't go through".
        .alert(String(localized: "addressChange.sendFailedTitle"), isPresented: $showingSendSummary) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(String(format: String(localized: "addressChange.sendFailedMessage"), failedItemTitles.joined(separator: ", ")))
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
        useShareFallback = MFMailComposeViewController.canSendMail() == false
        failedItemTitles = []
        let selected = affectedItems.filter { selectedItemIDs.contains($0.id) }
        queue = AddressChangeDraftBuilder().drafts(for: selected, newAddress: newAddress)
        advanceQueue()
    }

    private func advanceQueue() {
        currentMessage = queue.first
        if currentMessage == nil && failedItemTitles.isEmpty == false {
            showingSendSummary = true
        }
    }

    /// A recipient's email/name plus the exact subject/body `MailComposeView` would have used —
    /// whatever app the user picks from the share sheet gets the same drafted content, not a
    /// vaguer summary.
    private func shareText(for message: AddressChangeMessage) -> String {
        let recipient = message.recipientName.map { "\($0) <\(message.recipientEmail)>" } ?? message.recipientEmail
        return "\(recipient)\n\(message.subject)\n\n\(message.body)"
    }

    /// Unlike `handleResult`'s Mail-specific `.sent`/`.failed`/`.cancelled` outcome, the share
    /// sheet gives no signal at all about whether the user actually sent anything (picking an app
    /// vs. tapping Cancel both just dismiss it the same way) — so this never marks the item as
    /// address-synced, unlike the Mail path's confirmed-`.sent` case. It'll simply stay in
    /// "affected items" and can be sent again next time, which is the honest default when there's
    /// no way to confirm delivery either way.
    private func advanceQueueAfterShare(_ message: AddressChangeMessage) {
        queue.removeAll { $0.itemID == message.itemID }
        currentMessage = nil
        advanceQueue()
    }

    private func handleResult(_ result: MFMailComposeResult, for message: AddressChangeMessage) {
        queue.removeAll { $0.itemID == message.itemID }
        currentMessage = nil
        if result == .failed {
            let title = affectedItems.first { $0.id == message.itemID }?.title ?? message.subject
            failedItemTitles.append(title)
        }
        Task {
            if result == .sent {
                await store.markAddressSynced(message.itemID)
            }
            try? await Task.sleep(for: .seconds(0.3))
            advanceQueue()
        }
    }
}
