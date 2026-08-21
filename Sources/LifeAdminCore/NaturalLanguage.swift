import Foundation
public struct ExtractedItem: Codable, Equatable, Sendable { public var title: String?; public var category: LifeCategory?; public var amount: Decimal?; public var currency: String?; public var date: Date?; public var recurring: Recurrence?; public var reminderOffsets: [Int]?; public var confidence: Double }
public struct NaturalLanguageParser: Sendable {
    public init() {}

    static func simpleDate(in lower: String, now: Date) -> Date? {
        let months = ["january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12]
        let parts = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for (i, p) in parts.enumerated() {
            if let m = months[p], i + 1 < parts.count, let day = Int(parts[i + 1]) {
                var c = Calendar.current.dateComponents([.year], from: now)
                c.month = m
                c.day = day
                let candidate = Calendar.current.date(from: c)
                if let d = candidate, d < now {
                    c.year = (c.year ?? 2026) + 1
                    return Calendar.current.date(from: c)
                }
                return candidate
            }
            if let y = Int(p), y > 1900, y < 2200 {
                return Calendar.current.date(from: DateComponents(year: y, month: 12, day: 31))
            }
        }
        return nil
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
        let currency = lower.contains("€") ? "EUR" : lower.contains("$") ? "USD" : nil
        let amount = text.replacingOccurrences(of: ",", with: "").split(separator: " ").compactMap { Decimal(string: $0.filter { "0123456789.".contains($0) }) }.first
        let recurrence: Recurrence = lower.contains("every year") || lower.contains("yearly") || lower.contains("annual") || lower.contains("renews every") ? .yearly : lower.contains("every month") || lower.contains("monthly") ? .monthly : lower.contains("six months") ? .everySixMonths : .none
        let date = Self.simpleDate(in: lower, now: now)
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
