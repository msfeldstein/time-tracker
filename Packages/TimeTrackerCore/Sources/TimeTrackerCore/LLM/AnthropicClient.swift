import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AnthropicConfig {
    /// The one place the model is chosen. Current Claude Haiku per Anthropic's models overview.
    public static let model = "claude-haiku-5-5"
    public static let apiVersion = "2026-10-21"
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// Short, high-volume tasks: Anthropic recommends `low` effort for Haiku here.
    public static let effort = "low"
    public static let timeout: TimeInterval = 30
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Network seam so tests never touch the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

#if canImport(Darwin)
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(status: http?.statusCode ?? 0, headers: headers, body: data)
    }
}
#endif

/// Minimal Messages API client: one user turn, a system prompt, and a strict JSON output schema.
public struct AnthropicClient: Sendable {
    private let apiKey: @Sendable () -> String?
    private let transport: any HTTPTransport

    public init(apiKey: @escaping @Sendable () -> String?, transport: any HTTPTransport) {
        self.apiKey = apiKey
        self.transport = transport
    }

    public var hasKey: Bool { !(apiKey() ?? "").isEmpty }

    /// Sends the prompt and returns the JSON text of the first text block.
    public func complete(_ prompt: LLMPrompt) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw LLMServiceError.notConfigured }
        let request = try Self.makeRequest(prompt, apiKey: key)

        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as LLMServiceError {
            throw error
        } catch {
            throw LLMServiceError.network(String(describing: error))
        }
        return try Self.parse(response)
    }

    public static func makeRequest(_ prompt: LLMPrompt, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: AnthropicConfig.endpoint, timeoutInterval: AnthropicConfig.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AnthropicConfig.apiVersion, forHTTPHeaderField: "anthropic-version")
        let body: JSONValue = [
            "model": .string(AnthropicConfig.model),
            "max_tokens": .number(Double(prompt.maxTokens)),
            "system": .string(prompt.system),
            "messages": [["role": "user", "content": .string(prompt.user)]],
            "output_config": [
                "effort": .string(AnthropicConfig.effort),
                "format": ["type": "json_schema", "schema": prompt.schema],
            ],
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(body)
        return request
    }

    public static func parse(_ response: HTTPResponse) throws -> String {
        let json = try? JSONDecoder().decode(JSONValue.self, from: response.body)
        guard (200..<300).contains(response.status) else {
            let message = json?["error"]?["message"]?.stringValue ?? "HTTP \(response.status)"
            switch response.status {
            case 401, 403: throw LLMServiceError.invalidAPIKey
            case 429: throw LLMServiceError.rateLimited(retryAfter: response.header("retry-after").flatMap(TimeInterval.init))
            case 529: throw LLMServiceError.overloaded
            case 500...: throw LLMServiceError.server(status: response.status)
            case 408: throw LLMServiceError.network("Timed out")
            default: throw LLMServiceError.badRequest(message)
            }
        }
        guard let json else { throw LLMServiceError.invalidResponse("Body is not JSON") }
        switch json["stop_reason"]?.stringValue {
        case "refusal": throw LLMServiceError.refused
        case "max_tokens": throw LLMServiceError.truncated
        default: break
        }
        // Thinking blocks may come first; the answer is the first text block.
        let text = json["content"]?.arrayValue?
            .first { $0["type"]?.stringValue == "text" }?["text"]?.stringValue
        guard let text, !text.isEmpty else { throw LLMServiceError.invalidResponse("No text block") }
        return text
    }
}

/// `LLMService` backed by Claude Haiku via the Messages API.
public struct AnthropicLLMService: LLMService {
    private let client: AnthropicClient
    private let prompts: LLMPrompts

    public init(client: AnthropicClient, prompts: LLMPrompts = LLMPrompts()) {
        self.client = client
        self.prompts = prompts
    }

    public var isConfigured: Bool { client.hasKey }

    public func testConnection() async throws {
        try LLMResponseParser.testConnection(try await client.complete(prompts.testConnection()))
    }

    public func categorize(_ request: CategorizationRequest) async throws -> [String: String] {
        guard !request.activities.isEmpty else { return [:] }
        let text = try await client.complete(prompts.categorize(request))
        return try LLMResponseParser.categories(text, for: request)
    }

    public func interpret(_ request: InterpretationRequest) async throws -> InterpretationResult {
        let text = try await client.complete(prompts.interpret(request))
        return try LLMResponseParser.interpretation(text, for: request)
    }

    public func suggestStop(_ request: StopSuggestionRequest) async throws -> StopSuggestion? {
        let text = try await client.complete(prompts.suggestStop(request))
        return try LLMResponseParser.stopSuggestion(text, for: request)
    }

    public func summarize(_ request: SummaryRequest) async throws -> String {
        let text = try await client.complete(prompts.summarize(request))
        return try LLMResponseParser.summary(text)
    }
}
