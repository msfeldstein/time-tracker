import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TimeTrackerCore

/// Records requests and replies with canned responses; never touches the network.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Result<HTTPResponse, Error>]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Result<HTTPResponse, Error>]) {
        self.responses = responses
    }

    convenience init(answer text: String, stopReason: String = "end_turn", thinkingFirst: Bool = false) {
        self.init([.success(Self.messageResponse(text: text, stopReason: stopReason, thinkingFirst: thinkingFirst))])
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try lock.withLock {
            requests.append(request)
            guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
            return try responses.removeFirst().get()
        }
    }

    var lastBody: JSONValue? {
        lock.withLock {
            requests.last?.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        }
    }

    static func messageResponse(text: String, stopReason: String = "end_turn", thinkingFirst: Bool = false) -> HTTPResponse {
        var content: [JSONValue] = []
        if thinkingFirst {
            content.append(["type": "thinking", "thinking": "Let me think.", "signature": "abc"])
        }
        content.append(["type": "text", "text": .string(text)])
        let body: JSONValue = [
            "id": "msg_test", "type": "message", "role": "assistant", "model": .string(AnthropicConfig.model),
            "content": .array(content), "stop_reason": .string(stopReason),
            "usage": ["input_tokens": 10, "output_tokens": 5],
        ]
        return HTTPResponse(status: 200, body: try! JSONEncoder().encode(body))
    }

    static func error(status: Int, type: String, message: String, headers: [String: String] = [:]) -> HTTPResponse {
        let body: JSONValue = ["type": "error", "error": ["type": .string(type), "message": .string(message)]]
        return HTTPResponse(status: status, headers: headers, body: try! JSONEncoder().encode(body))
    }
}

func makeService(_ transport: MockTransport, key: String? = "sk-ant-test") -> AnthropicLLMService {
    AnthropicLLMService(
        client: AnthropicClient(apiKey: { key }, transport: transport),
        prompts: LLMPrompts(timeZone: TimeZone(identifier: "UTC")!)
    )
}
