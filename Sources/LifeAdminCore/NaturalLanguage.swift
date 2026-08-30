import Foundation
public struct ExtractedItem: Codable, Equatable, Sendable { public var title: String?; public var category: LifeCategory?; public var amount: Decimal?; public var currency: String?; public var date: Date?; public var recurring: Recurrence?; public var reminderOffsets: [Int]?; public var confidence: Double }
public struct NaturalLanguageParser: Sendable {
    public init() {}

    /// Recognizes both orderings — "March 18" and "18 March" — since day-before-month is the
    /// everyday order outside the US, and the confirmed on-device bug report that motivated the
    /// garbled-title fix elsewhere in this file used exactly that order ("On the 24 august").
    private static let hebrewMonths = ["ינואר": 1, "פברואר": 2, "מרץ": 3, "אפריל": 4, "מאי": 5, "יוני": 6, "יולי": 7, "אוגוסט": 8, "ספטמבר": 9, "אוקטובר": 10, "נובמבר": 11, "דצמבר": 12]
    private static let englishMonths = ["january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12]
    /// "starting sep 1" is at least as common as "starting september 1" in casual writing — a
    /// real test sentence used exactly this abbreviated form and was silently unrecognized before
    /// this was added. "may" needs no separate entry: its abbreviation is already its full name.
    private static let englishMonthAbbreviations = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12]
    /// Hebrew glues single-letter prepositions directly onto the following word with no space or
    /// hyphen — "in August" is "באוגוסט" (ב + אוגוסט), not two tokens — so a month name is only
    /// ever found by also trying the token with one of these leading letters stripped.
    private static let hebrewPrefixLetters: Set<Character> = ["ב", "ה", "ו", "ל", "מ", "כ", "ש"]

    static func simpleDate(in lower: String, now: Date) -> Date? {
        let parts = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        // A written-out date is far more likely to carry an ordinal suffix ("August 15th", "the
        // 1st") than not — Int("15th") fails outright, which silently dropped a clearly-stated
        // date entirely rather than just losing the suffix. Taking the leading digits handles
        // every English ordinal ("1st", "2nd", "3rd", "15th", "21st", ...) the same way it
        // already handles a bare "15".
        func dayNumber(_ token: String) -> Int? {
            let digits = token.prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }
        func monthNumber(_ token: String) -> Int? {
            if let m = englishMonths[token] { return m }
            if let m = englishMonthAbbreviations[token] { return m }
            if let m = hebrewMonths[token] { return m }
            if let first = token.first, hebrewPrefixLetters.contains(first), let m = hebrewMonths[String(token.dropFirst())] { return m }
            return nil
        }
        for (i, p) in parts.enumerated() {
            if let m = monthNumber(p), i + 1 < parts.count, let day = dayNumber(parts[i + 1]), (1...31).contains(day) {
                return Self.nextOccurrence(month: m, day: day, now: now)
            }
            if let day = dayNumber(p), (1...31).contains(day), i + 1 < parts.count, let m = monthNumber(parts[i + 1]) {
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

    /// Users type in Hebrew and English interchangeably ("תור לרופא מחר", "rent due next week"),
    /// and relative phrases are at least as common as absolute dates for near-term reminders —
    /// so this is tried before `simpleDate`, whose month-name matching can't see these at all.
    /// Always normalized to midnight, matching `simpleDate`'s "no stated time" convention; an
    /// explicit clock time in the same text is applied afterward by `timeOfDay`.
    private static let weekdayNumbers = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
    private static let hebrewWeekdayNumbers = ["ראשון": 1, "שני": 2, "שלישי": 3, "רביעי": 4, "חמישי": 5, "שישי": 6, "שבת": 7]

    /// The next date (never today itself — "next Tuesday" said on a Tuesday means the Tuesday a
    /// week out, not right now) whose weekday matches, per Calendar's own 1=Sunday...7=Saturday.
    private static func nextWeekday(_ target: Int, from now: Date, calendar: Calendar) -> Date? {
        let today = calendar.component(.weekday, from: now)
        var delta = (target - today + 7) % 7
        if delta == 0 { delta = 7 }
        return calendar.date(byAdding: .day, value: delta, to: now).map(calendar.startOfDay)
    }

    /// Spelled-out counts ("in three weeks", "בעוד שלושה שבועות") are at least as common in
    /// natural writing as digits, and understanding what was actually typed — not just the
    /// digit form — is the whole point; a real test sentence using "three" instead of "3" was
    /// silently unrecognized before this was added. Hebrew carries grammatical gender, so both
    /// forms of each number are listed.
    private static let englishNumberWords: [String: Int] = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]
    private static let hebrewNumberWords: [String: Int] = ["אחד": 1, "אחת": 1, "שניים": 2, "שתיים": 2, "שני": 2, "שתי": 2, "שלושה": 3, "שלוש": 3, "ארבעה": 4, "ארבע": 4, "חמישה": 5, "חמש": 5, "שישה": 6, "שש": 6, "שבעה": 7, "שבע": 7, "שמונה": 8, "תשעה": 9, "תשע": 9, "עשרה": 10, "עשר": 10]

    static func relativeDate(in lower: String, now: Date) -> Date? {
        let calendar = Calendar.current
        func days(_ n: Int) -> Date? { calendar.date(byAdding: .day, value: n, to: now).map(calendar.startOfDay) }
        func weeks(_ n: Int) -> Date? { calendar.date(byAdding: .weekOfYear, value: n, to: now).map(calendar.startOfDay) }
        func months(_ n: Int) -> Date? { calendar.date(byAdding: .month, value: n, to: now).map(calendar.startOfDay) }
        func years(_ n: Int) -> Date? { calendar.date(byAdding: .year, value: n, to: now).map(calendar.startOfDay) }

        if lower.contains("day after tomorrow") || lower.contains("מחרתיים") { return days(2) }
        if lower.contains("tomorrow") || lower.contains("מחר") { return days(1) }
        if lower.contains("today") || lower.contains("היום") { return days(0) }
        // Hebrew's dual grammatical form for exactly two ("יומיים"/"שבועיים"/"חודשיים"/"שנתיים")
        // is a single word, not "two days/weeks/months/years" as separate tokens, so it can't be
        // caught by the number-word scan below at all — it needs its own direct check. But "כל
        // שבועיים"/"כל חודשיים" ("every two weeks"/"every two months") is a recurrence with no
        // specific date at all, not a one-time date two weeks/months from now — recognized
        // separately as biweekly/everyTwoMonths recurrence in parse() — so it must be excluded
        // here or a recurring item would wrongly also get a fabricated due date.
        if lower.contains("יומיים") && !lower.contains("כל יומיים") { return days(2) }
        if lower.contains("שבועיים") && !lower.contains("כל שבועיים") { return weeks(2) }
        if lower.contains("חודשיים") && !lower.contains("כל חודשיים") { return months(2) }
        if lower.contains("שנתיים") && !lower.contains("כל שנתיים") { return years(2) }
        if lower.contains("next week") || lower.contains("in a week") || lower.contains("בעוד שבוע") || lower.contains("בשבוע הבא") { return weeks(1) }
        if lower.contains("next month") || lower.contains("in a month") || lower.contains("בעוד חודש") || lower.contains("בחודש הבא") { return months(1) }
        if lower.contains("next year") || lower.contains("in a year") || lower.contains("בעוד שנה") || lower.contains("בשנה הבאה") { return years(1) }

        // "next Tuesday" / Hebrew "יום שלישי הבא" — a weekday name is only a relative-date signal
        // paired with an explicit "next"/"הבא", since a bare day name usually just names which day
        // of the week something already-dated falls on, not a date on its own.
        for (name, number) in weekdayNumbers where lower.contains("next \(name)") {
            return nextWeekday(number, from: now, calendar: calendar)
        }
        for (name, number) in hebrewWeekdayNumbers where lower.contains("יום \(name) הבא") || lower.contains("ביום \(name) הבא") {
            return nextWeekday(number, from: now, calendar: calendar)
        }
        // "next December" / "בדצמבר הקרוב" — a bare month name is only a relative-date signal
        // paired with "next"/"הקרוב"; with no day stated, the 1st of that month is the only
        // reasonable convention (matches simpleDate's own next-occurrence rule for month+day).
        for (name, number) in englishMonths where lower.contains("next \(name)") {
            return Self.nextOccurrence(month: number, day: 1, now: now)
        }
        for (name, number) in hebrewMonths where lower.contains("ב\(name) הקרוב") || lower.contains("ל\(name) הקרוב") {
            return Self.nextOccurrence(month: number, day: 1, now: now)
        }

        func numberToken(_ s: String) -> Int? {
            if let n = Int(s) { return n }
            if let n = englishNumberWords[s.lowercased()] { return n }
            if let n = hebrewNumberWords[s] { return n }
            return nil
        }
        let numberAlternation = (["\\d+"] + englishNumberWords.keys + hebrewNumberWords.keys).joined(separator: "|")
        let numberedPatterns: [(String, (Int) -> Date?)] = [
            ("in\\s+(\(numberAlternation))\\s+days?", days),
            ("in\\s+(\(numberAlternation))\\s+weeks?", weeks),
            ("in\\s+(\(numberAlternation))\\s+months?", months),
            ("in\\s+(\(numberAlternation))\\s+years?", years),
            ("בעוד\\s+(\(numberAlternation))\\s+ימים?", days),
            ("בעוד\\s+(\(numberAlternation))\\s+שבועות", weeks),
            ("בעוד\\s+(\(numberAlternation))\\s+חודשים?", months),
            ("בעוד\\s+(\(numberAlternation))\\s+שנים?", years)
        ]
        for (pattern, apply) in numberedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(lower.startIndex..., in: lower)
            if let match = regex.firstMatch(in: lower, range: range),
               let numberRange = Range(match.range(at: 1), in: lower),
               let value = numberToken(String(lower[numberRange])) {
                return apply(value)
            }
        }
        return nil
    }

    /// "Driving test 4 september 11:00 am" saved a due date of midnight — simpleDate only ever
    /// looks for month/day/year, never a clock time, so an explicitly stated time was silently
    /// thrown away and replaced with one that's likely wrong. Only matches a clear am/pm time
    /// ("11:00 am", "3pm") — a bare 24-hour "14:30" is ambiguous with other colon-separated
    /// numbers in casual text, so it's deliberately left alone rather than guessed at.
    static func timeOfDay(in lower: String) -> (hour: Int, minute: Int)? {
        let pattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: range),
              let hourRange = Range(match.range(at: 1), in: lower),
              var hour = Int(lower[hourRange]) else { return nil }
        var minute = 0
        if let minuteRange = Range(match.range(at: 2), in: lower), let m = Int(lower[minuteRange]) { minute = m }
        if let periodRange = Range(match.range(at: 3), in: lower) {
            let period = lower[periodRange].lowercased()
            if period == "pm" && hour != 12 { hour += 12 }
            if period == "am" && hour == 12 { hour = 0 }
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
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
        KeywordMatch(keywords: ["doctor"], title: "Doctor Appointment", category: .appointments),
        KeywordMatch(keywords: ["driving test"], title: "Driving Test", category: .appointments),
        // car/money/health/work/education/documents/family were real LifeCategory cases the
        // parser could never actually reach — every sentence naming one of them (a car service,
        // a loan, a prescription, a paycheck, tuition, an ID renewal, a birthday) silently landed
        // in .other instead. Kept deliberately narrow to safe, unambiguous keywords rather than
        // broad single words like "home"/"shopping" that would false-positive too easily (e.g. a
        // bare "home" also appears in "home from work").
        KeywordMatch(keywords: ["car service"], title: "Car Service", category: .car),
        KeywordMatch(keywords: ["car wash"], title: "Car Wash", category: .car),
        KeywordMatch(keywords: ["car registration"], title: "Car Registration", category: .car),
        KeywordMatch(keywords: ["car maintenance"], title: "Car Maintenance", category: .car),
        KeywordMatch(keywords: ["credit card"], title: "Credit Card", category: .money),
        KeywordMatch(keywords: ["savings"], title: "Savings", category: .money),
        KeywordMatch(keywords: ["loan"], title: "Loan", category: .money),
        KeywordMatch(keywords: ["prescription"], title: "Prescription", category: .health),
        KeywordMatch(keywords: ["medication"], title: "Medication", category: .health),
        KeywordMatch(keywords: ["vitamins"], title: "Vitamins", category: .health),
        KeywordMatch(keywords: ["salary", "paycheck", "payroll"], title: "Salary", category: .work),
        KeywordMatch(keywords: ["tuition", "school fee"], title: "Tuition", category: .education),
        KeywordMatch(keywords: ["driver's license", "drivers license", "id card", "birth certificate"], title: "Document Renewal", category: .documents),
        KeywordMatch(keywords: ["birthday"], title: "Birthday", category: .family),
        KeywordMatch(keywords: ["anniversary"], title: "Anniversary", category: .family),
        // Hebrew mirror of the English list above. Kept as a separate block (rather than adding
        // a second keyword language to each existing entry) so the title stays in whichever
        // language the user actually typed in, instead of a Hebrew sentence silently producing
        // an English item title. Same specific-before-generic ordering within the block as above
        // (e.g. "ביטוח רכב" before the bare "ביטוח") for the same reason.
        KeywordMatch(keywords: ["ביטוח רכב"], title: "ביטוח רכב", category: .insurance),
        KeywordMatch(keywords: ["ביטוח דירה", "ביטוח בית"], title: "ביטוח דירה", category: .insurance),
        KeywordMatch(keywords: ["ביטוח בריאות"], title: "ביטוח בריאות", category: .insurance),
        KeywordMatch(keywords: ["ביטוח חיים"], title: "ביטוח חיים", category: .insurance),
        KeywordMatch(keywords: ["ביטוח"], title: "ביטוח", category: .insurance),
        KeywordMatch(keywords: ["דרכון"], title: "דרכון", category: .travel),
        KeywordMatch(keywords: ["ויזה"], title: "ויזה", category: .travel),
        KeywordMatch(keywords: ["נטפליקס"], title: "נטפליקס", category: .subscriptions),
        KeywordMatch(keywords: ["ספוטיפיי", "ספוטיפי"], title: "ספוטיפיי", category: .subscriptions),
        KeywordMatch(keywords: ["אחריות"], title: "אחריות", category: .warranties),
        KeywordMatch(keywords: ["חדר כושר", "מנוי כושר"], title: "מנוי חדר כושר", category: .memberships),
        KeywordMatch(keywords: ["שכר דירה", "שכירות"], title: "שכר דירה", category: .bills),
        KeywordMatch(keywords: ["משכנתא"], title: "משכנתא", category: .bills),
        KeywordMatch(keywords: ["חשבון חשמל"], title: "חשבון חשמל", category: .bills),
        KeywordMatch(keywords: ["חשבון מים"], title: "חשבון מים", category: .bills),
        KeywordMatch(keywords: ["חשבון טלפון"], title: "חשבון טלפון", category: .bills),
        KeywordMatch(keywords: ["רופא שיניים"], title: "תור לרופא שיניים", category: .appointments),
        KeywordMatch(keywords: ["רופא"], title: "תור לרופא", category: .appointments),
        KeywordMatch(keywords: ["טסט רכב", "מבחן נהיגה"], title: "טסט רכב", category: .appointments),
        KeywordMatch(keywords: ["טיפול לרכב"], title: "טיפול לרכב", category: .car),
        KeywordMatch(keywords: ["שטיפת רכב"], title: "שטיפת רכב", category: .car),
        KeywordMatch(keywords: ["רישוי רכב"], title: "רישוי רכב", category: .car),
        KeywordMatch(keywords: ["כרטיס אשראי"], title: "כרטיס אשראי", category: .money),
        KeywordMatch(keywords: ["חיסכון"], title: "חיסכון", category: .money),
        KeywordMatch(keywords: ["הלוואה"], title: "הלוואה", category: .money),
        KeywordMatch(keywords: ["מרשם"], title: "מרשם", category: .health),
        KeywordMatch(keywords: ["תרופה"], title: "תרופה", category: .health),
        KeywordMatch(keywords: ["משכורת"], title: "משכורת", category: .work),
        KeywordMatch(keywords: ["שכר לימוד", "אגרת לימוד"], title: "שכר לימוד", category: .education),
        KeywordMatch(keywords: ["רישיון נהיגה", "תעודת זהות", "תעודת לידה"], title: "חידוש מסמך", category: .documents),
        KeywordMatch(keywords: ["יום הולדת"], title: "יום הולדת", category: .family),
        KeywordMatch(keywords: ["יום נישואין"], title: "יום נישואין", category: .family)
    ]

    /// A bare-word keyword like "רופא" almost never appears bare in real Hebrew — "to the doctor"
    /// glues the preposition straight onto it ("לרופא"), same as the month-name prefixes in
    /// simpleDate. Widening the lookup set with each word's prefix-stripped form (once) is what
    /// makes single-word Hebrew keywords actually match ordinary phrasing instead of only the
    /// unnaturally bare form.
    private static func destemmed(_ words: Set<String>) -> Set<String> {
        words.reduce(into: words) { result, word in
            if let first = word.first, hebrewPrefixLetters.contains(first) {
                result.insert(String(word.dropFirst()))
            }
        }
    }

    /// Hebrew inserts its definite article directly onto the second word of a two-word phrase
    /// when the phrase is definite — "פרעתי את כרטיס האשראי" ("I paid off the credit card") says
    /// "כרטיס האשראי", not the bare "כרטיס אשראי" a keyword phrase is written as — so a plain
    /// substring check alone misses an entire, completely ordinary way of phrasing it. Trying the
    /// same phrase with "ה" inserted right after its first space catches that form too, for every
    /// two-word keyword in the list at once instead of special-casing each one.
    private static func withDefiniteArticle(_ keyword: String) -> String? {
        guard let spaceIndex = keyword.firstIndex(of: " ") else { return nil }
        let afterSpace = keyword.index(after: spaceIndex)
        return keyword[..<spaceIndex] + " ה" + keyword[afterSpace...]
    }

    private static func firstMatch(in lower: String, words: Set<String>) -> KeywordMatch? {
        let expandedWords = destemmed(words)
        return knownMatches.first { match in
            match.keywords.contains { keyword in
                guard keyword.contains(" ") else { return expandedWords.contains(keyword) }
                if lower.contains(keyword) { return true }
                if let withArticle = withDefiniteArticle(keyword), lower.contains(withArticle) { return true }
                return false
            }
        }
    }

    private static let currencyMarks: Set<Character> = ["$", "€", "₪"]
    private static let currencyWords: Set<String> = ["שקל", "שקלים", "ש\"ח", "ש״ח", "nis", "ils", "usd", "eur", "shekel", "shekels"]
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
            // A clock time like "11:00" strips down to "1100" if the colon is treated as noise —
            // that's not a smaller version of the same number, it's a completely different one,
            // so a token that ever had a colon is never a valid amount candidate at all.
            guard token.contains(":") == false else { return nil }
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
        // "meeting at 9am" isn't a $9 charge — a clock hour glued to am/pm (or standing right
        // next to it as its own token) is a time, not an amount. Found on a real test sentence
        // that had no currency in it at all, so nothing else here was catching it.
        let timeTokenPattern = try! NSRegularExpression(pattern: #"^\d{1,2}\s*(am|pm)$"#, options: .caseInsensitive)
        let timeMarkers: Set<String> = ["am", "pm"]
        // "expires in 2 years" isn't a 2-dollar bill — a bare number immediately followed by a
        // span-of-time word is a duration, not an amount, the same reasoning that already
        // excludes an ordinal day-of-month here.
        let durationWords: Set<String> = ["day", "days", "week", "weeks", "month", "months", "year", "years", "יום", "ימים", "שבוע", "שבועות", "חודש", "חודשים", "שנה", "שנים"]
        for (index, token) in tokens.enumerated() {
            let range = NSRange(token.startIndex..., in: token)
            if ordinalDatePattern.firstMatch(in: token, range: range) != nil { continue }
            if timeTokenPattern.firstMatch(in: token, range: range) != nil { continue }
            if let dayOfMonth, Int(token) == dayOfMonth { continue }
            if index + 1 < tokens.count, durationWords.contains(tokens[index + 1].lowercased()) { continue }
            if index + 1 < tokens.count, timeMarkers.contains(tokens[index + 1].lowercased()) { continue }
            if let value = decimalValue(token) { return value }
        }
        return nil
    }

    /// Splits a multi-line paste into one entry per line — "Rent $1200\nGym $40\nNetflix $17" is
    /// three items, not one. Without this, pasting a list of bills silently kept only whatever a
    /// single `parse()` call happened to find in the whole blob and dropped the rest. A single
    /// line (by far the common case) always comes back as a one-element array, so nothing about
    /// existing single-item behavior changes.
    public static func splitEntries(_ text: String) -> [String] {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
        return lines.isEmpty ? [text] : lines
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
        // A fallback title should never end up literally showing the amount ("credit card
        // payment $85"): stopping at the first token that carries a digit keeps the amount out of
        // the title text while still using up to 4 words, same as before, whenever the first
        // words happen to be digit-free (the overwhelmingly common case).
        let leadingWords = text.split(separator: " ").map(String.init)
        let wordsBeforeFirstDigit = leadingWords.prefix { $0.contains { $0.isNumber } == false }
        let fallbackWords = wordsBeforeFirstDigit.isEmpty ? leadingWords : Array(wordsBeforeFirstDigit)
        let fallbackTitle = fallbackWords.prefix(4).joined(separator: " ")
        let title = recognizedTitle ?? fallbackTitle
        // ₪/שקל/ש"ח matter here specifically because the app's own Hebrew UI and example prompts
        // use them — without this, typing exactly what the app itself suggested ("ביטוח רכב
        // מתחדש ב-15 באוגוסט, 840 ש״ח") would silently fail to detect any currency at all.
        // Symbols are checked as substrings (still fine even glued onto a prefix, e.g. "בשקלים"
        // contains "שקל"); spelled-out currency words ("nis", "shekels", "usd") are only ever
        // whole tokens, so those need the word set, not another `.contains` on the raw string.
        let currency = lower.contains("€") || words.contains("eur") || lower.contains("יורו") ? "EUR"
            : lower.contains("$") || words.contains("usd") || words.contains("dollar") || words.contains("dollars") || lower.contains("דולר") ? "USD"
            : lower.contains("₪") || lower.contains("שקל") || lower.contains("ש\"ח") || lower.contains("ש״ח") || words.contains("שח") || words.contains("nis") || words.contains("ils") || words.contains("shekel") || words.contains("shekels") ? "ILS"
            : nil
        // Checked most-specific-period-first: "renews every month" contains "renews every" as a
        // plain substring, so when that generic catch-all was checked before the monthly check,
        // it silently misclassified a monthly subscription as yearly. "renews every" (with no
        // period of its own) is only meant as a fallback for text that names no period at all —
        // it must never win against an actual "month"/"six months" match sitting right next to it.
        // "$45/month" and "לחודש" ("per month") are just as common a way to state a recurring
        // price as "monthly" spelled out, so they get the same weight here.
        // "יומיים"/"שבועיים"/"חודשיים"/"שנתיים" are Hebrew's dual form for exactly two
        // days/weeks/months/years — a single word, not "day/week/month/year" plus a count — and
        // each one contains "יומי"/"שבועי"/"חודשי"/"שנתי" as a plain substring, which falsely
        // fired the daily/weekly/monthly/yearly checks below on a one-time "expires in two months"
        // sentence that has no recurrence in it at all. Stripping the dual words out before
        // matching removes the false substring without touching any of the real
        // "יומי"/"שבועי"/"חודשי"/"שנתי"/"כל חודש"/"כל שנה" phrasing this block is meant to catch.
        // The explicit "every two X" / "כל Xיים" phrases (biweekly, everyTwoMonths) are matched
        // separately against the un-stripped text before falling through to this generic pass, so
        // stripping the dual word here never loses that case — it only stops it from being
        // mis-read as a plain weekly/monthly signal.
        let lowerForRecurrence = lower
            .replacingOccurrences(of: "יומיים", with: "")
            .replacingOccurrences(of: "שבועיים", with: "")
            .replacingOccurrences(of: "חודשיים", with: "")
            .replacingOccurrences(of: "שנתיים", with: "")
        let recurrence: Recurrence
        // " a month"/" a year" (no leading "in") is as common a way to state a recurring price as
        // "monthly" spelled out ("45 dollars a month") — but "in a month"/"in a year" is the
        // one-time relative-date phrase already handled above, and always contains " a month"/" a
        // year" as a substring, so it must be excluded here to avoid double-tagging a one-time
        // date as also recurring.
        if lowerForRecurrence.contains("daily") || lowerForRecurrence.contains("every day") || lowerForRecurrence.contains("כל יום") || lowerForRecurrence.contains("יומי") {
            recurrence = .daily
        } else if lower.contains("biweekly") || lower.contains("every two weeks") || lower.contains("every other week") || lower.contains("כל שבועיים") {
            recurrence = .biweekly
        } else if lower.contains("every two months") || lower.contains("every other month") || lower.contains("כל חודשיים") {
            recurrence = .everyTwoMonths
        } else if lowerForRecurrence.contains("quarterly") || lowerForRecurrence.contains("every quarter") || lowerForRecurrence.contains("every 3 months") || lowerForRecurrence.contains("every three months") || lowerForRecurrence.contains("רבעוני") || lowerForRecurrence.contains("כל רבעון") || lowerForRecurrence.contains("כל 3 חודשים") || lowerForRecurrence.contains("כל שלושה חודשים") {
            recurrence = .quarterly
        } else if lowerForRecurrence.contains("weekly") || lowerForRecurrence.contains("every week") || lowerForRecurrence.contains("שבועי") || lowerForRecurrence.contains("כל שבוע") || lowerForRecurrence.contains("לשבוע") {
            recurrence = .weekly
        } else if lowerForRecurrence.contains("every month") || lowerForRecurrence.contains("monthly") || lowerForRecurrence.contains("/month") || lowerForRecurrence.contains("per month") || lowerForRecurrence.contains("כל חודש") || lowerForRecurrence.contains("מדי חודש") || lowerForRecurrence.contains("חודשי") || lowerForRecurrence.contains("לחודש") || (lowerForRecurrence.contains(" a month") && !lowerForRecurrence.contains("in a month")) {
            recurrence = .monthly
        } else if lowerForRecurrence.contains("six months") || (lowerForRecurrence.contains("6 months") && !lowerForRecurrence.contains("in 6 months")) || lowerForRecurrence.contains("כל שישה חודשים") || lowerForRecurrence.contains("כל 6 חודשים") || lowerForRecurrence.contains("חצי שנה") {
            recurrence = .everySixMonths
        } else if lowerForRecurrence.contains("every year") || lowerForRecurrence.contains("yearly") || lowerForRecurrence.contains("annual") || lowerForRecurrence.contains("renews every") || lowerForRecurrence.contains("/year") || lowerForRecurrence.contains("per year") || lowerForRecurrence.contains("כל שנה") || lowerForRecurrence.contains("מדי שנה") || lowerForRecurrence.contains("שנתי") || lowerForRecurrence.contains("לשנה") || (lowerForRecurrence.contains(" a year") && !lowerForRecurrence.contains("in a year")) {
            recurrence = .yearly
        } else {
            recurrence = .none
        }
        var date = Self.relativeDate(in: lower, now: now) ?? Self.simpleDate(in: lower, now: now)
        if let recognizedDate = date, let time = Self.timeOfDay(in: lower) {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: recognizedDate)
            components.hour = time.hour
            components.minute = time.minute
            date = Calendar.current.date(from: components) ?? recognizedDate
        }
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
