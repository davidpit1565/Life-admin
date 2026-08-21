import XCTest
@testable import LifeAdminCore

private struct MockClient: AIExtracting {
    var result: Result<ExtractedItem, Error>
    private(set) var calls = 0
    func extract(from text: String) async throws -> ExtractedItem { try result.get() }
}
private struct Offline: ReachabilityChecking { let isNetworkAvailable = false }

final class AIServiceTests: XCTestCase {
    func testDeterministicParsingSucceedsWithoutGemini() async {
        let client = MockClient(result: .failure(AIExtractionError.unexpectedServerError))
        let service = LifeAdminAIService(client: client)
        let decision = await service.extract("My car insurance costs €840 and renews every March 18.")
        XCTAssertFalse(decision.usedAI)
        XCTAssertEqual(decision.item.title, "Car Insurance")
    }

    func testGeminiCalledOnlyWhenLocalParsingCannotHandleRequest() async {
        let ai = ExtractedItem(title: "Tax paperwork", category: .documents, amount: nil, currency: nil, date: nil, recurring: Recurrence.none, reminderOffsets: [30], confidence: 0.9)
        let service = LifeAdminAIService(client: MockClient(result: .success(ai)))
        let decision = await service.extract("That official letter from the city needs handling")
        XCTAssertTrue(decision.usedAI)
        XCTAssertEqual(decision.item.title, "Tax paperwork")
    }

    func testGenericDateSentenceEscalatesToGeminiInsteadOfGarbledTitle() async {
        // Regression: a sentence with a date but no recognized keyword used to get the local
        // parser's naive first-four-words title (e.g. "On the 24 august") reported at high
        // confidence, so the service never asked Gemini for a real title. Confirmed live
        // on-device: the original report used "rent", which the parser has since learned to
        // recognize (see testDayBeforeMonthDateResolvesEntirelyLocallyWhenKeywordIsRecognized
        // below) — this uses different, still-unrecognized wording to keep testing the same
        // regression: an unrecognized keyword must not get a falsely confident title.
        let ai = ExtractedItem(title: "Submit tax paperwork", category: .documents, amount: nil, currency: nil, date: nil, recurring: Recurrence.none, reminderOffsets: [30], confidence: 0.9)
        let service = LifeAdminAIService(client: MockClient(result: .success(ai)))
        let decision = await service.extract("On the 24 august I need to submit my tax paperwork")
        XCTAssertTrue(decision.usedAI)
        XCTAssertEqual(decision.item.title, "Submit tax paperwork")
    }

    func testDayBeforeMonthDateResolvesEntirelyLocallyWhenKeywordIsRecognized() async {
        // The exact input from the original live on-device bug report now resolves correctly and
        // entirely locally: simpleDate recognizes day-before-month order ("24 august", the normal
        // order outside the US) and "rent" is a recognized keyword, so no Gemini call is needed.
        let service = LifeAdminAIService(client: MockClient(result: .failure(AIExtractionError.unexpectedServerError)))
        let decision = await service.extract("On the 24 august I pay my rent each month")
        XCTAssertFalse(decision.usedAI)
        XCTAssertEqual(decision.item.title, "Rent")
        XCTAssertEqual(decision.item.category, .bills)
        XCTAssertNotNil(decision.item.date)
    }

    func testHighStakesAmountGetsASecondOpinionEvenWhenLocalParsingLooksConfident() async {
        // A wrong guess on a large insurance bill costs more than a wrong guess on a trivial
        // reminder, so this category+amount combination always gets a Gemini double-check, even
        // though the local parser recognizes "car insurance" and reports high confidence.
        let ai = ExtractedItem(title: "Car Insurance Renewal", category: .insurance, amount: 840, currency: "EUR", date: nil, recurring: Recurrence.yearly, reminderOffsets: [30], confidence: 0.95)
        let service = LifeAdminAIService(client: MockClient(result: .success(ai)))
        let decision = await service.extract("My car insurance costs €840 and renews every March 18.")
        XCTAssertTrue(decision.usedAI)
        XCTAssertEqual(decision.item.title, "Car Insurance Renewal")
    }

    func testLowValueInsuranceItemStaysLocalWithoutExtraScrutiny() async {
        let client = MockClient(result: .failure(AIExtractionError.unexpectedServerError))
        let service = LifeAdminAIService(client: client)
        let decision = await service.extract("My car insurance costs $50 and renews every March 18.")
        XCTAssertFalse(decision.usedAI)
        XCTAssertEqual(decision.item.title, "Car Insurance")
    }

    func testExtractLocalOnlyNeverCallsGeminiEvenForHighStakesText() {
        let service = LifeAdminAIService(client: MockClient(result: .success(ExtractedItem(title: "Should not be used", category: .insurance, amount: 9000, currency: "EUR", date: nil, recurring: Recurrence.none, reminderOffsets: nil, confidence: 0.99))))
        let decision = service.extractLocalOnly("My car insurance costs €9000 and renews every March 18.")
        XCTAssertFalse(decision.usedAI)
        XCTAssertEqual(decision.item.title, "Car Insurance")
    }

    func testValidGeminiStructuredJSONAccepted() throws {
        let data = #"{"title":"Passport","category":"travel","currency":"USD","confidence":0.91}"#.data(using: .utf8)!
        XCTAssertEqual(try AIJSONValidator().decode(data).category, .travel)
    }

    func testMalformedGeminiJSONRejectedSafely() {
        XCTAssertThrowsError(try AIJSONValidator().decode(Data("not json".utf8)))
    }

    func testRateLimitFallback() async {
        let service = LifeAdminAIService(client: MockClient(result: .failure(AIExtractionError.rateLimited)))
        let decision = await service.extract("ambiguous renewal thing")
        XCTAssertFalse(decision.usedAI)
        XCTAssertEqual(decision.fallbackReason, .rateLimited)
    }

    func testTimeoutFallback() async {
        let service = LifeAdminAIService(client: MockClient(result: .failure(AIExtractionError.timeout)))
        let decision = await service.extract("ambiguous renewal thing")
        XCTAssertEqual(decision.fallbackReason, .timeout)
    }

    func testNetworkFailureHandling() async {
        let service = LifeAdminAIService(client: MockClient(result: .failure(AIExtractionError.networkUnavailable)))
        let decision = await service.extract("ambiguous renewal thing")
        XCTAssertEqual(decision.fallbackReason, .networkUnavailable)
    }

    func testUnavailableGeminiHandling() async {
        let service = LifeAdminAIService(client: MockClient(result: .failure(AIExtractionError.serviceUnavailable)))
        let decision = await service.extract("ambiguous renewal thing")
        XCTAssertEqual(decision.fallbackReason, .serviceUnavailable)
    }

    func testOfflineFallbackSkipsAI() async {
        let service = LifeAdminAIService(client: MockClient(result: .failure(AIExtractionError.unexpectedServerError)), reachability: Offline())
        let decision = await service.extract("ambiguous renewal thing")
        XCTAssertFalse(decision.usedAI)
        XCTAssertEqual(decision.fallbackReason, .networkUnavailable)
    }

    func testInvalidStructuredOutputRejected() throws {
        let service = LifeAdminAIService(client: MockClient(result: .failure(AIExtractionError.unexpectedServerError)))
        XCTAssertThrowsError(try service.validateStructuredExtraction(ExtractedItem(title: "X", category: .other, amount: nil, currency: "BAD", date: nil, recurring: Recurrence.none, reminderOffsets: nil, confidence: 0.8)))
    }

    func testNoAPIKeyInClientCodeContract() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: "Sources/LifeAdminCore")
        let swiftFiles = files.filter { $0.hasSuffix(".swift") }
        for file in swiftFiles {
            let content = try String(contentsOfFile: "Sources/LifeAdminCore/\(file)")
            XCTAssertFalse(content.contains("AI" + "za"))
        }
    }
}
