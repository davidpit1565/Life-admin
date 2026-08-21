import XCTest
@testable import LifeAdminCore
final class LifeAdminCoreTests: XCTestCase {
 func testItemCreationValidation() throws { try ItemValidator().validate(LifeAdminItem(title:"Passport", currency:"EUR")) }
 func testInvalidCurrency() { XCTAssertThrowsError(try ItemValidator().validate(LifeAdminItem(title:"X", currency:"EURO"))) }
 func testPriority() { let due=Date().addingTimeInterval(3600); let i=LifeAdminItem(title:"Passport", category:.documents, dueDate:due, amount:10, currency:"USD", recurrence:.yearly); XCTAssertEqual(PriorityEngine().priority(for:i), .critical) }
 func testReminderCalculation() { let due=Date(timeIntervalSince1970: 86400*100); let i=LifeAdminItem(title:"P", dueDate:due, reminderOffsets:[90,30,7,1]); XCTAssertEqual(ReminderEngine().notificationDates(for:i).count, 4) }
 func testSearch() { let i=LifeAdminItem(title:"Car Insurance", category:.insurance, amount:840, currency:"EUR"); var f=SearchFilter(); f.query="840"; XCTAssertEqual(SearchEngine().search([i], filter:f).count, 1) }
 func testFiltering() { let i=LifeAdminItem(title:"Netflix", category:.subscriptions, amount:17, currency:"USD"); var f=SearchFilter(); f.categories=[.subscriptions]; f.hasPayment=true; XCTAssertEqual(SearchEngine().search([i], filter:f).count, 1) }
 func testDuplicateDetection() { let d=Date(); let a=LifeAdminItem(title:"Car Insurance", dueDate:d, amount:840); let b=LifeAdminItem(title:"car insurance", dueDate:d.addingTimeInterval(60), amount:840); XCTAssertTrue(DuplicateDetector().isLikelyDuplicate(a,b)) }
 func testImportExport() throws { let e=ImportExportEngine(); let data=try e.exportJSON([LifeAdminItem(title:"Gym")]); XCTAssertEqual(try e.importJSON(data).first?.title, "Gym") }
 func testCSVExport() { XCTAssertTrue(ImportExportEngine().exportCSV([LifeAdminItem(title:"Gym")]).contains("Title")) }
 func testNaturalLanguageCurrency() { let e=NaturalLanguageParser().parse("My car insurance costs €840 and renews every March 18."); XCTAssertEqual(e.category, .insurance); XCTAssertEqual(e.currency, "EUR"); XCTAssertEqual(e.recurring, .yearly) }
 func testAIJSONParsing() throws { let json=#"{"title":"Passport","category":"travel","currency":"EUR","confidence":0.8}"#.data(using:.utf8)!; XCTAssertEqual(try AIJSONValidator().decode(json).title, "Passport") }
 func testAIJSONFailure() { let json=#"{"confidence":2}"#.data(using:.utf8)!; XCTAssertThrowsError(try AIJSONValidator().decode(json)) }
 func testLocalizationCoverage() { XCTAssertEqual(SupportedLanguage.allCases.count, 14); XCTAssertTrue(SupportedLanguage.he.isRTL); XCTAssertTrue(SupportedLanguage.ar.isRTL) }
 func testStatusCompletion() { var i=LifeAdminItem(title:"Dentist"); i.status = .completed; XCTAssertEqual(i.status, .completed) }
 func testAttachmentValidation() { let a=Attachment(filename:"policy.pdf", mimeType:"application/pdf", sizeBytes:1, localPath:"/local/policy.pdf"); XCTAssertNoThrow(try ItemValidator().validate(LifeAdminItem(title:"Policy", attachments:[a]))) }
 func testDigestFlagsOverdueItem() { let overdue=LifeAdminItem(title:"Rent", dueDate:Date().addingTimeInterval(-86400*2)); let s=DigestEngine().summary(for:[overdue]); XCTAssertEqual(s.overdueCount, 1); XCTAssertTrue(DigestEngine().shouldNotify(s)) }
 func testDigestFlagsDueToday() { let dueToday=LifeAdminItem(title:"Bill", dueDate:Date().addingTimeInterval(3600)); let s=DigestEngine().summary(for:[dueToday]); XCTAssertEqual(s.dueTodayCount, 1); XCTAssertTrue(DigestEngine().shouldNotify(s)) }
 func testDigestStaysQuietWithNothingUrgent() { let future=LifeAdminItem(title:"Renewal", dueDate:Date().addingTimeInterval(86400*20)); let s=DigestEngine().summary(for:[future]); XCTAssertEqual(s.overdueCount, 0); XCTAssertEqual(s.dueTodayCount, 0); XCTAssertFalse(DigestEngine().shouldNotify(s)) }
 func testDigestIgnoresCompletedItems() { var done=LifeAdminItem(title:"Paid", dueDate:Date().addingTimeInterval(-86400)); done.status = .completed; let s=DigestEngine().summary(for:[done]); XCTAssertEqual(s.overdueCount, 0) }
 func testCriticalItemsGetAnEscalatedSameDayReminder() { var i=LifeAdminItem(title:"Rent", dueDate:Date().addingTimeInterval(86400*5), reminderOffsets:[30]); i.priority = .critical; XCTAssertTrue(ReminderEngine().notificationDates(for:i).contains { Calendar.current.isDate($0, inSameDayAs: i.dueDate!) }) }
 func testNonCriticalItemsDoNotGetTheEscalatedReminder() { let i=LifeAdminItem(title:"Gym", category:.other, dueDate:Date().addingTimeInterval(86400*5), reminderOffsets:[30]); XCTAssertEqual(i.priority, .low); XCTAssertFalse(ReminderEngine().notificationDates(for:i).contains { Calendar.current.isDate($0, inSameDayAs: i.dueDate!) }) }
 func testLifeEventDetectorFlagsMoving() { XCTAssertEqual(LifeEventDetector().detectedTags(in: "I'm moving to a new apartment next month"), [LifeEventDetector.movingTag]) }
 func testLifeEventDetectorIgnoresUnrelatedText() { XCTAssertTrue(LifeEventDetector().detectedTags(in: "Pay the Netflix subscription").isEmpty) }
 func testSensitiveCategoriesFlaggedForGenericNotifications() { XCTAssertTrue(LifeCategory.insurance.isSensitive); XCTAssertTrue(LifeCategory.money.isSensitive); XCTAssertTrue(LifeCategory.health.isSensitive) }
 func testNonSensitiveCategoriesShowTitleInNotifications() { XCTAssertFalse(LifeCategory.subscriptions.isSensitive); XCTAssertFalse(LifeCategory.travel.isSensitive) }
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
 func testParserRecognizesShekelWord() { let e = NaturalLanguageParser().parse("ביטוח רכב מתחדש ב-15 באוגוסט, 840 ש״ח"); XCTAssertEqual(e.currency, "ILS") }
 func testNextOccurrenceClearsAttachments() {
     let a = Attachment(filename: "bill.jpg", mimeType: "image/jpeg", sizeBytes: 1, localPath: "/local/bill.jpg")
     var item = LifeAdminItem(title: "Electric Bill", dueDate: Date(), recurrence: .monthly, attachments: [a])
     let next = RecurrenceEngine().nextOccurrence(of: item)
     XCTAssertEqual(next?.attachments.isEmpty, true)
 }
}
