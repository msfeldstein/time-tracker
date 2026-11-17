import Foundation
import TimeTrackerCore

/// The optional Claude Haiku layer. Everything works without it: no key or the toggle off
/// simply means the on-device parser, cached categories and local summaries are used.
enum AISettings {
    static let enabledKey = "aiEnabled"

    static var isEnabled: Bool {
        get { AppConfig.sharedDefaults.object(forKey: enabledKey) as? Bool ?? true }
        set { AppConfig.sharedDefaults.set(newValue, forKey: enabledKey) }
    }

    static var hasKey: Bool { AnthropicKey.load() != nil }

    /// AI work is attempted only when the toggle is on and a key is saved.
    static var isActive: Bool { isEnabled && hasKey }

    static let disclosure = "When on, activity names, times, categories and the words of unclear voice notes are sent to Anthropic. Never audio."
}

enum LLMServices {
    /// The service to use right now: Claude Haiku when AI is on and a key is saved, otherwise a no-op.
    static func current() -> any LLMService {
        AISettings.isActive ? claude() : DisabledLLMService()
    }

    /// Claude Haiku regardless of the toggle (used by "Test key").
    static func claude() -> any LLMService {
        AnthropicLLMService(client: AnthropicClient(apiKey: { AnthropicKey.load() }, transport: URLSessionTransport()))
    }
}
