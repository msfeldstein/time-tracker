import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import TimeTrackerCore

final class AnthropicClientTests: XCTestCase {
    func testRequestHeadersAndBody() async throws {
        let transport = MockTransport(answer: #"{"ok": true}"#)
        try await makeService(transport).testConnection()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url, AnthropicConfig.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), AnthropicConfig.apiVersion)
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")

        let body = try XCTUnwrap(transport.lastBody)
        XCTAssertEqual(body["model"]?.stringValue, "claude-haiku-5-5")
        XCTAssertEqual(body["max_tokens"]?.intValue, 256)
        XCTAssertEqual(body["output_config"]?["effort"]?.stringValue, "low")
        XCTAssertEqual(body["output_config"]?["format"]?["type"]?.stringValue, "json_schema")
        XCTAssertEqual(body["output_config"]?["format"]?["schema"]?["additionalProperties"], .bool(false))
        XCTAssertEqual(body["messages"]?.arrayValue?.first?["role"]?.stringValue, "user")
        XCTAssertNotNil(body["system"]?.stringValue)
        // Removed in API version 2026-10-21; sending them is a 400.
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["top_p"])
    }

    func testModelIdIsTheSingleConstant() {
        XCTAssertEqual(AnthropicConfig.model, "claude-haiku-5-5")
    }

    func testNoKeyNeverHitsTheNetwork() async {
        let transport = MockTransport(answer: #"{"ok": true}"#)
        await assertThrows(LLMServiceError.notConfigured) { try await makeService(transport, key: nil).testConnection() }
        await assertThrows(LLMServiceError.notConfigured) { try await makeService(transport, key: "").testConnection() }
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertFalse(makeService(transport, key: nil).isConfigured)
    }

    func testThinkingBlocksAreSkipped() async throws {
        let transport = MockTransport(answer: #"{"ok": true}"#, thinkingFirst: true)
        try await makeService(transport).testConnection()
    }

    func testErrorMapping() async {
        let cases: [(HTTPResponse, LLMServiceError)] = [
            (MockTransport.error(status: 401, type: "authentication_error", message: "invalid x-api-key"), .invalidAPIKey),
            (MockTransport.error(status: 429, type: "rate_limit_error", message: "slow down", headers: ["Retry-After": "12"]), .rateLimited(retryAfter: 12)),
            (MockTransport.error(status: 529, type: "overloaded_error", message: "busy"), .overloaded),
            (MockTransport.error(status: 500, type: "api_error", message: "oops"), .server(status: 500)),
            (MockTransport.error(status: 400, type: "invalid_request_error", message: "bad schema"), .badRequest("bad schema")),
        ]
        for (response, expected) in cases {
            let transport = MockTransport([.success(response)])
            await assertThrows(expected) { try await makeService(transport).testConnection() }
        }
    }

    func testRetryability() {
        XCTAssertTrue(LLMServiceError.rateLimited(retryAfter: nil).isRetryable)
        XCTAssertTrue(LLMServiceError.network("offline").isRetryable)
        XCTAssertTrue(LLMServiceError.overloaded.isRetryable)
        XCTAssertFalse(LLMServiceError.invalidAPIKey.isRetryable)
        XCTAssertFalse(LLMServiceError.badRequest("x").isRetryable)
    }

    func testTransportFailureBecomesNetworkError() async {
        let transport = MockTransport([.failure(URLError(.notConnectedToInternet))])
        do {
            try await makeService(transport).testConnection()
            XCTFail("Expected error")
        } catch let error as LLMServiceError {
            XCTAssertTrue(error.isRetryable)
            if case .network = error {} else { XCTFail("Expected network, got \(error)") }
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testRefusalAndTruncation() async {
        await assertThrows(LLMServiceError.refused) {
            try await makeService(MockTransport(answer: "I can't help", stopReason: "refusal")).testConnection()
        }
        await assertThrows(LLMServiceError.truncated) {
            try await makeService(MockTransport(answer: #"{"ok": tr"#, stopReason: "max_tokens")).testConnection()
        }
    }

    func testEndToEndCategorizeThroughMockedNetwork() async throws {
        let transport = MockTransport(answer: #"{"assignments":[{"activity":"Dishes","category":"Chores"},{"activity":"Pick up kids","category":"Kids"}]}"#)
        let result = try await makeService(transport).categorize(
            CategorizationRequest(activities: ["Dishes", "Pick up kids"], existingCategories: ["Chores", "Kids"])
        )
        XCTAssertEqual(result, [CategoryKey.normalize("Dishes"): "Chores", CategoryKey.normalize("Pick up kids"): "Kids"])
        let user = transport.lastBody?["messages"]?.arrayValue?.first?["content"]?.stringValue ?? ""
        XCTAssertTrue(user.contains("- Dishes"))
        XCTAssertTrue(user.contains("Existing categories: Chores, Kids"))
    }

    func testEmptyCategorizationSkipsTheCall() async throws {
        let transport = MockTransport([])
        let result = try await makeService(transport).categorize(CategorizationRequest(activities: [], existingCategories: []))
        XCTAssertEqual(result, [:])
        XCTAssertTrue(transport.requests.isEmpty)
    }
}

func assertThrows(
    _ expected: LLMServiceError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch let error as LLMServiceError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Unexpected \(error)", file: file, line: line)
    }
}
