import Foundation

// The optional language-model layer. The deterministic parser stays the source of truth; the LLM
// sorts finished activities into categories, re-reads transcripts the parser couldn't handle,
// suggests stop times for forgotten timers, and writes summaries. Only activity text, times and
// categories are sent, never audio.

public protocol LLMService: Sendable {
    /// Whether the service can be called (an API key is present).
    var isConfigured: Bool { get }

    /// A tiny request that verifies the API key and connectivity.
    func testConnection() async throws

    /// Returns a category for each activity, keyed by `CategoryKey.normalize(activity)`.
    func categorize(_ request: CategorizationRequest) async throws -> [String: String]

    /// Re-reads a transcript the local parser couldn't handle confidently.
    func interpret(_ request: InterpretationRequest) async throws -> InterpretationResult

    /// Suggests when a probably-forgotten activity really ended. `nil` if there's no good guess.
    func suggestStop(_ request: StopSuggestionRequest) async throws -> StopSuggestion?

    /// A short, warm, plain-language note about a day or week.
    func summarize(_ request: SummaryRequest) async throws -> String
}

// MARK: - Errors

public enum LLMServiceError: Error, Equatable, Sendable {
    case notConfigured
    case invalidAPIKey
    case rateLimited(retryAfter: TimeInterval?)
    case overloaded
    case server(status: Int)
    case badRequest(String)
    case network(String)
    case refused
    case truncated
    case invalidResponse(String)

    /// Worth retrying later (offline, rate limits, server trouble).
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded, .server, .network, .truncated: true
        case .notConfigured, .invalidAPIKey, .badRequest, .refused, .invalidResponse: false
        }
    }

    public var userMessage: String {
        switch self {
        case .notConfigured: "No API key saved."
        case .invalidAPIKey: "That key didn\u{2019}t work. Check it and try again."
        case .rateLimited: "Anthropic is rate-limiting requests. It will retry later."
        case .overloaded: "Anthropic is busy right now. It will retry later."
        case .server(let status): "Anthropic had a problem (\(status)). It will retry later."
        case .badRequest(let message): "The request was rejected: \(message)"
        case .network: "Can\u{2019}t reach Anthropic. Check the internet connection."
        case .refused: "The model declined to answer."
        case .truncated: "The answer was cut off. It will retry later."
        case .invalidResponse: "The answer couldn\u{2019}t be read."
        }
    }
}

// MARK: - Categories

public enum CategoryDefaults {
    /// Starting vocabulary, so categories are sensible with no setup.
    public static let names = [
        "Chores", "Cooking", "Kids", "Errands", "Work", "Self-care", "Exercise", "Social", "Rest", "Other",
    ]
    public static let uncategorized = "Uncategorized"
}

public enum CategoryKey {
    /// Cache key for an activity name: "The Dishes", "dishes" and "dish" share one key.
    public static func normalize(_ activity: String) -> String {
        ActivityMatcher.keyTokens(activity).joined(separator: " ")
    }

    /// Tidies a category name returned by the model; reuses an existing name when it differs only by case or spacing.
    public static func canonical(_ category: String, existing: [String]) -> String? {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "-&"))))
        guard !trimmed.isEmpty, trimmed.count <= 30 else { return nil }
        let folded = fold(trimmed)
        if let match = existing.first(where: { fold($0) == folded }) {
            return match
        }
        return TextNormalizer.displayName(trimmed)
    }

    private static func fold(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

public struct CategorizationRequest: Sendable, Equatable {
    public let activities: [String]
    public let existingCategories: [String]

    public init(activities: [String], existingCategories: [String]) {
        self.activities = activities
        self.existingCategories = existingCategories
    }
}

// MARK: - Interpretation

public struct LLMRunningActivity: Sendable, Equatable {
    /// Short opaque id the model echoes back ("r1"); never a database id.
    public let ref: String
    public let name: String
    public let startedAt: Date

    public init(ref: String, name: String, startedAt: Date) {
        self.ref = ref
        self.name = name
        self.startedAt = startedAt
    }
}

public struct InterpretationRequest: Sendable, Equatable {
    public let transcript: String
    public let running: [LLMRunningActivity]
    public let spokenAt: Date

    public init(transcript: String, running: [LLMRunningActivity], spokenAt: Date) {
        self.transcript = transcript
        self.running = running
        self.spokenAt = spokenAt
    }
}

public enum InterpretedEvent: Sendable, Equatable {
    case start(activity: String, minutesAgo: Int)
    case stop(ref: String)
    case note(String)
}

public struct InterpretationResult: Sendable, Equatable {
    public let events: [InterpretedEvent]
    public let confidence: Double

    public init(events: [InterpretedEvent], confidence: Double) {
        self.events = events
        self.confidence = confidence
    }

    /// Below this the local result is left alone.
    public static let minimumConfidence = 0.6
}

// MARK: - Stop suggestions

public struct PastSession: Sendable, Equatable {
    public let startedAt: Date
    public let minutes: Int

    public init(startedAt: Date, minutes: Int) {
        self.startedAt = startedAt
        self.minutes = minutes
    }
}

public struct StopSuggestionRequest: Sendable, Equatable {
    public let activity: String
    public let category: String?
    public let startedAt: Date
    public let now: Date
    public let typicalMinutes: Int?
    public let history: [PastSession]
    /// Things she started after this one, which hint at when it really ended.
    public let laterActivities: [PastSession]

    public init(
        activity: String, category: String?, startedAt: Date, now: Date, typicalMinutes: Int?,
        history: [PastSession], laterActivities: [PastSession] = []
    ) {
        self.activity = activity
        self.category = category
        self.startedAt = startedAt
        self.now = now
        self.typicalMinutes = typicalMinutes
        self.history = history
        self.laterActivities = laterActivities
    }
}

public struct StopSuggestion: Sendable, Equatable {
    public let endedAt: Date
    public let reason: String

    public init(endedAt: Date, reason: String) {
        self.endedAt = endedAt
        self.reason = reason
    }
}

// MARK: - Summaries

public struct SummaryRequest: Sendable, Equatable {
    public let period: SummaryPeriod
    public let periodLabel: String
    public let totals: [CategoryTotal]
    public let topActivities: [ActivityTotal]

    public init(period: SummaryPeriod, periodLabel: String, totals: [CategoryTotal], topActivities: [ActivityTotal]) {
        self.period = period
        self.periodLabel = periodLabel
        self.totals = totals
        self.topActivities = topActivities
    }
}

public enum SummaryPeriod: String, Sendable, CaseIterable {
    case day
    case week
}

/// Used when AI is off or no key is configured. Every call fails with `.notConfigured`.
public struct DisabledLLMService: LLMService {
    public init() {}

    public var isConfigured: Bool { false }
    public func testConnection() async throws { throw LLMServiceError.notConfigured }
    public func categorize(_ request: CategorizationRequest) async throws -> [String: String] { throw LLMServiceError.notConfigured }
    public func interpret(_ request: InterpretationRequest) async throws -> InterpretationResult { throw LLMServiceError.notConfigured }
    public func suggestStop(_ request: StopSuggestionRequest) async throws -> StopSuggestion? { throw LLMServiceError.notConfigured }
    public func summarize(_ request: SummaryRequest) async throws -> String { throw LLMServiceError.notConfigured }
}
