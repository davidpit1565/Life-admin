import Foundation

public enum LifeCategory: String, Codable, CaseIterable, Sendable {
    case documents, insurance, money, bills, subscriptions, car, home, health, travel, work, education, shopping, warranties, memberships, appointments, personal, family, other

    /// Categories where an item's title could itself read as financial or health information —
    /// "Car Insurance" next to a due date is closer to a disclosure than "Gym" is. Notifications
    /// for these stay generic on the lock screen instead of showing the title verbatim.
    public var isSensitive: Bool {
        switch self {
        case .money, .bills, .insurance, .health: return true
        default: return false
        }
    }
}
public enum ItemStatus: String, Codable, CaseIterable, Sendable { case active, completed, snoozed, archived }
public enum Priority: String, Codable, CaseIterable, Comparable, Sendable {
    case low, medium, high, critical
    public static func < (lhs: Priority, rhs: Priority) -> Bool { allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)! }
}
public enum Recurrence: String, Codable, CaseIterable, Sendable { case none, daily, weekly, biweekly, monthly, everyTwoMonths, quarterly, everySixMonths, yearly, custom }
public struct ContactInfo: Codable, Equatable, Sendable { public var name, company, phone, email, website, notes: String?; public init(name: String? = nil, company: String? = nil, phone: String? = nil, email: String? = nil, website: String? = nil, notes: String? = nil) { self.name=name; self.company=company; self.phone=phone; self.email=email; self.website=website; self.notes=notes } }
public struct Attachment: Codable, Identifiable, Equatable, Sendable { public var id: UUID; public var filename: String; public var mimeType: String; public var addedAt: Date; public var sizeBytes: Int; public var localPath: String; public init(id: UUID = UUID(), filename: String, mimeType: String, addedAt: Date = Date(), sizeBytes: Int, localPath: String) { self.id=id; self.filename=filename; self.mimeType=mimeType; self.addedAt=addedAt; self.sizeBytes=sizeBytes; self.localPath=localPath } }
public struct LifeAdminItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID; public var title: String; public var description: String?; public var category: LifeCategory; public var status: ItemStatus; public var priority: Priority; public var priorityOverride: Priority?; public var dueDate: Date?; public var endDate: Date?; public var amount: Decimal?; public var currency: String?; public var recurrence: Recurrence; public var recurrenceRule: String?
    /// The day-of-month a monthly-family recurrence is meant to land on, captured once and then
    /// carried forward unchanged by `RecurrenceEngine` — kept separate from `dueDate` because
    /// `dueDate` itself gets clamped in short months (Jan 31 -> Feb 28), and computing the next
    /// occurrence from that clamped value would permanently shrink every later date to the 28th
    /// instead of returning to the 31st once a long month comes around again. `nil` for items
    /// that don't need it (non-monthly recurrences, or a plain one-off item).
    public var recurrenceAnchorDay: Int?
    public var reminderOffsets: [Int]; public var notes: String?; public var tags: [String]; public var attachments: [Attachment]; public var contact: ContactInfo?; public var location: String?; public var createdAt: Date; public var updatedAt: Date
    public init(id: UUID = UUID(), title: String, description: String? = nil, category: LifeCategory = .other, status: ItemStatus = .active, priority: Priority = .low, priorityOverride: Priority? = nil, dueDate: Date? = nil, endDate: Date? = nil, amount: Decimal? = nil, currency: String? = nil, recurrence: Recurrence = .none, recurrenceRule: String? = nil, recurrenceAnchorDay: Int? = nil, reminderOffsets: [Int] = [], notes: String? = nil, tags: [String] = [], attachments: [Attachment] = [], contact: ContactInfo? = nil, location: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) { self.id=id; self.title=title; self.description=description; self.category=category; self.status=status; self.priority=priority; self.priorityOverride=priorityOverride; self.dueDate=dueDate; self.endDate=endDate; self.amount=amount; self.currency=currency; self.recurrence=recurrence; self.recurrenceRule=recurrenceRule; self.recurrenceAnchorDay=recurrenceAnchorDay; self.reminderOffsets=reminderOffsets; self.notes=notes; self.tags=tags; self.attachments=attachments; self.contact=contact; self.location=location; self.createdAt=createdAt; self.updatedAt=updatedAt }
}
