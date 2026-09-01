import Foundation

public enum LifeAdminError: Error, LocalizedError { case invalidTitle, invalidDate, invalidCurrency, oversizedAttachment, invalidAmount, invalidAttachment, invalidJSON; public var errorDescription: String? { "Something went wrong. Please try again." } }
public struct ItemValidator { public init() {} ; public func validate(_ item: LifeAdminItem) throws { if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw LifeAdminError.invalidTitle }; if let c=item.currency, Locale.commonISOCurrencyCodes.contains(c.uppercased()) == false { throw LifeAdminError.invalidCurrency }; if let d=item.dueDate, d < Date(timeIntervalSince1970: 0) { throw LifeAdminError.invalidDate }; if let amount=item.amount, amount < 0 { throw LifeAdminError.invalidAmount }; for a in item.attachments { if a.sizeBytes > 25_000_000 { throw LifeAdminError.oversizedAttachment }; if a.sizeBytes < 0 { throw LifeAdminError.invalidAttachment } } } }
public struct PriorityEngine { public init() {} ; public func priority(for item: LifeAdminItem, now: Date = Date()) -> Priority { if let o=item.priorityOverride { return o }; var score = 0; if let due=item.dueDate { let days = Calendar.current.dateComponents([.day], from: now, to: due).day ?? 9999; score += days <= 1 ? 5 : days <= 7 ? 4 : days <= 30 ? 2 : 0 }; if item.amount != nil { score += 1 }; if [.documents,.insurance,.warranties,.memberships].contains(item.category) { score += 2 }; if item.recurrence != .none { score += 1 }; return score >= 7 ? .critical : score >= 5 ? .high : score >= 2 ? .medium : .low } }
public struct ReminderEngine {
    public init() {}

    /// Critical items get a same-day reminder in addition to whatever offsets were already set,
    /// so the reminder cadence escalates automatically as the deadline gets close instead of
    /// relying on a single fixed lead time chosen when the item was created.
    ///
    /// Travel items default to offsets of [90, 30, 7, 1] days — for something due in, say, 10
    /// days, the 90- and 30-day offsets land in the past. Scheduling a local notification with a
    /// past trigger date fires it right away, so without filtering against `now`, adding that one
    /// item would immediately blast out two bogus "reminders" before the app even finishes saving
    /// it — this filters to offsets that still land in the future, not just after the Unix epoch.
    public func notificationDates(for item: LifeAdminItem, calendar: Calendar = .current, now: Date = Date()) -> [Date] {
        guard item.status == .active, let due = item.dueDate else { return [] }
        var offsets = item.reminderOffsets
        if item.priority == .critical, offsets.contains(0) == false {
            offsets.append(0)
        }
        return offsets.compactMap { calendar.date(byAdding: .day, value: -$0, to: due) }.filter { $0 > now }.sorted()
    }

    /// A one-size-fits-all lead time doesn't fit what these categories actually involve: renewing
    /// a passport or shopping around for a new insurance policy is a weeks-long process someone
    /// needs real advance notice for, while cancelling a subscription or gym membership is a
    /// same-day decision that a month's notice would just mean forgetting about again before it's
    /// due. Callers building a brand-new item — nothing here changes an item someone already
    /// created with different offsets — should use this instead of a single hardcoded default.
    public static func defaultOffsets(for category: LifeCategory) -> [Int] {
        switch category {
        case .travel, .insurance, .documents, .warranties:
            return [90, 30, 7, 1]
        case .subscriptions, .memberships:
            return [3, 1]
        default:
            return [30, 7]
        }
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
public struct SearchFilter: Sendable { public var query: String = ""; public var categories: Set<LifeCategory> = []; public var statuses: Set<ItemStatus> = []; public var priorities: Set<Priority> = []; public var hasAttachment: Bool?; public var hasPayment: Bool?; public var dueFrom: Date?; public var dueTo: Date?; public init() {} }
public struct SearchEngine { public init() {} ; public func search(_ items: [LifeAdminItem], filter: SearchFilter) -> [LifeAdminItem] { items.filter { item in let hay=[item.title,item.description,item.notes,item.contact?.name,item.contact?.company,item.amount.map(String.init(describing:)),item.currency,item.tags.joined(separator:" ")].compactMap{$0}.joined(separator:" ").localizedCaseInsensitiveContains(filter.query) || filter.query.isEmpty; return hay && (filter.categories.isEmpty || filter.categories.contains(item.category)) && (filter.statuses.isEmpty || filter.statuses.contains(item.status)) && (filter.priorities.isEmpty || filter.priorities.contains(item.priority)) && (filter.hasAttachment == nil || filter.hasAttachment == !(item.attachments.isEmpty)) && (filter.hasPayment == nil || filter.hasPayment == (item.amount != nil)) && (filter.dueFrom == nil || (item.dueDate != nil && item.dueDate! >= filter.dueFrom!)) && (filter.dueTo == nil || (item.dueDate != nil && item.dueDate! <= filter.dueTo!)) } } }
// `amount` also requires matching currency — otherwise a 100 EUR item and an unrelated 100 ILS
// item would compare equal on the raw `Decimal` alone and get flagged as the same bill.
public struct DuplicateDetector { public init() {} ; public func isLikelyDuplicate(_ a: LifeAdminItem, _ b: LifeAdminItem) -> Bool { let title = a.title.lowercased() == b.title.lowercased(); let company = a.contact?.company?.lowercased() == b.contact?.company?.lowercased() && a.contact?.company != nil; let amount = a.amount == b.amount && a.amount != nil && a.currency == b.currency; let closeDate = abs((a.dueDate ?? .distantPast).timeIntervalSince(b.dueDate ?? .distantFuture)) < 86400*3; return (title && (closeDate || amount)) || (company && closeDate) } }

/// Competitor subscription trackers (Rocket Money and similar) flag overlapping/redundant
/// services by mining bank transaction history — this app has no bank connection and never will
/// (that's a deliberate, different trade-off: local-first, no financial account access). The same
/// kind of nudge is still achievable from data already on hand: two or more ACTIVE, RECURRING
/// items sharing a category is worth a second look, even without knowing exactly what either one
/// is for. Not proof of actual waste — a "Subscriptions" category legitimately holds a streaming
/// service AND a gym membership at once — just a prompt to check.
public struct OverlapDetector: Sendable {
    public init() {}

    public struct Overlap: Equatable, Sendable {
        public let category: LifeCategory
        public let items: [LifeAdminItem]
    }

    public func possibleOverlaps(in items: [LifeAdminItem]) -> [Overlap] {
        let active = items.filter { $0.status == .active && $0.recurrence != .none }
        let grouped = Dictionary(grouping: active, by: \.category)
        return grouped
            .filter { $0.value.count >= 2 }
            .map { Overlap(category: $0.key, items: $0.value) }
            .sorted { $0.items.count > $1.items.count }
    }
}
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
public struct SpendEngine: Sendable {
    public init() {}

    /// Total amount per currency for active items due within `[from, to]` — kept as separate
    /// per-currency totals rather than one summed number, since adding a USD amount to an ILS
    /// amount would just be a wrong number dressed up as a real one.
    public func totalsByCurrency(for items: [LifeAdminItem], from: Date, to: Date) -> [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for item in items {
            guard item.status == .active, let amount = item.amount, let due = item.dueDate else { continue }
            guard due >= from, due <= to else { continue }
            let currency = item.currency ?? ""
            totals[currency, default: 0] += amount
        }
        return totals
    }
}
public struct RecurrenceEngine: Sendable {
    public init() {}

    /// `anchorDay` is the day-of-month a monthly-family recurrence should keep returning to. Pass
    /// the value carried on the item (`LifeAdminItem.recurrenceAnchorDay`, falling back to the day
    /// of `date` for a first-ever computation) — without it, chaining "+1 month" off an
    /// already-clamped date drifts permanently short. See `monthlyAdvance` below.
    public func nextDueDate(after date: Date, recurrence: Recurrence, calendar: Calendar = .current, anchorDay: Int? = nil) -> Date? {
        switch recurrence {
        case .none, .custom: return nil
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date)
        case .biweekly: return calendar.date(byAdding: .day, value: 14, to: date)
        case .monthly: return monthlyAdvance(from: date, months: 1, calendar: calendar, anchorDay: anchorDay)
        case .everyTwoMonths: return monthlyAdvance(from: date, months: 2, calendar: calendar, anchorDay: anchorDay)
        case .quarterly: return monthlyAdvance(from: date, months: 3, calendar: calendar, anchorDay: anchorDay)
        case .everySixMonths: return monthlyAdvance(from: date, months: 6, calendar: calendar, anchorDay: anchorDay)
        // Reuses the exact same month-count-and-reclamp math as the monthly-family cases (12
        // months is a year) rather than a bare `.year` addition — a birthday or anniversary
        // anchored on Feb 29 otherwise clamps to Feb 28 the first non-leap year and then, with a
        // plain year addition, *stays* Feb 28 forever, never snapping back on the next leap year
        // the way `anchorDay` already correctly handles for e.g. a Jan-31 monthly bill.
        case .yearly: return monthlyAdvance(from: date, months: 12, calendar: calendar, anchorDay: anchorDay)
        }
    }

    /// Adding months by chaining off the previous due date drifts permanently once a short month
    /// clamps it: a bill anchored on Jan 31 becomes Feb 28 (Foundation clamps out-of-range days to
    /// the month's last day), and naively computing "Feb 28 + 1 month" gives Mar 28 — not Mar 31 —
    /// because the clamped date no longer remembers the day the recurrence actually meant. Every
    /// later month then inherits that shrunken day forever. Re-deriving the day from `anchorDay`
    /// (kept on the item independently of the clamped `dueDate`) snaps back to day 31 the moment a
    /// 31-day month comes around again, instead of a due date that silently drifts earlier.
    private func monthlyAdvance(from date: Date, months: Int, calendar: Calendar, anchorDay: Int?) -> Date? {
        guard let bumped = calendar.date(byAdding: .month, value: months, to: date) else { return nil }
        guard let anchorDay else { return bumped }
        var comps = calendar.dateComponents([.year, .month, .hour, .minute, .second, .nanosecond], from: bumped)
        let daysInMonth = calendar.range(of: .day, in: .month, for: bumped)?.count ?? calendar.component(.day, from: bumped)
        comps.day = max(1, min(anchorDay, daysInMonth))
        return calendar.date(from: comps) ?? bumped
    }

    /// The whole point of marking a recurring item's dueDate/recurrence is that it keeps coming
    /// back — without this, "every month" only ever fires once: the first time it's marked done,
    /// the reminder is gone for good, exactly the opposite of what setting a recurrence promised.
    /// Returns a fresh active item for the next occurrence, or nil for a one-off item, an item
    /// with no due date, or a custom recurrence rule this can't compute without a rule parser.
    public func nextOccurrence(of item: LifeAdminItem, calendar: Calendar = .current, now: Date = Date()) -> LifeAdminItem? {
        guard let due = item.dueDate else { return nil }
        let anchorDay = item.recurrenceAnchorDay ?? calendar.component(.day, from: due)
        guard let next = nextDueDate(after: due, recurrence: item.recurrence, calendar: calendar, anchorDay: anchorDay) else { return nil }
        var nextItem = item
        nextItem.id = UUID()
        nextItem.status = .active
        nextItem.dueDate = next
        nextItem.recurrenceAnchorDay = anchorDay
        nextItem.priorityOverride = nil
        // Last month's scanned bill or receipt doesn't belong on next month's occurrence —
        // carrying it forward would show a stale document against a due date it has nothing to
        // do with.
        nextItem.attachments = []
        nextItem.createdAt = now
        nextItem.updatedAt = now
        // The completed occurrence's own amount becomes what the new one is compared against —
        // carried forward as `amount` too (the actual renewal price isn't known yet, so last
        // time's is the only reasonable starting guess) so the two only diverge once someone
        // types in what this renewal actually costs.
        nextItem.previousAmount = item.amount
        return nextItem
    }

    /// The percentage change from `previousAmount` to `amount` — positive means it went up. `nil`
    /// when there's nothing to compare (no prior amount recorded, or either side is missing or
    /// zero, where a percentage isn't a meaningful number).
    public func priceChangePercent(for item: LifeAdminItem) -> Double? {
        guard let previous = item.previousAmount, let current = item.amount, previous != 0 else { return nil }
        return Double(truncating: ((current - previous) / previous * 100) as NSDecimalNumber)
    }
}
public struct ImportExportEngine {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    public init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func exportJSON(_ items: [LifeAdminItem]) throws -> Data { try encoder.encode(items) }

    /// No real user backs up more than a few thousand life-admin items; a file claiming far more
    /// is either corrupt or was crafted to make the app decode and validate an unbounded array
    /// (a backup is picked via the system file picker, so this can only ever be self-inflicted,
    /// but it's a one-line guard against a bad file wedging the import).
    static let maxImportItemCount = 20_000

    public func importJSON(_ data: Data) throws -> [LifeAdminItem] {
        // A raw DecodingError (from an empty file, truncated JSON, or a field of the wrong type)
        // is a Foundation implementation detail, not something to surface to the user — every
        // other failure in this flow reports through LifeAdminError's friendly "Something went
        // wrong" message, so a corrupt backup should too instead of leaking a cryptic system error.
        let items: [LifeAdminItem]
        do {
            items = try decoder.decode([LifeAdminItem].self, from: data)
        } catch {
            throw LifeAdminError.invalidJSON
        }
        guard items.count <= Self.maxImportItemCount else { throw LifeAdminError.invalidJSON }
        // Two items sharing an id isn't a shape a well-formed export can ever produce — every id
        // is a fresh UUID — so it only happens with a hand-crafted or corrupted file. Importing it
        // anyway would hand the rest of the app (anything keyed by id, e.g. a SwiftUI List or an
        // upsert-by-id store) two "same" items, silently dropping one instead of failing loudly.
        guard Set(items.map(\.id)).count == items.count else { throw LifeAdminError.invalidJSON }
        try items.forEach { try ItemValidator().validate($0) }
        return items
    }

    /// A title can be user-typed, OCR'd off a scanned document, or AI-extracted — none of those
    /// are trustworthy input. Without escaping, a comma in the title would silently misalign every
    /// column after it; without the leading-character guard, a title like `=HYPERLINK(...)` opens
    /// straight into formula injection the moment the exported file is opened in Excel/Numbers/
    /// Sheets. Every field gets both treatments regardless of content, since none of these fields
    /// are ever safe to trust as-is.
    private func csvField(_ raw: String) -> String {
        var value = raw
        if let first = value.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) {
            value = "'" + value
        }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    public func exportCSV(_ items: [LifeAdminItem]) -> String {
        let header = "Title,Category,Status,Priority,DueDate,Amount,Currency,PreviousAmount"
        let rows = items.map { item in
            [
                csvField(item.title),
                csvField(item.category.rawValue),
                csvField(item.status.rawValue),
                csvField(item.priority.rawValue),
                csvField(item.dueDate?.ISO8601Format() ?? ""),
                csvField(item.amount.map(String.init(describing:)) ?? ""),
                csvField(item.currency ?? ""),
                // A renewal costing more than the cycle it replaced was otherwise invisible in an
                // exported backup entirely — the raw prior amount (not just a percentage) so
                // whatever tool opens this CSV can compute its own comparison however it likes.
                csvField(item.previousAmount.map(String.init(describing:)) ?? "")
            ].joined(separator: ",")
        }
        // Excel only renders a CSV as UTF-8 (Hebrew titles included) when it opens with a UTF-8
        // byte-order mark; without it, Excel guesses the system codepage instead and every
        // non-ASCII character — every Hebrew title, since this app is Hebrew-first — comes out as
        // mojibake the moment a user double-clicks their exported file.
        return "\u{FEFF}" + ([header] + rows).joined(separator: "\n")
    }
}
