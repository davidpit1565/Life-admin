import XCTest
@testable import LifeAdminCore
final class LifeAdminCoreTests: XCTestCase {
 func testItemCreationValidation() throws { try ItemValidator().validate(LifeAdminItem(title:"Passport", currency:"EUR")) }
 func testInvalidCurrency() { XCTAssertThrowsError(try ItemValidator().validate(LifeAdminItem(title:"X", currency:"EURO"))) }
 func testPriority() { let due=Date().addingTimeInterval(3600); let i=LifeAdminItem(title:"Passport", category:.documents, dueDate:due, amount:10, currency:"USD", recurrence:.yearly); XCTAssertEqual(PriorityEngine().priority(for:i), .critical) }
 func testReminderCalculation() { let due=Date(timeIntervalSince1970: 86400*100); let i=LifeAdminItem(title:"P", dueDate:due, reminderOffsets:[90,30,7,1]); XCTAssertEqual(ReminderEngine().notificationDates(for:i, now: Date(timeIntervalSince1970: 0)).count, 4) }
 func testSpendTotalsGroupByCurrency() {
     let from = Date(timeIntervalSince1970: 1_700_000_000)
     let to = from.addingTimeInterval(86400 * 30)
     let usd = LifeAdminItem(title: "Rent", dueDate: from.addingTimeInterval(86400), amount: 1200, currency: "USD")
     let ils = LifeAdminItem(title: "Insurance", dueDate: from.addingTimeInterval(86400 * 2), amount: 300, currency: "ILS")
     let totals = SpendEngine().totalsByCurrency(for: [usd, ils], from: from, to: to)
     XCTAssertEqual(totals["USD"], 1200)
     XCTAssertEqual(totals["ILS"], 300)
 }
 func testSpendTotalsSumsSameCurrency() {
     let from = Date(timeIntervalSince1970: 1_700_000_000)
     let to = from.addingTimeInterval(86400 * 30)
     let a = LifeAdminItem(title: "Rent", dueDate: from.addingTimeInterval(86400), amount: 1200, currency: "USD")
     let b = LifeAdminItem(title: "Gym", dueDate: from.addingTimeInterval(86400 * 3), amount: 40, currency: "USD")
     let totals = SpendEngine().totalsByCurrency(for: [a, b], from: from, to: to)
     XCTAssertEqual(totals["USD"], 1240)
 }
 func testSpendTotalsExcludeItemsOutsideRangeOrCompletedOrWithoutAmount() {
     let from = Date(timeIntervalSince1970: 1_700_000_000)
     let to = from.addingTimeInterval(86400 * 30)
     var completed = LifeAdminItem(title: "Paid", dueDate: from.addingTimeInterval(86400), amount: 50, currency: "USD")
     completed.status = .completed
     let tooLate = LifeAdminItem(title: "Later", dueDate: from.addingTimeInterval(86400 * 60), amount: 50, currency: "USD")
     let noAmount = LifeAdminItem(title: "No amount", dueDate: from.addingTimeInterval(86400), currency: "USD")
     let totals = SpendEngine().totalsByCurrency(for: [completed, tooLate, noAmount], from: from, to: to)
     XCTAssertTrue(totals.isEmpty)
 }
 func testReminderOffsetsThatHaveAlreadyElapsedAreNotScheduled() {
     // A travel item's default offsets are [90, 30, 7, 1] days — due in only 10 days, the 90-
     // and 30-day-before offsets already landed in the past. A past-dated local notification
     // trigger fires immediately, so without filtering against `now`, saving this item would
     // instantly fire two bogus "reminders" for offsets that already elapsed.
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let due = now.addingTimeInterval(86400 * 10)
     let i = LifeAdminItem(title: "Passport renewal", category: .travel, dueDate: due, reminderOffsets: [90, 30, 7, 1])
     let dates = ReminderEngine().notificationDates(for: i, now: now)
     XCTAssertEqual(dates.count, 2)
     XCTAssertTrue(dates.allSatisfy { $0 > now })
 }
 func testSearch() { let i=LifeAdminItem(title:"Car Insurance", category:.insurance, amount:840, currency:"EUR"); var f=SearchFilter(); f.query="840"; XCTAssertEqual(SearchEngine().search([i], filter:f).count, 1) }
 func testFiltering() { let i=LifeAdminItem(title:"Netflix", category:.subscriptions, amount:17, currency:"USD"); var f=SearchFilter(); f.categories=[.subscriptions]; f.hasPayment=true; XCTAssertEqual(SearchEngine().search([i], filter:f).count, 1) }
 func testFilteringByDueDateRangeIncludesItemsInRange() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let inRange = LifeAdminItem(title: "Rent", dueDate: now.addingTimeInterval(86400 * 3))
     var f = SearchFilter()
     f.dueFrom = now
     f.dueTo = now.addingTimeInterval(86400 * 7)
     XCTAssertEqual(SearchEngine().search([inRange], filter: f).count, 1)
 }
 func testFilteringByDueDateRangeExcludesItemsOutsideRangeOrWithNoDueDate() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let tooLate = LifeAdminItem(title: "Later", dueDate: now.addingTimeInterval(86400 * 30))
     let noDueDate = LifeAdminItem(title: "No date")
     var f = SearchFilter()
     f.dueFrom = now
     f.dueTo = now.addingTimeInterval(86400 * 7)
     XCTAssertTrue(SearchEngine().search([tooLate, noDueDate], filter: f).isEmpty)
 }
 func testDuplicateDetection() { let d=Date(); let a=LifeAdminItem(title:"Car Insurance", dueDate:d, amount:840); let b=LifeAdminItem(title:"car insurance", dueDate:d.addingTimeInterval(60), amount:840); XCTAssertTrue(DuplicateDetector().isLikelyDuplicate(a,b)) }
 // Regression test for a real bug: matching on the raw Decimal `amount` alone let two same-titled
 // items months apart (so the date-proximity signal is out) get flagged as duplicates purely
 // because "100 == 100" — ignoring that they're denominated in different currencies entirely.
 func testDuplicateDetectionRequiresMatchingCurrencyNotJustAmount() {
     let now = Date()
     let a = LifeAdminItem(title: "Invoice", dueDate: now, amount: 100, currency: "EUR")
     let b = LifeAdminItem(title: "Invoice", dueDate: now.addingTimeInterval(86400 * 30), amount: 100, currency: "ILS")
     XCTAssertFalse(DuplicateDetector().isLikelyDuplicate(a, b))
 }
 func testImportExport() throws { let e=ImportExportEngine(); let data=try e.exportJSON([LifeAdminItem(title:"Gym")]); XCTAssertEqual(try e.importJSON(data).first?.title, "Gym") }
 func testCSVExport() { XCTAssertTrue(ImportExportEngine().exportCSV([LifeAdminItem(title:"Gym")]).contains("Title")) }
 func testCSVExportEscapesCommaInTitle() { let csv=ImportExportEngine().exportCSV([LifeAdminItem(title:"Insurance, Inc.")]); XCTAssertTrue(csv.contains("\"Insurance, Inc.\"")) }
 func testCSVExportNeutralizesFormulaInjection() { let csv=ImportExportEngine().exportCSV([LifeAdminItem(title:"=HYPERLINK(\"http://evil.example\")")]); XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"http://evil.example\"\")\"")) }
 func testCSVExportIncludesPreviousAmountColumn() {
     var item = LifeAdminItem(title: "Car Insurance", amount: 920)
     item.previousAmount = 800
     let csv = ImportExportEngine().exportCSV([item])
     XCTAssertTrue(csv.contains("PreviousAmount"))
     XCTAssertTrue(csv.contains("800"))
 }
 func testNaturalLanguageCurrency() { let e=NaturalLanguageParser().parse("My car insurance costs €840 and renews every March 18."); XCTAssertEqual(e.category, .insurance); XCTAssertEqual(e.currency, "EUR"); XCTAssertEqual(e.recurring, .yearly) }
 func testAIJSONParsing() throws { let json=#"{"title":"Passport","category":"travel","currency":"EUR","confidence":0.8}"#.data(using:.utf8)!; XCTAssertEqual(try AIJSONValidator().decode(json).title, "Passport") }
 func testAIJSONFailure() { let json=#"{"confidence":2}"#.data(using:.utf8)!; XCTAssertThrowsError(try AIJSONValidator().decode(json)) }
 func testAIJSONParsesDocumentFieldsFromAScannedPassport() throws {
     let json = #"{"title":"Passport","category":"documents","confidence":0.9,"documentFields":[{"label":"Passport Number","value":"912345678"},{"label":"Nationality","value":"Israeli"}]}"#.data(using: .utf8)!
     let fields = try AIJSONValidator().decode(json).documentFields
     XCTAssertEqual(fields?.count, 2)
     XCTAssertEqual(fields?.first?.label, "Passport Number")
     XCTAssertEqual(fields?.first?.value, "912345678")
 }
 // A CVV/CVC must never survive decoding, no matter what a scanned card's OCR text (or a buggy/
 // compromised proxy) hands back — see DocumentFieldSafety's own doc comment for why.
 func testAIJSONNeverSurfacesACVVField() throws {
     let json = #"{"title":"Visa Card","category":"money","confidence":0.9,"documentFields":[{"label":"Card Number","value":"4111111111111111"},{"label":"CVV","value":"123"},{"label":"Security Code","value":"456"}]}"#.data(using: .utf8)!
     let fields = try AIJSONValidator().decode(json).documentFields
     XCTAssertEqual(fields?.map(\.label), ["Card Number"])
 }
 func testLocalizationCoverage() { XCTAssertEqual(SupportedLanguage.allCases.count, 14); XCTAssertTrue(SupportedLanguage.he.isRTL); XCTAssertTrue(SupportedLanguage.ar.isRTL) }
 func testStatusCompletion() { var i=LifeAdminItem(title:"Dentist"); i.status = .completed; XCTAssertEqual(i.status, .completed) }
 func testAttachmentValidation() { let a=Attachment(filename:"policy.pdf", mimeType:"application/pdf", sizeBytes:1, localPath:"/local/policy.pdf"); XCTAssertNoThrow(try ItemValidator().validate(LifeAdminItem(title:"Policy", attachments:[a]))) }
 func testDigestFlagsOverdueItem() { let overdue=LifeAdminItem(title:"Rent", dueDate:Date().addingTimeInterval(-86400*2)); let s=DigestEngine().summary(for:[overdue]); XCTAssertEqual(s.overdueCount, 1); XCTAssertTrue(DigestEngine().shouldNotify(s)) }
 func testDigestFlagsDueToday() {
     // A fixed `now` well before midnight — "1 hour from now" relative to the real wall clock
     // rolls into tomorrow whenever this happens to run late at night, making the test flaky for
     // a reason that has nothing to do with what it's actually checking.
     let now = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
     let dueToday = LifeAdminItem(title: "Bill", dueDate: now.addingTimeInterval(3600))
     let s = DigestEngine().summary(for: [dueToday], now: now)
     XCTAssertEqual(s.dueTodayCount, 1)
     XCTAssertTrue(DigestEngine().shouldNotify(s))
 }
 func testDigestStaysQuietWithNothingUrgent() { let future=LifeAdminItem(title:"Renewal", dueDate:Date().addingTimeInterval(86400*20)); let s=DigestEngine().summary(for:[future]); XCTAssertEqual(s.overdueCount, 0); XCTAssertEqual(s.dueTodayCount, 0); XCTAssertFalse(DigestEngine().shouldNotify(s)) }
 func testDigestIgnoresCompletedItems() { var done=LifeAdminItem(title:"Paid", dueDate:Date().addingTimeInterval(-86400)); done.status = .completed; let s=DigestEngine().summary(for:[done]); XCTAssertEqual(s.overdueCount, 0) }
 func testCriticalItemsGetAnEscalatedSameDayReminder() { var i=LifeAdminItem(title:"Rent", dueDate:Date().addingTimeInterval(86400*5), reminderOffsets:[30]); i.priority = .critical; XCTAssertTrue(ReminderEngine().notificationDates(for:i).contains { Calendar.current.isDate($0, inSameDayAs: i.dueDate!) }) }
 func testNonCriticalItemsDoNotGetTheEscalatedReminder() { let i=LifeAdminItem(title:"Gym", category:.other, dueDate:Date().addingTimeInterval(86400*5), reminderOffsets:[30]); XCTAssertEqual(i.priority, .low); XCTAssertFalse(ReminderEngine().notificationDates(for:i).contains { Calendar.current.isDate($0, inSameDayAs: i.dueDate!) }) }
 func testLifeEventDetectorFlagsMoving() { XCTAssertEqual(LifeEventDetector().detectedTags(in: "I'm moving to a new apartment next month"), [LifeEventDetector.movingTag]) }
 func testLifeEventDetectorIgnoresUnrelatedText() { XCTAssertTrue(LifeEventDetector().detectedTags(in: "Pay the Netflix subscription").isEmpty) }
 // .documents/.travel/.personal added after a red-team review found a passport/ID/visa renewal
 // (the exact use case this app's checklist feature targets) could otherwise show its full title
 // verbatim on the lock screen or in a shared calendar, unlike an insurance/money/health item.
 func testSensitiveCategoriesFlaggedForGenericNotifications() { XCTAssertTrue(LifeCategory.insurance.isSensitive); XCTAssertTrue(LifeCategory.money.isSensitive); XCTAssertTrue(LifeCategory.health.isSensitive); XCTAssertTrue(LifeCategory.documents.isSensitive); XCTAssertTrue(LifeCategory.travel.isSensitive); XCTAssertTrue(LifeCategory.personal.isSensitive) }
 func testNonSensitiveCategoriesShowTitleInNotifications() { XCTAssertFalse(LifeCategory.subscriptions.isSensitive); XCTAssertFalse(LifeCategory.shopping.isSensitive) }
 func testChineseLocaleIdentifiersAreValidBCP47() { XCTAssertEqual(SupportedLanguage.zhHans.localeIdentifier, "zh-Hans"); XCTAssertEqual(SupportedLanguage.zhHant.localeIdentifier, "zh-Hant") }
 func testOrdinaryLocaleIdentifierMatchesRawValue() { XCTAssertEqual(SupportedLanguage.he.localeIdentifier, "he") }
 func testParserRecognizesRentAsABill() { let e = NaturalLanguageParser().parse("I need to pay rent on the 1st"); XCTAssertEqual(e.title, "Rent"); XCTAssertEqual(e.category, .bills) }
 func testParserRecognizesGymAsMembership() { let e = NaturalLanguageParser().parse("My gym renews in March"); XCTAssertEqual(e.title, "Gym Membership"); XCTAssertEqual(e.category, .memberships) }
 func testParserRecognizesDoctorAsAppointment() { let e = NaturalLanguageParser().parse("Doctor visit next week"); XCTAssertEqual(e.title, "Doctor Appointment"); XCTAssertEqual(e.category, .appointments) }
 func testParserDoesNotFalsePositiveRentInsideParent() { let e = NaturalLanguageParser().parse("Dinner with my parents on Friday"); XCTAssertNotEqual(e.title, "Rent"); XCTAssertNotEqual(e.category, .bills) }
 func testParserPrefersSpecificInsuranceOverGeneric() { let e = NaturalLanguageParser().parse("My home insurance renews in June"); XCTAssertEqual(e.title, "Home Insurance") }
 func testDayBeforeMonthOrderParses() { XCTAssertNotNil(NaturalLanguageParser().parse("Due on 24 august").date) }
 func testMonthBeforeDayOrderStillParses() { XCTAssertNotNil(NaturalLanguageParser().parse("Due on august 24").date) }
 func testSearchFilterByStatusExcludesCompletedByDefault() { var done=LifeAdminItem(title:"Paid"); done.status = .completed; let active=LifeAdminItem(title:"Owed"); var f=SearchFilter(); f.statuses=[.active]; XCTAssertEqual(SearchEngine().search([done, active], filter:f).map(\.title), ["Owed"]) }
 func testSearchFilterByStatusCanIncludeCompleted() { var done=LifeAdminItem(title:"Paid"); done.status = .completed; var f=SearchFilter(); f.statuses=[.completed]; XCTAssertEqual(SearchEngine().search([done], filter:f).count, 1) }
 func testCompletedItemsGetNoMoreReminders() { var done=LifeAdminItem(title:"Paid", dueDate:Date().addingTimeInterval(86400*5), reminderOffsets:[1,3]); done.status = .completed; XCTAssertTrue(ReminderEngine().notificationDates(for:done).isEmpty) }
 func testActiveItemsStillGetReminders() { let active=LifeAdminItem(title:"Owed", dueDate:Date().addingTimeInterval(86400*5), reminderOffsets:[1]); XCTAssertFalse(ReminderEngine().notificationDates(for:active).isEmpty) }
 func testMonthlyRecurrenceProducesNextMonthActiveItem() {
     let due = Date(timeIntervalSince1970: 1_700_000_000)
     var item = LifeAdminItem(title: "Rent", dueDate: due, recurrence: .monthly)
     item.status = .completed
     let next = RecurrenceEngine().nextOccurrence(of: item)
     XCTAssertNotNil(next)
     XCTAssertEqual(next?.status, .active)
     XCTAssertNotEqual(next?.id, item.id)
     let expected = Calendar.current.date(byAdding: .month, value: 1, to: due)
     XCTAssertEqual(next?.dueDate, expected)
 }
 func testNonRecurringItemProducesNoNextOccurrence() { let item = LifeAdminItem(title: "One-off", dueDate: Date(), recurrence: .none); XCTAssertNil(RecurrenceEngine().nextOccurrence(of: item)) }
 func testRecurrenceWithNoDueDateProducesNoNextOccurrence() { let item = LifeAdminItem(title: "No date", recurrence: .yearly); XCTAssertNil(RecurrenceEngine().nextOccurrence(of: item)) }
 func testNextOccurrenceClearsPriorityOverrideAndGetsNewID() {
     var item = LifeAdminItem(title: "Insurance", dueDate: Date(), recurrence: .yearly)
     item.priorityOverride = .critical
     let next = RecurrenceEngine().nextOccurrence(of: item)
     XCTAssertNil(next?.priorityOverride)
     XCTAssertNotEqual(next?.id, item.id)
 }
 func testParserRecognizesShekelSymbol() { let e = NaturalLanguageParser().parse("Car insurance renews August 15th, 840 ₪"); XCTAssertEqual(e.currency, "ILS") }
 func testAmountIsNotConfusedWithTheDayOfMonth() { let e = NaturalLanguageParser().parse("Car insurance renews August 15th, $240"); XCTAssertEqual(e.amount, 240) }
 func testAmountIsNotConfusedWithABareDayNumberNextToARecognizedDate() { let e = NaturalLanguageParser().parse("On the 24 august I pay my rent each month"); XCTAssertNil(e.amount) }
 func testAmountStillFoundWhenItGenuinelyMatchesTheDayNumber() { let e = NaturalLanguageParser().parse("Rent due on the 5th, $5"); XCTAssertEqual(e.amount, 5) }
 func testAmountWithCurrencyWordAfterTheNumber() { let e = NaturalLanguageParser().parse("Electric bill 300 NIS due next week"); XCTAssertEqual(e.amount, 300) }
 func testClockTimeIsNotMisreadAsAnAmount() { let e = NaturalLanguageParser().parse("Driving test 4 september 11:00 am deurne examen centrum"); XCTAssertNil(e.amount) }
 func testClockTimeIsAppliedToTheDueDate() {
     let e = NaturalLanguageParser().parse("Driving test 4 september 11:00 am deurne examen centrum")
     XCTAssertNotNil(e.date)
     let components = Calendar.current.dateComponents([.hour, .minute], from: e.date!)
     XCTAssertEqual(components.hour, 11)
     XCTAssertEqual(components.minute, 0)
 }
 func testDateWithNoStatedTimeStaysAtMidnight() { let e = NaturalLanguageParser().parse("Passport renewal March 18"); let components = Calendar.current.dateComponents([.hour, .minute], from: e.date!); XCTAssertEqual(components.hour, 0); XCTAssertEqual(components.minute, 0) }
 func testDrivingTestIsRecognizedAsAnAppointment() { let e = NaturalLanguageParser().parse("Driving test 4 september 11:00 am"); XCTAssertEqual(e.title, "Driving Test"); XCTAssertEqual(e.category, .appointments) }
 func testParserRecognizesShekelWord() { let e = NaturalLanguageParser().parse("ביטוח רכב מתחדש ב-15 באוגוסט, 840 ש״ח"); XCTAssertEqual(e.currency, "ILS") }
 func testSplitEntriesSingleLineStaysOneEntry() { XCTAssertEqual(NaturalLanguageParser.splitEntries("Rent $1200"), ["Rent $1200"]) }
 func testSplitEntriesSplitsMultipleLines() { XCTAssertEqual(NaturalLanguageParser.splitEntries("Rent $1200\nGym $40\nNetflix $17"), ["Rent $1200", "Gym $40", "Netflix $17"]) }
 func testSplitEntriesIgnoresBlankLinesAndTrimsWhitespace() { XCTAssertEqual(NaturalLanguageParser.splitEntries("  Rent $1200  \n\n  Gym $40\n"), ["Rent $1200", "Gym $40"]) }
 func testSplitEntriesOnEmptyTextReturnsTheTextItself() { XCTAssertEqual(NaturalLanguageParser.splitEntries(""), [""]) }
 func testDateWithOrdinalSuffixIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("Car insurance renews August 15th, $240", now: now)
     XCTAssertNotNil(e.date, "an ordinal suffix (\"15th\") must not make a clearly-stated date silently disappear")
     let components = Calendar.current.dateComponents([.month, .day], from: e.date!)
     XCTAssertEqual(components.month, 8)
     XCTAssertEqual(components.day, 15)
 }
 func testNextWeekdayInEnglishIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("Dentist appointment next Tuesday", now: now)
     XCTAssertNotNil(e.date)
     XCTAssertEqual(Calendar.current.component(.weekday, from: e.date!), 3, "Tuesday is weekday 3 in Calendar's 1=Sunday...7=Saturday numbering")
     XCTAssertGreaterThan(e.date!, Calendar.current.startOfDay(for: now))
 }
 func testNextWeekdayInHebrewIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("תור לרופא ביום שלישי הבא", now: now)
     XCTAssertNotNil(e.date)
     XCTAssertEqual(Calendar.current.component(.weekday, from: e.date!), 3)
 }
 func testHebrewAbsoluteDateWithPrefixedMonthIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("ביטוח רכב מתחדש ב-15 באוגוסט, 840 שח", now: now)
     XCTAssertNotNil(e.date, "a Hebrew month name glued to its ב prefix (\"באוגוסט\") must still be recognized")
     let components = Calendar.current.dateComponents([.month, .day], from: e.date!)
     XCTAssertEqual(components.month, 8)
     XCTAssertEqual(components.day, 15)
 }
 func testInNYearsIsRecognizedAndNotMistakenForAnAmount() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("Passport expires in 2 years", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .year, value: 2, to: now)!))
     XCTAssertNil(e.amount, "a bare number immediately before a duration word (\"2 years\") is not an amount")
 }
 func testNextYearIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("warranty expires next year", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .year, value: 1, to: now)!))
 }
 func testHebrewKeywordMatchesWithGluedPrefix() {
     let e = NaturalLanguageParser().parse("מחר יש לי תור לרופא")
     XCTAssertEqual(e.category, .appointments, "\"לרופא\" (to the doctor) must match the \"רופא\" keyword despite the glued ל prefix")
 }
 func testShekelsSpelledOutInEnglishIsRecognizedAsILS() {
     let e = NaturalLanguageParser().parse("Water bill 320 shekels due in 10 days")
     XCTAssertEqual(e.currency, "ILS")
 }
 func testCasualShHWithoutPunctuationIsRecognizedAsILS() {
     let e = NaturalLanguageParser().parse("ביטוח בריאות 1200 שח")
     XCTAssertEqual(e.currency, "ILS")
 }
 func testHebrewWordForDollarIsRecognizedAsUSD() {
     let e = NaturalLanguageParser().parse("ביטוח דירה מתחדש כל שנה, 600 דולר")
     XCTAssertEqual(e.currency, "USD")
 }
 func testRenewsEveryMonthIsMonthlyNotYearly() {
     let e = NaturalLanguageParser().parse("Gym membership renews every month at $45")
     XCTAssertEqual(e.recurring, .monthly, "\"renews every month\" contains \"renews every\" as a substring — that generic yearly fallback must not win against the actual \"month\" it's paired with")
 }
 func testSlashMonthIsRecognizedAsMonthlyRecurrence() {
     let e = NaturalLanguageParser().parse("Gym membership $45/month")
     XCTAssertEqual(e.recurring, .monthly)
 }
 func testTomorrowInEnglishIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("Dentist tomorrow", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!))
 }
 func testTomorrowInHebrewIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("תור לרופא מחר", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!))
 }
 func testDayAfterTomorrowInHebrewIsTwoDaysOut() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("פגישה מחרתיים", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 2, to: now)!))
 }
 func testInNDaysInEnglishIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("Passport renewal in 3 days", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 3, to: now)!))
 }
 func testInNDaysInHebrewIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("חידוש דרכון בעוד 3 ימים", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 3, to: now)!))
 }
 // Regression test for a real bug found by a user: "remind me in 1 hour" wasn't understood as a
 // relative date at all (only day/week/month/year granularity existed) — the bare "1" was instead
 // misread as a $1 amount, with no due date set at all, silently defeating the whole reminder.
 // Hour/minute granularity deliberately does NOT snap to the start of the day like every other
 // unit here — "in 1 hour" means a specific moment, not "today".
 func testInNHoursInEnglishIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("Remind me in 1 hour to have lunch", now: now)
     XCTAssertEqual(e.date, Calendar.current.date(byAdding: .hour, value: 1, to: now))
     XCTAssertNil(e.amount, "the bare \"1\" in \"1 hour\" must not be misread as a $1 amount")
 }
 func testInNMinutesInEnglishIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("Call the pharmacy in 30 minutes", now: now)
     XCTAssertEqual(e.date, Calendar.current.date(byAdding: .minute, value: 30, to: now))
 }
 func testInAnHourInHebrewIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("תזכיר לי בעוד שעה להתקשר", now: now)
     XCTAssertEqual(e.date, Calendar.current.date(byAdding: .hour, value: 1, to: now))
 }
 func testNextWeekInHebrewIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("שכירות בעוד שבוע", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now)!))
 }
 func testTwoWeeksInHebrewIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("ביקור בעוד שבועיים", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .weekOfYear, value: 2, to: now)!))
 }
 func testRelativeDateStaysAtMidnightWithNoStatedTime() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("Dentist tomorrow", now: now)
     let components = Calendar.current.dateComponents([.hour, .minute], from: e.date!)
     XCTAssertEqual(components.hour, 0)
     XCTAssertEqual(components.minute, 0)
 }
 func testRelativeDateCombinesWithAnExplicitTime() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("Dentist tomorrow at 3pm", now: now)
     let components = Calendar.current.dateComponents([.hour, .minute], from: e.date!)
     XCTAssertEqual(components.hour, 15)
 }
 func testNextOccurrenceClearsAttachments() {
     let a = Attachment(filename: "bill.jpg", mimeType: "image/jpeg", sizeBytes: 1, localPath: "/local/bill.jpg")
     var item = LifeAdminItem(title: "Electric Bill", dueDate: Date(), recurrence: .monthly, attachments: [a])
     let next = RecurrenceEngine().nextOccurrence(of: item)
     XCTAssertEqual(next?.attachments.isEmpty, true)
 }
 // Bugs found by a 50-sentence hands-on test battery run through the real parser (not written to
 // match pre-decided expected outputs) — each one below reproduces a sentence that came back wrong.
 func testTwoMonthsInHebrewIsRecognizedAsADateNotMonthlyRecurrence() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("ביטוח נסיעות פג תוקף בעוד חודשיים", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .month, value: 2, to: now)!))
     XCTAssertEqual(e.recurring, Recurrence.none)
 }
 func testTwoYearsInHebrewIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("הרישיון פג בעוד שנתיים", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .year, value: 2, to: now)!))
 }
 func testSpelledOutNumberInEnglishIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("Dentist appointment in three weeks", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .weekOfYear, value: 3, to: now)!))
 }
 func testSpelledOutNumberInHebrewIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("תור לרופא שיניים בעוד שלושה שבועות", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .weekOfYear, value: 3, to: now)!))
 }
 func testInNMonthsIsRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("car service due in 6 months", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .month, value: 6, to: now)!))
     XCTAssertEqual(e.recurring, Recurrence.none)
 }
 func testNextMonthNameInEnglishIsRecognized() {
     let e = NaturalLanguageParser().parse("renew passport before it expires next December")
     XCTAssertNotNil(e.date)
     XCTAssertEqual(Calendar.current.component(.month, from: e.date!), 12)
 }
 func testNextMonthNameInHebrewIsRecognized() {
     let e = NaturalLanguageParser().parse("לחדש דרכון לפני שהוא פג בדצמבר הקרוב")
     XCTAssertNotNil(e.date)
     XCTAssertEqual(Calendar.current.component(.month, from: e.date!), 12)
 }
 func testAbbreviatedMonthNameIsRecognized() {
     let e = NaturalLanguageParser().parse("credit card payment $85 every month starting sep 1")
     XCTAssertNotNil(e.date)
     XCTAssertEqual(Calendar.current.component(.month, from: e.date!), 9)
 }
 func testClockTimeGluedToAmPmIsNotMisreadAsAnAmount() {
     let e = NaturalLanguageParser().parse("meeting with the accountant tomorrow at 9am")
     XCTAssertNil(e.amount)
 }
 func testSpelledOutDollarsIsRecognizedAsUSD() {
     let e = NaturalLanguageParser().parse("pet insurance 45 dollars a month, renews on the 10th")
     XCTAssertEqual(e.currency, "USD")
     XCTAssertEqual(e.recurring, .monthly)
 }
 func testEveryNMonthsIsRecognizedAsEverySixMonthsNotYearly() {
     let e = NaturalLanguageParser().parse("streaming bundle renews every 6 months for $89.99")
     XCTAssertEqual(e.recurring, .everySixMonths)
 }
 func testHebrewHalfYearIsRecognizedAsEverySixMonths() {
     let e = NaturalLanguageParser().parse("מנוי טלוויזיה מתחדש כל חצי שנה ב-350 שקל")
     XCTAssertEqual(e.recurring, .everySixMonths)
 }
 func testFallbackTitleStopsBeforeABareAmount() {
     let e = NaturalLanguageParser().parse("annual subscription fee 3800 nis due the 28th of every month")
     XCTAssertEqual(e.title, "annual subscription fee")
 }
 func testLoanIsRecognizedAsMoneyCategory() {
     let e = NaturalLanguageParser().parse("housing loan installment 3800 nis due the 28th of every month")
     XCTAssertEqual(e.title, "Loan")
     XCTAssertEqual(e.category, LifeCategory.money)
 }
 // Recurrence coverage: daily/biweekly/everyTwoMonths/quarterly/weekly were part of the
 // Recurrence model but could never actually be produced by the natural-language parser before
 // this — any real sentence using them silently fell through to .none or the wrong bucket.
 func testDailyIsRecognized() {
     XCTAssertEqual(NaturalLanguageParser().parse("Take vitamins daily").recurring, Recurrence.daily)
     XCTAssertEqual(NaturalLanguageParser().parse("תרופה יומית בבוקר").recurring, Recurrence.daily)
 }
 func testWeeklyIsRecognized() {
     XCTAssertEqual(NaturalLanguageParser().parse("Trash pickup is weekly").recurring, Recurrence.weekly)
     XCTAssertEqual(NaturalLanguageParser().parse("אשפה נאספת כל שבוע").recurring, Recurrence.weekly)
 }
 func testBiweeklyIsRecognized() {
     XCTAssertEqual(NaturalLanguageParser().parse("Payroll deduction is biweekly, $200").recurring, Recurrence.biweekly)
     XCTAssertEqual(NaturalLanguageParser().parse("warranty check every other week").recurring, Recurrence.biweekly)
 }
 func testHebrewBiweeklyDoesNotAlsoFabricateADueDate() {
     // "כל שבועיים" ("every two weeks") is a recurrence with no specific date at all — it must
     // not also trigger the unrelated "שבועיים" (dual "two weeks") one-time relative-date match.
     let e = NaturalLanguageParser().parse("משכורת מתקבלת כל שבועיים")
     XCTAssertEqual(e.recurring, Recurrence.biweekly)
     XCTAssertNil(e.date)
 }
 func testEveryTwoMonthsIsRecognized() {
     XCTAssertEqual(NaturalLanguageParser().parse("Car wash every two months").recurring, Recurrence.everyTwoMonths)
     XCTAssertEqual(NaturalLanguageParser().parse("insurance renews every other month").recurring, Recurrence.everyTwoMonths)
 }
 func testHebrewEveryTwoMonthsDoesNotAlsoFabricateADueDate() {
     let e = NaturalLanguageParser().parse("שטיפת רכב כל חודשיים, 60 שח")
     XCTAssertEqual(e.recurring, Recurrence.everyTwoMonths)
     XCTAssertNil(e.date)
 }
 func testQuarterlyIsRecognized() {
     XCTAssertEqual(NaturalLanguageParser().parse("Gym fee charged quarterly, $150").recurring, Recurrence.quarterly)
     XCTAssertEqual(NaturalLanguageParser().parse("תשלום רבעוני לביטוח, 900 שקל").recurring, Recurrence.quarterly)
     XCTAssertEqual(NaturalLanguageParser().parse("Cleaning service every three months").recurring, Recurrence.quarterly)
 }
 func testOneTimeInTwoMonthsIsNotMisreadAsRecurring() {
     // "due in two months" is a one-time date, not a recurrence — must not be swept up by the
     // new everyTwoMonths detection just because it mentions "two months".
     let e = NaturalLanguageParser().parse("car wash due in two months")
     XCTAssertEqual(e.recurring, Recurrence.none)
     XCTAssertNotNil(e.date)
 }
 func testHebrewTwoDaysIsRecognizedAsADate() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("פגישה בעוד יומיים", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 2, to: now)!))
 }
 // LifeCategory has car/money/health/work/education/documents/family cases that the parser could
 // never actually produce before — every sentence naming one of them silently landed in .other.
 func testCarServiceIsRecognizedAsCarCategory() {
     XCTAssertEqual(NaturalLanguageParser().parse("Car wash this weekend, 60 nis").category, LifeCategory.car)
     XCTAssertEqual(NaturalLanguageParser().parse("טיפול לרכב בעוד שבוע").category, LifeCategory.car)
 }
 func testPrescriptionIsRecognizedAsHealthCategory() {
     XCTAssertEqual(NaturalLanguageParser().parse("Pick up my prescription tomorrow").category, LifeCategory.health)
     XCTAssertEqual(NaturalLanguageParser().parse("לקחת מרשם ממחר").category, LifeCategory.health)
 }
 func testSalaryIsRecognizedAsWorkCategory() {
     XCTAssertEqual(NaturalLanguageParser().parse("Payroll runs on the 1st").category, LifeCategory.work)
     XCTAssertEqual(NaturalLanguageParser().parse("המשכורת נכנסת ב-1 לחודש").category, LifeCategory.work)
 }
 func testTuitionIsRecognizedAsEducationCategory() {
     XCTAssertEqual(NaturalLanguageParser().parse("Tuition payment due September 1st, $4,200").category, LifeCategory.education)
 }
 func testBirthdayIsRecognizedAsFamilyCategory() {
     XCTAssertEqual(NaturalLanguageParser().parse("Mom's birthday is next month").category, LifeCategory.family)
 }
 func testHebrewDefiniteArticleInsertedMidPhraseStillMatches() {
     // "כרטיס האשראי" ("the credit card") inserts Hebrew's definite article "ה" onto the second
     // word — a completely ordinary way to phrase it that a bare "כרטיס אשראי" substring check
     // would otherwise miss entirely.
     let e = NaturalLanguageParser().parse("פרעתי את כרטיס האשראי, 340 שח")
     XCTAssertEqual(e.category, LifeCategory.money)
     let insurance = NaturalLanguageParser().parse("ביטוח הרכב מתחדש בקרוב")
     XCTAssertEqual(insurance.category, LifeCategory.insurance)
 }
 func testUnrelatedHomeAndSchoolMentionsDoNotFalsePositive() {
     // Guards against ever adding an overly broad bare keyword like "home"/"school" for the
     // .home/.education categories — these ordinary sentences must stay uncategorized (.other)
     // rather than being swept up by too-eager matching.
     XCTAssertEqual(NaturalLanguageParser().parse("working from home today").category, LifeCategory.other)
     XCTAssertEqual(NaturalLanguageParser().parse("school starts next week").category, LifeCategory.other)
 }

 // MARK: - Recurrence month-end drift (Engines.swift)

 func testMonthlyRecurrenceAnchoredOnJan31RollsToFeb28() {
     var cal = Calendar(identifier: .gregorian)
     cal.timeZone = TimeZone(identifier: "UTC")!
     let jan31 = cal.date(from: DateComponents(year: 2026, month: 1, day: 31))!
     let item = LifeAdminItem(title: "Rent", dueDate: jan31, recurrence: .monthly)
     let next = RecurrenceEngine().nextOccurrence(of: item, calendar: cal)
     XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: next!.dueDate!), DateComponents(year: 2026, month: 2, day: 28))
 }

 func testMonthlyRecurrenceAnchoredOnJan31ReturnsToThe31stOnceALongMonthComesAround() {
     // The real-world bug: chaining "+1 month" off the already-clamped Feb 28 date gives Mar 28,
     // not Mar 31, and every later month inherits that shrunken day forever — a bill due on the
     // 31st silently and permanently drifts to the 28th. Carrying the intended day separately
     // (recurrenceAnchorDay) must snap the date back to the 31st the moment March comes around.
     var cal = Calendar(identifier: .gregorian)
     cal.timeZone = TimeZone(identifier: "UTC")!
     let jan31 = cal.date(from: DateComponents(year: 2026, month: 1, day: 31))!
     var item = LifeAdminItem(title: "Rent", dueDate: jan31, recurrence: .monthly)
     for _ in 0..<2 {
         item = RecurrenceEngine().nextOccurrence(of: item, calendar: cal)!
     }
     // Jan 31 -> Feb 28 -> Mar 31 (not Mar 28)
     XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: item.dueDate!), DateComponents(year: 2026, month: 3, day: 31))
 }

 func testYearlyRecurrenceOnLeapDayClampsToFeb28InANonLeapYear() {
     var cal = Calendar(identifier: .gregorian)
     cal.timeZone = TimeZone(identifier: "UTC")!
     let feb29 = cal.date(from: DateComponents(year: 2028, month: 2, day: 29))!
     let item = LifeAdminItem(title: "Anniversary reminder", dueDate: feb29, recurrence: .yearly)
     let next = RecurrenceEngine().nextOccurrence(of: item, calendar: cal)
     XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: next!.dueDate!), DateComponents(year: 2029, month: 2, day: 28))
 }
 // Regression test for a real bug: .yearly used to advance with a bare `calendar.date(byAdding:
 // .year, ...)`, which keeps whatever day the clamped date landed on (28) forever, instead of
 // re-checking the real anchor day (29) the way the monthly-family cases already do. Chaining
 // through to the next leap year confirms it snaps back to Feb 29 instead of staying stuck on 28.
 func testYearlyRecurrenceReturnsToLeapDayOnTheNextLeapYear() {
     var cal = Calendar(identifier: .gregorian)
     cal.timeZone = TimeZone(identifier: "UTC")!
     let feb29 = cal.date(from: DateComponents(year: 2028, month: 2, day: 29))!
     var item = LifeAdminItem(title: "Anniversary reminder", dueDate: feb29, recurrence: .yearly)
     for _ in 0..<4 {
         item = RecurrenceEngine().nextOccurrence(of: item, calendar: cal)!
     }
     // 2028 (29) -> 2029 (28) -> 2030 (28) -> 2031 (28) -> 2032 (29, a leap year again)
     XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: item.dueDate!), DateComponents(year: 2032, month: 2, day: 29))
 }

 // MARK: - Model invariants (Models.swift / Engines.swift)

 func testNegativeAmountIsRejected() {
     XCTAssertThrowsError(try ItemValidator().validate(LifeAdminItem(title: "Refund", amount: -50, currency: "USD")))
 }

 func testNegativeAttachmentSizeIsRejected() {
     let a = Attachment(filename: "bad.pdf", mimeType: "application/pdf", sizeBytes: -1, localPath: "/x")
     XCTAssertThrowsError(try ItemValidator().validate(LifeAdminItem(title: "Policy", attachments: [a])))
 }

 func testCodableRoundTripPreservesEveryPopulatedOptionalField() throws {
     let attachment = Attachment(filename: "policy.pdf", mimeType: "application/pdf", sizeBytes: 1024, localPath: "/local/policy.pdf")
     let contact = ContactInfo(name: "Dana", company: "Acme", phone: "050-1234567", email: "dana@acme.com", website: "https://acme.com", notes: "Ask for Dana")
     let documentField = DocumentField(label: "Policy Number", value: "POL-12345")
     let full = LifeAdminItem(
         title: "Car Insurance", description: "Annual policy", category: .insurance, status: .snoozed,
         priority: .high, priorityOverride: .critical, dueDate: Date(timeIntervalSince1970: 1_700_000_000),
         endDate: Date(timeIntervalSince1970: 1_800_000_000), amount: 840.50, currency: "ILS",
         recurrence: .yearly, recurrenceRule: "FREQ=YEARLY", recurrenceAnchorDay: 31,
         reminderOffsets: [30, 7, 1], notes: "Renew early", tags: ["car", "insurance"],
         attachments: [attachment], contact: contact, location: "Home", documentFields: [documentField],
         createdAt: Date(timeIntervalSince1970: 1_600_000_000), updatedAt: Date(timeIntervalSince1970: 1_650_000_000)
     )
     let decodedFull = try JSONDecoder().decode(LifeAdminItem.self, from: JSONEncoder().encode(full))
     XCTAssertEqual(decodedFull, full)

     let empty = LifeAdminItem(title: "Minimal")
     let decodedEmpty = try JSONDecoder().decode(LifeAdminItem.self, from: JSONEncoder().encode(empty))
     XCTAssertEqual(decodedEmpty, empty)
 }

 func testOldExportWithoutRecurrenceAnchorDayFieldStillDecodes() {
     // Backward compatibility: a backup exported before recurrenceAnchorDay existed has no such
     // key at all. It must still decode (as nil), not fail to import.
     let json = #"[{"id":"\#(UUID().uuidString)","title":"Gym","category":"other","status":"active","priority":"low","recurrence":"none","reminderOffsets":[],"tags":[],"attachments":[],"createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z"}]"#.data(using: .utf8)!
     XCTAssertNoThrow(try ImportExportEngine().importJSON(json))
 }

 func testOldExportWithoutDocumentFieldsKeyStillDecodesAsEmpty() throws {
     // Same backward-compatibility contract as recurrenceAnchorDay above, but for documentFields
     // — added later, and (unlike recurrenceAnchorDay) a non-optional array everywhere else in
     // the app, so it needs its own explicit decoding fallback rather than getting one for free.
     let json = #"[{"id":"\#(UUID().uuidString)","title":"Gym","category":"other","status":"active","priority":"low","recurrence":"none","reminderOffsets":[],"tags":[],"attachments":[],"createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z"}]"#.data(using: .utf8)!
     let items = try ImportExportEngine().importJSON(json)
     XCTAssertEqual(items.first?.documentFields, [])
 }

 // MARK: - ImportExportEngine edge cases (Engines.swift)

 func testCSVExportStartsWithUTF8BOMSoExcelRendersHebrewCorrectly() {
     let csv = ImportExportEngine().exportCSV([LifeAdminItem(title: "שכר דירה")])
     XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
     XCTAssertTrue(csv.contains("שכר דירה"))
 }

 func testImportRejectsDuplicateIDs() throws {
     let e = ImportExportEngine()
     let a = LifeAdminItem(title: "Gym")
     var b = LifeAdminItem(title: "Netflix")
     b.id = a.id
     let data = try e.exportJSON([a, b])
     XCTAssertThrowsError(try e.importJSON(data))
 }

 func testImportOfEmptyDataThrowsFriendlyErrorNotARawDecodingError() {
     XCTAssertThrowsError(try ImportExportEngine().importJSON(Data())) { error in
         XCTAssertTrue(error is LifeAdminError)
     }
 }

 func testImportAtExactlyTheCapSucceeds() throws {
     let e = ImportExportEngine()
     let items = (0..<ImportExportEngine.maxImportItemCount).map { LifeAdminItem(title: "Item \($0)") }
     let data = try e.exportJSON(items)
     XCTAssertEqual(try e.importJSON(data).count, ImportExportEngine.maxImportItemCount)
 }

 func testImportOneOverTheCapThrows() throws {
     let e = ImportExportEngine()
     let items = (0...ImportExportEngine.maxImportItemCount).map { LifeAdminItem(title: "Item \($0)") }
     let data = try e.exportJSON(items)
     XCTAssertThrowsError(try e.importJSON(data))
 }

 // MARK: - AddressChangeDraftBuilder (AddressChange.swift)

 func testAddressChangeDraftIsNotBuiltForABlankNewAddress() {
     let item = LifeAdminItem(title: "Bank Account", contact: ContactInfo(email: "bank@example.com"))
     XCTAssertNil(AddressChangeDraftBuilder().draft(for: item, newAddress: "   "))
 }

 func testAddressChangeDraftIsBuiltForANonBlankNewAddress() {
     let item = LifeAdminItem(title: "Bank Account", contact: ContactInfo(email: "bank@example.com"))
     XCTAssertNotNil(AddressChangeDraftBuilder().draft(for: item, newAddress: "123 Main St"))
 }
 // Spanish/French support: parse() understands text in whichever of the app's languages the
 // user actually typed in, regardless of the app's current display language. Bugs below were
 // found by a hands-on battery of genuinely varied Spanish/French sentences run through the
 // real parser, same methodology as the English/Hebrew rounds above.
 func testSpanishDayDeMonthDateIsRecognized() {
     let e = NaturalLanguageParser().parse("El seguro de auto se renueva el 15 de agosto, 240 euros")
     XCTAssertNotNil(e.date)
     XCTAssertEqual(Calendar.current.component(.month, from: e.date!), 8)
     XCTAssertEqual(Calendar.current.component(.day, from: e.date!), 15)
     XCTAssertEqual(e.amount, 240)
     XCTAssertEqual(e.currency, "EUR")
     XCTAssertEqual(e.category, LifeCategory.insurance)
 }
 func testFrenchDayMonthDateIsRecognized() {
     let e = NaturalLanguageParser().parse("L'assurance auto se renouvelle le 15 août, 240 euros")
     XCTAssertNotNil(e.date)
     XCTAssertEqual(Calendar.current.component(.month, from: e.date!), 8)
     XCTAssertEqual(Calendar.current.component(.day, from: e.date!), 15)
 }
 func testSpanishRecurringDayOfMonthIsNotMisreadAsAnAmount() {
     let e = NaturalLanguageParser().parse("Netflix se renueva el 1 de cada mes")
     XCTAssertNil(e.amount)
     XCTAssertEqual(e.recurring, Recurrence.monthly)
 }
 func testFrenchOrdinalDayOfMonthIsNotMisreadAsAnAmount() {
     let e = NaturalLanguageParser().parse("Netflix se renouvelle le 1er de chaque mois")
     XCTAssertNil(e.amount)
     XCTAssertEqual(e.recurring, Recurrence.monthly)
 }
 func testSpanishYearsDurationIsNotMisreadAsAnAmount() {
     let e = NaturalLanguageParser().parse("El pasaporte vence en 2 años")
     XCTAssertNil(e.amount)
     XCTAssertNotNil(e.date)
 }
 func testFrenchDaysDurationIsNotMisreadAsAnAmount() {
     let e = NaturalLanguageParser().parse("Facture d'électricité due dans 3 jours, 512 dollars")
     XCTAssertEqual(e.amount, 512)
     XCTAssertEqual(e.currency, "USD")
 }
 func testSpanishNextWeekdayIsRecognized() {
     let e = NaturalLanguageParser().parse("Cita con el dentista el próximo martes")
     XCTAssertNotNil(e.date)
     XCTAssertEqual(e.category, LifeCategory.appointments)
 }
 func testFrenchRelativeDateAndCategoryAreRecognized() {
     let now = Date(timeIntervalSince1970: 1_700_000_000)
     let e = NaturalLanguageParser().parse("Demain j'ai rendez-vous chez le médecin", now: now)
     XCTAssertEqual(e.date, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!))
     XCTAssertEqual(e.category, LifeCategory.appointments)
 }
 func testSpanishQuarterlyRecurrenceIsRecognized() {
     let e = NaturalLanguageParser().parse("Pago trimestral del gimnasio, 150 dólares")
     XCTAssertEqual(e.recurring, Recurrence.quarterly)
     XCTAssertEqual(e.category, LifeCategory.memberships)
 }
 func testFrenchEverySixMonthsRecurrenceIsRecognized() {
     let e = NaturalLanguageParser().parse("L'assurance auto se renouvelle tous les six mois")
     XCTAssertEqual(e.recurring, Recurrence.everySixMonths)
 }
 func testSpanishLoanIsRecognizedAsMoneyCategory() {
     let e = NaturalLanguageParser().parse("Tomé un préstamo para la renovación")
     XCTAssertEqual(e.category, LifeCategory.money)
 }
 func testFrenchBirthdayIsRecognizedAsFamilyCategory() {
     let e = NaturalLanguageParser().parse("L'anniversaire de maman est le mois prochain")
     XCTAssertEqual(e.category, LifeCategory.family)
 }
 func testSpelledOutEuroIsRecognizedAsEUR() {
     XCTAssertEqual(NaturalLanguageParser().parse("El seguro cuesta 100 euros").currency, "EUR")
 }
 // ChecklistEngine: the starter checklist of commonly-forgotten reminders (passport, car
 // insurance, ...), shown to users who haven't added one yet.
 func testDefaultsCoverEveryCategoryTheyClaimAndHaveNoDuplicateIDs() {
     let defaults = ChecklistSuggestion.defaults
     XCTAssertEqual(Set(defaults.map(\.id)).count, defaults.count)
     XCTAssertFalse(defaults.isEmpty)
 }
 func testUncoveredCategoryProducesAnOutstandingSuggestion() {
     let suggestions = ChecklistEngine().outstandingSuggestions(items: [])
     XCTAssertTrue(suggestions.contains { $0.id == "passport" })
 }
 func testMatchingExistingItemCoversItsSuggestion() {
     let carInsurance = LifeAdminItem(title: "Car Insurance", category: .insurance)
     let suggestions = ChecklistEngine().outstandingSuggestions(items: [carInsurance])
     XCTAssertFalse(suggestions.contains { $0.id == "carInsurance" })
     // A different insurance keyword in the same category must not falsely cover car insurance.
     XCTAssertTrue(suggestions.contains { $0.id == "homeInsurance" })
 }
 func testHebrewTitleAlsoCoversItsSuggestion() {
     let item = LifeAdminItem(title: "ביטוח דירה", category: .insurance)
     let suggestions = ChecklistEngine().outstandingSuggestions(items: [item])
     XCTAssertFalse(suggestions.contains { $0.id == "homeInsurance" })
 }
 func testArchivedItemDoesNotCountAsCoverage() {
     var item = LifeAdminItem(title: "Passport", category: .travel)
     item.status = .archived
     let suggestions = ChecklistEngine().outstandingSuggestions(items: [item])
     XCTAssertTrue(suggestions.contains { $0.id == "passport" })
 }
 func testDismissedSuggestionStaysHiddenEvenWhenUncovered() {
     let suggestions = ChecklistEngine().outstandingSuggestions(items: [], dismissedIDs: ["passport"])
     XCTAssertFalse(suggestions.contains { $0.id == "passport" })
 }
 // Regression test for a real bug: a `.completed` item used to count as coverage exactly like an
 // `.active` one. That's harmless for a recurring suggestion (completing it immediately creates a
 // fresh active occurrence via RecurrenceEngine.nextOccurrence), but a one-off suggestion like
 // "passport" (suggestedRecurrence: .none) has no next occurrence — so a completed passport item
 // used to hide the suggestion forever, even long after that passport actually expired again.
 func testCompletedOneOffItemDoesNotPermanentlyCoverItsSuggestion() {
     var item = LifeAdminItem(title: "Passport", category: .travel)
     item.status = .completed
     let suggestions = ChecklistEngine().outstandingSuggestions(items: [item])
     XCTAssertTrue(suggestions.contains { $0.id == "passport" })
 }
 func testActiveItemStillCoversItsSuggestion() {
     let item = LifeAdminItem(title: "Passport", category: .travel, status: .active)
     let suggestions = ChecklistEngine().outstandingSuggestions(items: [item])
     XCTAssertFalse(suggestions.contains { $0.id == "passport" })
 }
 // ReminderEngine.defaultOffsets: a one-size-fits-all lead time doesn't fit what these
 // categories actually involve (see the doc comment on defaultOffsets itself).
 func testDefaultOffsetsGiveLongLeadTimeForInsuranceAndTravel() {
     XCTAssertEqual(ReminderEngine.defaultOffsets(for: .insurance), [90, 30, 7, 1])
     XCTAssertEqual(ReminderEngine.defaultOffsets(for: .travel), [90, 30, 7, 1])
     XCTAssertEqual(ReminderEngine.defaultOffsets(for: .documents), [90, 30, 7, 1])
     XCTAssertEqual(ReminderEngine.defaultOffsets(for: .warranties), [90, 30, 7, 1])
 }
 func testDefaultOffsetsGiveShortLeadTimeForSubscriptionsAndMemberships() {
     XCTAssertEqual(ReminderEngine.defaultOffsets(for: .subscriptions), [3, 1])
     XCTAssertEqual(ReminderEngine.defaultOffsets(for: .memberships), [3, 1])
 }
 func testDefaultOffsetsFallBackToAModerateWindow() {
     XCTAssertEqual(ReminderEngine.defaultOffsets(for: .bills), [30, 7])
     XCTAssertEqual(ReminderEngine.defaultOffsets(for: .other), [30, 7])
 }
 // RecurrenceEngine.nextOccurrence / priceChangePercent: catching a renewal that quietly costs
 // more than the cycle it replaced.
 func testNextOccurrenceCarriesForwardThePreviousAmountForComparison() {
     let item = LifeAdminItem(title: "Car Insurance", category: .insurance, dueDate: Date(), amount: 800, currency: "ILS", recurrence: .yearly)
     let next = RecurrenceEngine().nextOccurrence(of: item)
     XCTAssertEqual(next?.previousAmount, 800)
     // The starting guess for the new cycle's amount is last time's — it hasn't diverged yet.
     XCTAssertEqual(next?.amount, 800)
 }
 func testPriceChangePercentDetectsAnIncrease() {
     var item = LifeAdminItem(title: "Car Insurance", amount: 920)
     item.previousAmount = 800
     XCTAssertEqual(RecurrenceEngine().priceChangePercent(for: item) ?? 0, 15, accuracy: 0.01)
 }
 func testPriceChangePercentDetectsADecrease() {
     var item = LifeAdminItem(title: "Car Insurance", amount: 700)
     item.previousAmount = 800
     let percent = RecurrenceEngine().priceChangePercent(for: item)
     XCTAssertNotNil(percent)
     XCTAssertTrue(percent! < 0)
 }
 func testPriceChangePercentIsNilWithNoPriorAmount() {
     let item = LifeAdminItem(title: "Car Insurance", amount: 800)
     XCTAssertNil(RecurrenceEngine().priceChangePercent(for: item))
 }
 // Scam/phishing-language heuristic: deliberately requires BOTH an urgency/threat phrase AND a
 // phishing-style action phrase together, specifically so ordinary bills using normal urgency
 // language ("final notice", "pay immediately") on their own are never flagged.
 func testUrgencyLanguageAloneDoesNotTriggerScamFlag() {
     let e = NaturalLanguageParser().parse("Final notice: electricity bill $150 due immediately or service will be cut off")
     XCTAssertNotEqual(e.scamRiskDetected, true)
 }
 func testUrgencyPlusPhishingActionTriggersScamFlag() {
     let e = NaturalLanguageParser().parse("Your account will be suspended — verify your account now to avoid suspension")
     XCTAssertEqual(e.scamRiskDetected, true)
 }
 func testHebrewUrgencyPlusPhishingActionTriggersScamFlag() {
     let e = NaturalLanguageParser().parse("החשבון שלך יושעה - אמת את החשבון שלך מיד")
     XCTAssertEqual(e.scamRiskDetected, true)
 }
 func testOrdinaryReminderDoesNotTriggerScamFlag() {
     let e = NaturalLanguageParser().parse("Car insurance renews August 15th, $240")
     XCTAssertNotEqual(e.scamRiskDetected, true)
 }
 func testSpanishUrgencyPlusPhishingActionTriggersScamFlag() {
     let e = NaturalLanguageParser().parse("Su cuenta será suspendida - verifique su cuenta ahora")
     XCTAssertEqual(e.scamRiskDetected, true)
 }
 func testFrenchUrgencyPlusPhishingActionTriggersScamFlag() {
     let e = NaturalLanguageParser().parse("Votre compte sera suspendu - vérifiez votre compte maintenant")
     XCTAssertEqual(e.scamRiskDetected, true)
 }
}
