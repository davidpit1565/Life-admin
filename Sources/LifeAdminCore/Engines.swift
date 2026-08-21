import Foundation

public enum LifeAdminError: Error, LocalizedError { case invalidTitle, invalidDate, invalidCurrency, oversizedAttachment, invalidJSON; public var errorDescription: String? { "Something went wrong. Please try again." } }
public struct ItemValidator { public init() {} ; public func validate(_ item: LifeAdminItem) throws { if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw LifeAdminError.invalidTitle }; if let c=item.currency, Locale.commonISOCurrencyCodes.contains(c.uppercased()) == false { throw LifeAdminError.invalidCurrency }; if let d=item.dueDate, d < Date(timeIntervalSince1970: 0) { throw LifeAdminError.invalidDate }; for a in item.attachments where a.sizeBytes > 25_000_000 { throw LifeAdminError.oversizedAttachment } } }
public struct PriorityEngine { public init() {} ; public func priority(for item: LifeAdminItem, now: Date = Date()) -> Priority { if let o=item.priorityOverride { return o }; var score = 0; if let due=item.dueDate { let days = Calendar.current.dateComponents([.day], from: now, to: due).day ?? 9999; score += days <= 1 ? 5 : days <= 7 ? 4 : days <= 30 ? 2 : 0 }; if item.amount != nil { score += 1 }; if [.documents,.insurance,.warranties,.memberships].contains(item.category) { score += 2 }; if item.recurrence != .none { score += 1 }; return score >= 7 ? .critical : score >= 5 ? .high : score >= 2 ? .medium : .low } }
public struct ReminderEngine {
    public init() {}

    /// Critical items get a same-day reminder in addition to whatever offsets were already set,
    /// so the reminder cadence escalates automatically as the deadline gets close instead of
    /// relying on a single fixed lead time chosen when the item was created.
    public func notificationDates(for item: LifeAdminItem, calendar: Calendar = .current) -> [Date] {
        guard item.status == .active, let due = item.dueDate else { return [] }
        var offsets = item.reminderOffsets
        if item.priority == .critical, offsets.contains(0) == false {
            offsets.append(0)
        }
        return offsets.compactMap { calendar.date(byAdding: .day, value: -$0, to: due) }.filter { $0 > Date(timeIntervalSince1970: 0) }.sorted()
    }
}
public struct LifeEventDetector: Sendable {
    public init() {}

    public static let movingTag = "life-event-moving"

    private static let movingKeywords = ["moving to", "moving out", "i'm moving", "im moving", "new address", "changed my address", "change of address", "new apartment", "new house", "relocat"]

    /// Scans raw input text (independent of however the item itself got parsed) for phrases that
    /// signal a life event with cascading admin consequences, so the app can proactively surface
    /// the relevant follow-up flow instead of waiting for the user to remember it exists.
    public func detectedTags(in text: String) -> [String] {
        let lower = text.lowercased()
        return Self.movingKeywords.contains { lower.contains($0) } ? [Self.movingTag] : []
    }
}
public struct SearchFilter: Sendable { public var query: String = ""; public var categories: Set<LifeCategory> = []; public var statuses: Set<ItemStatus> = []; public var priorities: Set<Priority> = []; public var hasAttachment: Bool?; public var hasPayment: Bool?; public init() {} }
public struct SearchEngine { public init() {} ; public func search(_ items: [LifeAdminItem], filter: SearchFilter) -> [LifeAdminItem] { items.filter { item in let hay=[item.title,item.description,item.notes,item.contact?.name,item.contact?.company,item.amount.map(String.init(describing:)),item.currency,item.tags.joined(separator:" ")].compactMap{$0}.joined(separator:" ").localizedCaseInsensitiveContains(filter.query) || filter.query.isEmpty; return hay && (filter.categories.isEmpty || filter.categories.contains(item.category)) && (filter.statuses.isEmpty || filter.statuses.contains(item.status)) && (filter.priorities.isEmpty || filter.priorities.contains(item.priority)) && (filter.hasAttachment == nil || filter.hasAttachment == !(item.attachments.isEmpty)) && (filter.hasPayment == nil || filter.hasPayment == (item.amount != nil)) } } }
public struct DuplicateDetector { public init() {} ; public func isLikelyDuplicate(_ a: LifeAdminItem, _ b: LifeAdminItem) -> Bool { let title = a.title.lowercased() == b.title.lowercased(); let company = a.contact?.company?.lowercased() == b.contact?.company?.lowercased() && a.contact?.company != nil; let amount = a.amount == b.amount && a.amount != nil; let closeDate = abs((a.dueDate ?? .distantPast).timeIntervalSince(b.dueDate ?? .distantFuture)) < 86400*3; return (title && (closeDate || amount)) || (company && closeDate) } }
public struct DigestEngine: Sendable {
    public init() {}

    public struct Summary: Equatable, Sendable {
        public var overdueCount: Int
        public var dueTodayCount: Int
        public var dueThisWeekCount: Int
        public var topItem: LifeAdminItem?
    }

    public func summary(for items: [LifeAdminItem], now: Date = Date(), calendar: Calendar = .current) -> Summary {
        let active = items.filter { $0.status == .active }
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: now) ?? now

        let overdue = active.filter { ($0.dueDate ?? .distantFuture) < startOfToday }
        let dueToday = active.filter { guard let due = $0.dueDate else { return false }; return due >= startOfToday && due < startOfTomorrow }
        let dueThisWeek = active.filter { guard let due = $0.dueDate else { return false }; return due >= now && due <= weekEnd }
        let top = (overdue + dueToday).sorted { $0.priority > $1.priority }.first

        return Summary(overdueCount: overdue.count, dueTodayCount: dueToday.count, dueThisWeekCount: dueThisWeek.count, topItem: top)
    }

    public func shouldNotify(_ summary: Summary) -> Bool {
        summary.overdueCount > 0 || summary.dueTodayCount > 0
    }
}
public struct ImportExportEngine { let encoder=JSONEncoder(); let decoder=JSONDecoder(); public init() { encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601 }; public func exportJSON(_ items: [LifeAdminItem]) throws -> Data { try encoder.encode(items) }; public func importJSON(_ data: Data) throws -> [LifeAdminItem] { let items = try decoder.decode([LifeAdminItem].self, from: data); try items.forEach { try ItemValidator().validate($0) }; return items }; public func exportCSV(_ items: [LifeAdminItem]) -> String { (["Title,Category,Status,Priority,DueDate,Amount,Currency"] + items.map { "\($0.title),\($0.category.rawValue),\($0.status.rawValue),\($0.priority.rawValue),\($0.dueDate?.ISO8601Format() ?? ""),\($0.amount.map(String.init(describing:)) ?? ""),\($0.currency ?? "")" }).joined(separator:"\n") } }
