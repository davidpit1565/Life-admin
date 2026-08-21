import Foundation
public struct ExtractedItem: Codable, Equatable, Sendable { public var title: String?; public var category: LifeCategory?; public var amount: Decimal?; public var currency: String?; public var date: Date?; public var recurring: Recurrence?; public var reminderOffsets: [Int]?; public var confidence: Double }
public struct NaturalLanguageParser: Sendable {
    public init() {}

    /// Recognizes both orderings — "March 18" and "18 March" — since day-before-month is the
    /// everyday order outside the US, and the confirmed on-device bug report that motivated the
    /// garbled-title fix elsewhere in this file used exactly that order ("On the 24 august").
    static func simpleDate(in lower: String, now: Date) -> Date? {
        let months = ["january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12]
        let parts = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for (i, p) in parts.enumerated() {
            if let m = months[p], i + 1 < parts.count, let day = Int(parts[i + 1]), (1...31).contains(day) {
                return Self.nextOccurrence(month: m, day: day, now: now)
            }
            if let day = Int(p), (1...31).contains(day), i + 1 < parts.count, let m = months[parts[i + 1]] {
                return Self.nextOccurrence(month: m, day: day, now: now)
            }
            if let y = Int(p), y > 1900, y < 2200 {
                return Calendar.current.date(from: DateComponents(year: y, month: 12, day: 31))
            }
        }
        return nil
    }

    private static func nextOccurrence(month: Int, day: Int, now: Date) -> Date? {
        var components = Calendar.current.dateComponents([.year], from: now)
        components.month = month
        components.day = day
        let candidate = Calendar.current.date(from: components)
        if let candidate, candidate < now {
            components.year = (components.year ?? 2026) + 1
            return Calendar.current.date(from: components)
        }
        return candidate
    }

    /// A single-word keyword is matched against whole words only ("rent" must not match inside
    /// "parent"); a multi-word phrase is matched as a substring, since it's specific enough on its
    /// own not to need that guard.
    private struct KeywordMatch { let keywords: [String]; let title: String; let category: LifeCategory }

    private static let knownMatches: [KeywordMatch] = [
        KeywordMatch(keywords: ["car insurance"], title: "Car Insurance", category: .insurance),
        KeywordMatch(keywords: ["home insurance"], title: "Home Insurance", category: .insurance),
        KeywordMatch(keywords: ["health insurance"], title: "Health Insurance", category: .insurance),
        KeywordMatch(keywords: ["life insurance"], title: "Life Insurance", category: .insurance),
        KeywordMatch(keywords: ["insurance"], title: "Insurance", category: .insurance),
        KeywordMatch(keywords: ["passport"], title: "Passport", category: .travel),
        KeywordMatch(keywords: ["visa renewal", "visa"], title: "Visa", category: .travel),
        KeywordMatch(keywords: ["netflix"], title: "Netflix", category: .subscriptions),
        KeywordMatch(keywords: ["spotify"], title: "Spotify", category: .subscriptions),
        KeywordMatch(keywords: ["warranty"], title: "Warranty", category: .warranties),
        KeywordMatch(keywords: ["gym"], title: "Gym Membership", category: .memberships),
        KeywordMatch(keywords: ["rent"], title: "Rent", category: .bills),
        KeywordMatch(keywords: ["mortgage"], title: "Mortgage", category: .bills),
        KeywordMatch(keywords: ["electricity bill", "electric bill"], title: "Electricity Bill", category: .bills),
        KeywordMatch(keywords: ["water bill"], title: "Water Bill", category: .bills),
        KeywordMatch(keywords: ["phone bill"], title: "Phone Bill", category: .bills),
        KeywordMatch(keywords: ["dentist"], title: "Dentist Appointment", category: .appointments),
        KeywordMatch(keywords: ["doctor"], title: "Doctor Appointment", category: .appointments)
    ]

    private static func firstMatch(in lower: String, words: Set<String>) -> KeywordMatch? {
        knownMatches.first { match in
            match.keywords.contains { keyword in
                keyword.contains(" ") ? lower.contains(keyword) : words.contains(keyword)
            }
        }
    }

    private static let currencyMarks: Set<Character> = ["$", "€", "₪"]
    private static let currencyWords: Set<String> = ["שקל", "שקלים", "ש\"ח", "ש״ח", "nis", "ils", "usd", "eur"]
    private static func mentionsCurrency(_ token: String) -> Bool {
        token.contains { currencyMarks.contains($0) } || currencyWords.contains(token.lowercased())
    }

    /// A bare first-numeric-token scan finds "15" in "August 15th, $240" before it ever reaches
    /// the actual amount — a real bug hit on the very first on-device test, confirmed by the app
    /// literally saving $15 for a $240 bill. Prefers a number that's touching or next to a
    /// currency mark; only falls back to the old any-number scan when nothing mentions currency
    /// at all, and even then skips an obvious day-of-month ordinal ("15th") or the exact day
    /// number `simpleDate` already recognized elsewhere in the same text ("24" in "on the 24
    /// august", which the earlier date parser already consumed as the day-of-month).
    static func extractAmount(from text: String, dayOfMonth: Int? = nil) -> Decimal? {
        let tokens = text.replacingOccurrences(of: ",", with: "").split(separator: " ").map(String.init)
        func decimalValue(_ token: String) -> Decimal? {
            let digits = token.filter { "0123456789.".contains($0) }
            return digits.isEmpty ? nil : Decimal(string: digits)
        }
        for (index, token) in tokens.enumerated() {
            guard let value = decimalValue(token) else { continue }
            if mentionsCurrency(token) { return value }
            // Only a bare currency mark (no digits of its own, like "₪" or "שקל" sitting next to
            // "840") lends its currency-ness to a neighboring number — a neighbor that has digits
            // of its own (like "$240" next to "15th") is a separate, self-contained amount, not
            // one split across two tokens.
            let prevIsBareMark = index > 0 && mentionsCurrency(tokens[index - 1]) && decimalValue(tokens[index - 1]) == nil
            let nextIsBareMark = index + 1 < tokens.count && mentionsCurrency(tokens[index + 1]) && decimalValue(tokens[index + 1]) == nil
            if prevIsBareMark || nextIsBareMark {
                return value
            }
        }
        let ordinalDatePattern = try! NSRegularExpression(pattern: #"^\d{1,2}(st|nd|rd|th)$"#, options: .caseInsensitive)
        for token in tokens {
            let range = NSRange(token.startIndex..., in: token)
            if ordinalDatePattern.firstMatch(in: token, range: range) != nil { continue }
            if let dayOfMonth, Int(token) == dayOfMonth { continue }
            if let value = decimalValue(token) { return value }
        }
        return nil
    }

    public func parse(_ text: String, now: Date = Date()) -> ExtractedItem {
        let lower = text.lowercased()
        let words = Set(lower.split { $0.isLetter == false }.map(String.init))
        let match = Self.firstMatch(in: lower, words: words)
        let category = match?.category ?? .other
        // A recognized title comes from an actual keyword match. Anything else falls back to the
        // first few words of the input, which is rarely a meaningful title (e.g. "On the 24 august"
        // for "On the 24 august I pay my rent") — that fallback must not be reported as confident,
        // or LifeAdminAIService.isCompleteEnough will treat it as good enough and never ask Gemini
        // for a real title.
        let recognizedTitle: String? = match?.title
        let fallbackTitle = text.split(separator: " ").prefix(4).joined(separator: " ")
        let title = recognizedTitle ?? fallbackTitle
        // ₪/שקל/ש"ח matter here specifically because the app's own Hebrew UI and example prompts
        // use them — without this, typing exactly what the app itself suggested ("ביטוח רכב
        // מתחדש ב-15 באוגוסט, 840 ש״ח") would silently fail to detect any currency at all.
        let currency = lower.contains("€") ? "EUR"
            : lower.contains("$") ? "USD"
            : lower.contains("₪") || lower.contains("שקל") || lower.contains("ש\"ח") || lower.contains("ש״ח") ? "ILS"
            : nil
        let recurrence: Recurrence = lower.contains("every year") || lower.contains("yearly") || lower.contains("annual") || lower.contains("renews every") ? .yearly : lower.contains("every month") || lower.contains("monthly") ? .monthly : lower.contains("six months") ? .everySixMonths : .none
        let date = Self.simpleDate(in: lower, now: now)
        let amount = Self.extractAmount(from: text, dayOfMonth: date.map { Calendar.current.component(.day, from: $0) })
        let baseConfidence = date == nil ? 0.55 : 0.86
        let confidence = recognizedTitle == nil ? min(baseConfidence, 0.65) : baseConfidence
        return ExtractedItem(
            title: title.isEmpty ? nil : title,
            category: category,
            amount: amount,
            currency: currency,
            date: date,
            recurring: recurrence,
            reminderOffsets: category == .travel ? [90, 30, 7, 1] : [30],
            confidence: confidence
        )
    }
}
public struct AIJSONValidator { public init() {} ; public func decode(_ data: Data) throws -> ExtractedItem { let dec=JSONDecoder(); dec.dateDecodingStrategy = .iso8601; let item = try dec.decode(ExtractedItem.self, from: data); if item.confidence < 0 || item.confidence > 1 { throw LifeAdminError.invalidJSON }; return item } }
public enum AIProcessingMode: String, Codable, CaseIterable { case askEveryTime, allowAutomatically, disabled }
public protocol AIExtracting: Sendable { func extract(from text: String) async throws -> ExtractedItem }
public typealias GeminiExtractionClient = ProxyAIClient
