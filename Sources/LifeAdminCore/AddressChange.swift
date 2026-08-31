import Foundation

public struct AddressChangeMessage: Identifiable, Equatable, Sendable {
    public var id: UUID { itemID }
    public let itemID: UUID
    public let recipientEmail: String
    public let recipientName: String?
    public let subject: String
    public let body: String

    public init(itemID: UUID, recipientEmail: String, recipientName: String?, subject: String, body: String) {
        self.itemID = itemID
        self.recipientEmail = recipientEmail
        self.recipientName = recipientName
        self.subject = subject
        self.body = body
    }
}

public struct AddressChangeEngine: Sendable {
    public static let syncedTag = "address-synced"

    public init() {}

    public func affectedItems(in items: [LifeAdminItem]) -> [LifeAdminItem] {
        items.filter { item in
            guard let email = item.contact?.email, email.isEmpty == false else { return false }
            return item.tags.contains(Self.syncedTag) == false
        }
    }
}

public struct AddressChangeDraftBuilder: Sendable {
    public init() {}

    public func draft(for item: LifeAdminItem, newAddress: String) -> AddressChangeMessage? {
        guard let email = item.contact?.email, email.isEmpty == false else { return nil }
        let trimmedAddress = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        // A blank (or whitespace-only) address would still build and could still get sent — a
        // real email telling a real vendor "update my address on file to: <nothing>" — so this
        // bails out the same way a missing recipient email already does above.
        guard trimmedAddress.isEmpty == false else { return nil }
        let recipientName = item.contact?.name ?? item.contact?.company
        let greeting = recipientName.map { "Hello \($0)," } ?? "Hello,"
        let subject = "Address update – \(item.title)"
        let body = "\(greeting)\n\nPlease update my address on file for \(item.title) to:\n\(trimmedAddress)\n\nThank you."
        return AddressChangeMessage(itemID: item.id, recipientEmail: email, recipientName: recipientName, subject: subject, body: body)
    }

    public func drafts(for items: [LifeAdminItem], newAddress: String) -> [AddressChangeMessage] {
        items.compactMap { draft(for: $0, newAddress: newAddress) }
    }
}
