import Foundation

public enum LifeCategory: String, Codable, CaseIterable, Sendable {
    case documents, insurance, money, bills, subscriptions, car, home, health, travel, work, education, shopping, warranties, memberships, appointments, personal, family, other

    /// Categories where an item's title could itself read as financial, health, or identity
    /// information — "Car Insurance" next to a due date is closer to a disclosure than "Gym" is,
    /// and the same goes for a passport/ID renewal (`.documents`), a visa (`.travel`), or
    /// anything filed as `.personal`. Notifications for these stay generic on the lock screen
    /// instead of showing the title verbatim, and CalendarSyncService uses the same check before
    /// writing a title into the system Calendar/Reminders (shared calendars, unencrypted backups).
    public var isSensitive: Bool {
        switch self {
        case .money, .bills, .insurance, .health, .documents, .travel, .personal: return true
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
/// One arbitrary label/value detail on an item — a passport number, a card's expiry month/year,
/// a policy number — for whatever specifics a given item's own document actually has, rather than
/// a fixed set of columns every category would otherwise have to share. Filled in either by hand
/// or from a scanned document's OCR text (see `DocumentFieldSuggestion`, and `DocumentFieldSafety`
/// for what's never allowed to end up here). Unlike `DocumentFieldSuggestion`, this carries a
/// stable `id` because it needs one: for a SwiftUI list identity that survives reordering/editing,
/// and because it's the type actually persisted on `LifeAdminItem`.
public struct DocumentField: Codable, Identifiable, Equatable, Sendable { public var id: UUID; public var label: String; public var value: String; public init(id: UUID = UUID(), label: String, value: String) { self.id=id; self.label=label; self.value=value } }
public struct LifeAdminItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID; public var title: String; public var description: String?; public var category: LifeCategory; public var status: ItemStatus; public var priority: Priority; public var priorityOverride: Priority?; public var dueDate: Date?; public var endDate: Date?; public var amount: Decimal?; public var currency: String?; public var recurrence: Recurrence; public var recurrenceRule: String?
    /// The day-of-month a monthly-family recurrence is meant to land on, captured once and then
    /// carried forward unchanged by `RecurrenceEngine` — kept separate from `dueDate` because
    /// `dueDate` itself gets clamped in short months (Jan 31 -> Feb 28), and computing the next
    /// occurrence from that clamped value would permanently shrink every later date to the 28th
    /// instead of returning to the 31st once a long month comes around again. `nil` for items
    /// that don't need it (non-monthly recurrences, or a plain one-off item).
    public var recurrenceAnchorDay: Int?
    /// The amount from the occurrence this one was generated from (`RecurrenceEngine.nextOccurrence`
    /// carries it forward, separately from `amount` itself), so a renewal that comes in higher —
    /// insurance, a subscription price hike — can be flagged instead of the increase quietly
    /// blending into "just this year's number". `nil` for a plain one-off item, or the very first
    /// occurrence of a recurring one, which has nothing yet to compare against.
    public var previousAmount: Decimal?
    public var reminderOffsets: [Int]; public var notes: String?; public var tags: [String]; public var attachments: [Attachment]; public var contact: ContactInfo?; public var location: String?
    /// Free-form document-specific details — a passport number, a card's bank name and expiry, an
    /// insurance policy number — that no fixed set of item fields could anticipate for every
    /// category. See `DocumentField`'s own doc comment.
    public var documentFields: [DocumentField]; public var createdAt: Date; public var updatedAt: Date
    public init(id: UUID = UUID(), title: String, description: String? = nil, category: LifeCategory = .other, status: ItemStatus = .active, priority: Priority = .low, priorityOverride: Priority? = nil, dueDate: Date? = nil, endDate: Date? = nil, amount: Decimal? = nil, currency: String? = nil, recurrence: Recurrence = .none, recurrenceRule: String? = nil, recurrenceAnchorDay: Int? = nil, previousAmount: Decimal? = nil, reminderOffsets: [Int] = [], notes: String? = nil, tags: [String] = [], attachments: [Attachment] = [], contact: ContactInfo? = nil, location: String? = nil, documentFields: [DocumentField] = [], createdAt: Date = Date(), updatedAt: Date = Date()) { self.id=id; self.title=title; self.description=description; self.category=category; self.status=status; self.priority=priority; self.priorityOverride=priorityOverride; self.dueDate=dueDate; self.endDate=endDate; self.amount=amount; self.currency=currency; self.recurrence=recurrence; self.recurrenceRule=recurrenceRule; self.recurrenceAnchorDay=recurrenceAnchorDay; self.previousAmount=previousAmount; self.reminderOffsets=reminderOffsets; self.notes=notes; self.tags=tags; self.attachments=attachments; self.contact=contact; self.location=location; self.documentFields=documentFields; self.createdAt=createdAt; self.updatedAt=updatedAt }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, category, status, priority, priorityOverride, dueDate, endDate, amount, currency, recurrence, recurrenceRule, recurrenceAnchorDay, previousAmount, reminderOffsets, notes, tags, attachments, contact, location, documentFields, createdAt, updatedAt
    }

    // A backup exported before `documentFields` existed has no such key at all — same situation
    // `recurrenceAnchorDay` (an Optional) already handles for free via synthesized Codable, but
    // `documentFields` is deliberately a plain non-optional array everywhere else in the app (like
    // `attachments`/`tags`), so decoding it needs this explicit fallback instead.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        category = try c.decode(LifeCategory.self, forKey: .category)
        status = try c.decode(ItemStatus.self, forKey: .status)
        priority = try c.decode(Priority.self, forKey: .priority)
        priorityOverride = try c.decodeIfPresent(Priority.self, forKey: .priorityOverride)
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        amount = try c.decodeIfPresent(Decimal.self, forKey: .amount)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        recurrence = try c.decode(Recurrence.self, forKey: .recurrence)
        recurrenceRule = try c.decodeIfPresent(String.self, forKey: .recurrenceRule)
        recurrenceAnchorDay = try c.decodeIfPresent(Int.self, forKey: .recurrenceAnchorDay)
        previousAmount = try c.decodeIfPresent(Decimal.self, forKey: .previousAmount)
        reminderOffsets = try c.decode([Int].self, forKey: .reminderOffsets)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        tags = try c.decode([String].self, forKey: .tags)
        attachments = try c.decode([Attachment].self, forKey: .attachments)
        contact = try c.decodeIfPresent(ContactInfo.self, forKey: .contact)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        documentFields = try c.decodeIfPresent([DocumentField].self, forKey: .documentFields) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}
