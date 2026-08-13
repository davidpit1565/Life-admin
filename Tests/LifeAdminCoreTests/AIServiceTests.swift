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
