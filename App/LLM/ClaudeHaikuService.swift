import Foundation
import TimeTrackerCore

/// Milestone 2: Anthropic Claude Haiku over the Messages API.
///
/// Not wired up yet. Every method checks for a key and then throws `.notImplemented`.
/// The API key comes only from the Keychain (entered in Settings); never hard-code one,
/// as this repository is public.
struct ClaudeHaikuService: LLMService {
    static let model = "claude-haiku-4-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"

    private let apiKey: @Sendable () -> String?

    init(apiKey: @escaping @Sendable () -> String? = { AnthropicKey.load() }) {
        self.apiKey = apiKey
    }

    var isConfigured: Bool { apiKey() != nil }

    func interpret(transcript: String, runningActivities: [String]) async throws -> [ParsedCommand] {
        try requireKey()
        throw LLMServiceError.notImplemented
    }

    func categorize(activityNames: [String]) async throws -> [String: String] {
        try requireKey()
        throw LLMServiceError.notImplemented
    }

    func summarize(entries: [LLMEntryInput], period: SummaryPeriod) async throws -> String {
        try requireKey()
        throw LLMServiceError.notImplemented
    }

    private func requireKey() throws {
        guard isConfigured else { throw LLMServiceError.notConfigured }
    }
}

enum LLMServices {
    /// The service the app should use right now.
    static func current() -> any LLMService {
        let claude = ClaudeHaikuService()
        return claude.isConfigured ? claude : DisabledLLMService()
    }
}
