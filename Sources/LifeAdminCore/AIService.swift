import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AIExtractionError: Error, Equatable, LocalizedError, Sendable {
    case rateLimited
    case authenticationFailed
    case timeout
    case networkUnavailable
    case serviceUnavailable
    case malformedJSON
    case invalidStructuredOutput
    case emptyResponse
    case unexpectedServerError

    public var errorDescription: String? {
        switch self {
        case .rateLimited: return "AI is busy right now. You can continue manually."
        case .authenticationFailed: return "AI is not configured. You can continue manually."
        case .timeout: return "AI took too long. You can continue manually."
        case .networkUnavailable: return "AI is unavailable offline. You can continue manually."
        case .serviceUnavailable: return "AI is unavailable right now. You can continue manually."
        case .malformedJSON, .invalidStructuredOutput, .emptyResponse, .unexpectedServerError: return "AI could not understand this safely. You can continue manually."
        }
    }
}

public struct ExtractionDecision: Equatable, Sendable {
    public let item: ExtractedItem
    public let usedAI: Bool
    public let fallbackReason: AIExtractionError?
}

public protocol ReachabilityChecking: Sendable {
    var isNetworkAvailable: Bool { get }
}

public struct AlwaysOnlineReachability: ReachabilityChecking {
    public init() {}
    public var isNetworkAvailable: Bool { true }
}

public struct LifeAdminAIService: Sendable {
    public var parser: NaturalLanguageParser
    public var client: AIExtracting
    public var reachability: ReachabilityChecking
    public var confidenceThreshold: Double

    public init(
        parser: NaturalLanguageParser = NaturalLanguageParser(),
        client: AIExtracting,
        reachability: ReachabilityChecking = AlwaysOnlineReachability(),
        confidenceThreshold: Double = 0.80
    ) {
        self.parser = parser
        self.client = client
        self.reachability = reachability
        self.confidenceThreshold = confidenceThreshold
    }

    public func extract(_ text: String, now: Date = Date()) async -> ExtractionDecision {
        let local = parser.parse(text, now: now)
        if isCompleteEnough(local) && local.confidence >= confidenceThreshold {
            return ExtractionDecision(item: local, usedAI: false, fallbackReason: nil)
        }
        guard reachability.isNetworkAvailable else {
            return ExtractionDecision(item: local, usedAI: false, fallbackReason: .networkUnavailable)
        }
        do {
            let ai = try await client.extract(from: text)
            try validateStructuredExtraction(ai)
            return ExtractionDecision(item: ai, usedAI: true, fallbackReason: nil)
        } catch let error as AIExtractionError {
            return ExtractionDecision(item: local, usedAI: false, fallbackReason: error)
        } catch {
            return ExtractionDecision(item: local, usedAI: false, fallbackReason: .unexpectedServerError)
        }
    }

    public func isCompleteEnough(_ item: ExtractedItem) -> Bool {
        item.title?.isEmpty == false && item.category != nil && (item.date != nil || item.amount != nil || item.recurring != Recurrence.none)
    }

    public func validateStructuredExtraction(_ item: ExtractedItem) throws {
        if item.confidence < 0 || item.confidence > 1 { throw AIExtractionError.invalidStructuredOutput }
        if item.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { throw AIExtractionError.invalidStructuredOutput }
        if let currency = item.currency, Locale.commonISOCurrencyCodes.contains(currency.uppercased()) == false { throw AIExtractionError.invalidStructuredOutput }
    }
}

public struct ProxyAIClient: AIExtracting, Sendable {
    public let endpoint: URL
    public let timeoutSeconds: TimeInterval
    private let session: URLSession

    public init(endpoint: URL, timeoutSeconds: TimeInterval = 12, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.timeoutSeconds = timeoutSeconds
        self.session = session
    }

    public func extract(from text: String) async throws -> ExtractedItem {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["text": String(text.prefix(4000))])
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIExtractionError.unexpectedServerError }
            switch http.statusCode {
            case 200:
                guard data.isEmpty == false else { throw AIExtractionError.emptyResponse }
                do { return try AIJSONValidator().decode(data) } catch { throw AIExtractionError.malformedJSON }
            case 401, 403: throw AIExtractionError.authenticationFailed
            case 408: throw AIExtractionError.timeout
            case 429: throw AIExtractionError.rateLimited
            case 500, 502, 503, 504: throw AIExtractionError.serviceUnavailable
            default: throw AIExtractionError.unexpectedServerError
            }
        } catch let error as AIExtractionError {
            throw error
        } catch let error as URLError {
            if error.code == .timedOut { throw AIExtractionError.timeout }
            if [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost].contains(error.code) { throw AIExtractionError.networkUnavailable }
            throw AIExtractionError.unexpectedServerError
        }
    }
}
