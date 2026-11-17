import Foundation

// Milestone 2 seam: an optional language-model helper. The deterministic parser stays the
// source of truth; the LLM is only consulted for text the parser could not understand,
// for grouping activities into categories, and for written summaries.

public struct LLMEntryInput: Sendable, Equatable {
    public let name: String
    public let startedAt: Date
    public let endedAt: Date?

    public init(name: String, startedAt: Date, endedAt: Date?) {
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public enum SummaryPeriod: String, Sendable {
    case day
    case week
}

public enum LLMServiceError: Error, Equatable, Sendable {
    case notConfigured
    case notImplemented
}

public protocol LLMService: Sendable {
    /// Whether the service can be called (e.g. an API key is present).
    var isConfigured: Bool { get }

    /// Interprets a transcript the local parser could not handle.
    func interpret(transcript: String, runningActivities: [String]) async throws -> [ParsedCommand]

    /// Maps activity names to short category names ("Dishes" -> "Housework").
    func categorize(activityNames: [String]) async throws -> [String: String]

    /// A short, friendly written summary of a day or week.
    func summarize(entries: [LLMEntryInput], period: SummaryPeriod) async throws -> String
}

/// Used when no API key is configured. Every call fails with `.notConfigured`.
public struct DisabledLLMService: LLMService {
    public init() {}

    public var isConfigured: Bool { false }

    public func interpret(transcript: String, runningActivities: [String]) async throws -> [ParsedCommand] {
        throw LLMServiceError.notConfigured
    }

    public func categorize(activityNames: [String]) async throws -> [String: String] {
        throw LLMServiceError.notConfigured
    }

    public func summarize(entries: [LLMEntryInput], period: SummaryPeriod) async throws -> String {
        throw LLMServiceError.notConfigured
    }
}
