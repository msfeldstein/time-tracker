import Foundation
import XCTest
import TimeTrackerCore

final class LLMResponseParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_799_157_600)

    // MARK: JSON extraction

    func testExtractsFencedAndWrappedJSON() throws {
        XCTAssertEqual(try LLMResponseParser.extractJSON("```json\n{\"ok\": true}\n```")["ok"], .bool(true))
        XCTAssertEqual(try LLMResponseParser.extractJSON("Sure! Here you go: {\"ok\": true} Hope that helps.")["ok"], .bool(true))
        XCTAssertThrowsError(try LLMResponseParser.extractJSON("no json here"))
    }

    // MARK: Categories

    private let categoryRequest = CategorizationRequest(activities: ["Dishes", "Pick up kids", "Groceries"], existingCategories: ["Chores", "Kids"])

    func testCategoriesStrictShape() throws {
        let text = #"{"assignments":[{"activity":"Dishes","category":"Chores"},{"activity":"Pick up kids","category":"Kids"},{"activity":"Groceries","category":"Errands"}]}"#
        let result = try LLMResponseParser.categories(text, for: categoryRequest)
        XCTAssertEqual(result[CategoryKey.normalize("Dishes")], "Chores")
        XCTAssertEqual(result[CategoryKey.normalize("Pick up kids")], "Kids")
        XCTAssertEqual(result[CategoryKey.normalize("Groceries")], "Errands")
    }

    func testCategoriesTolerantDecoding() throws {
        // Different casing of names and categories, a dictionary shape, and an unknown activity.
        let text = #"{"the dishes": "chores", "PICK UP KIDS": " kids ", "Taxes": "Work", "Groceries": "Uncategorized"}"#
        let result = try LLMResponseParser.categories(text, for: categoryRequest)
        XCTAssertEqual(result[CategoryKey.normalize("Dishes")], "Chores")
        XCTAssertEqual(result[CategoryKey.normalize("Pick up kids")], "Kids")
        XCTAssertEqual(result[CategoryKey.normalize("Groceries")], "Other")
        XCTAssertNil(result[CategoryKey.normalize("Taxes")])
        XCTAssertEqual(result.count, 3)
    }

    func testCategoriesNewCategoryIsTitleCased() throws {
        let result = try LLMResponseParser.categories(#"{"assignments":[{"activity":"Dishes","category":"house stuff"}]}"#, for: categoryRequest)
        XCTAssertEqual(result[CategoryKey.normalize("Dishes")], "House stuff")
    }

    func testCategoriesGarbageThrows() {
        XCTAssertThrowsError(try LLMResponseParser.categories(#"{"assignments":[]}"#, for: categoryRequest))
    }

    // MARK: Interpretation

    private var interpretationRequest: InterpretationRequest {
        InterpretationRequest(
            transcript: "the washing is out, now picking up the kids",
            running: [
                LLMRunningActivity(ref: "r1", name: "Laundry", startedAt: now.addingTimeInterval(-3600)),
                LLMRunningActivity(ref: "r2", name: "Dishes", startedAt: now.addingTimeInterval(-600)),
            ],
            spokenAt: now
        )
    }

    func testInterpretationStrictShape() throws {
        let text = #"{"events":[{"type":"stop","text":"","ref":"r1","minutes_ago":0},{"type":"start","text":"picking up the kids","ref":"","minutes_ago":0}],"confidence":0.85}"#
        let result = try LLMResponseParser.interpretation(text, for: interpretationRequest)
        XCTAssertEqual(result.events, [.stop(ref: "r1"), .start(activity: "picking up the kids", minutesAgo: 0)])
        XCTAssertEqual(result.confidence, 0.85)
    }

    func testInterpretationTolerantDecoding() throws {
        // Capitalised types, camelCase keys, string numbers, a stop by name, an unknown ref, a duplicate, and an empty note.
        let text = """
        ```json
        {"events":[
          {"type":"Stop","ref":"laundry"},
          {"type":"STOP","ref":"r9"},
          {"type":"Start","activity":"the school run","minutesAgo":"15"},
          {"type":"start","text":"the school run","minutes_ago":15},
          {"type":"note","text":""},
          {"type":"dance","text":"?"}
        ],"confidence":"1.7"}
        ```
        """
        let result = try LLMResponseParser.interpretation(text, for: interpretationRequest)
        XCTAssertEqual(result.events, [.stop(ref: "r1"), .start(activity: "school run", minutesAgo: 15)])
        XCTAssertEqual(result.confidence, 1)
    }

    func testInterpretationClampsMinutesAndDefaultsConfidence() throws {
        let result = try LLMResponseParser.interpretation(#"{"events":[{"type":"start","text":"nap","minutes_ago":-5}]}"#, for: interpretationRequest)
        XCTAssertEqual(result.events, [.start(activity: "nap", minutesAgo: 0)])
        XCTAssertEqual(result.confidence, 0.5)
    }

    func testInterpretationWithoutEventsThrows() {
        XCTAssertThrowsError(try LLMResponseParser.interpretation(#"{"confidence":1}"#, for: interpretationRequest))
    }

    // MARK: Stop suggestions

    private var stopRequest: StopSuggestionRequest {
        StopSuggestionRequest(activity: "Vacuuming", category: "Chores", startedAt: now.addingTimeInterval(-4 * 3600), now: now, typicalMinutes: 30, history: [])
    }

    func testStopSuggestion() throws {
        let suggestion = try LLMResponseParser.stopSuggestion(#"{"has_suggestion":true,"minutes_after_start":35,"reason":"You usually vacuum for about half an hour"}"#, for: stopRequest)
        XCTAssertEqual(suggestion?.endedAt, stopRequest.startedAt.addingTimeInterval(35 * 60))
        XCTAssertEqual(suggestion?.reason, "You usually vacuum for about half an hour")
    }

    func testStopSuggestionIsClampedToNow() throws {
        let suggestion = try LLMResponseParser.stopSuggestion(#"{"has_suggestion":true,"minutes_after_start":"999","reason":""}"#, for: stopRequest)
        XCTAssertEqual(suggestion?.endedAt, now)
        XCTAssertEqual(suggestion?.reason, "Based on how long it usually takes")
    }

    func testNoStopSuggestion() throws {
        XCTAssertNil(try LLMResponseParser.stopSuggestion(#"{"has_suggestion":false,"minutes_after_start":0,"reason":"no idea"}"#, for: stopRequest))
        XCTAssertNil(try LLMResponseParser.stopSuggestion(#"{"minutes_after_start":0}"#, for: stopRequest))
    }

    // MARK: Summary

    func testSummary() throws {
        XCTAssertEqual(try LLMResponseParser.summary(#"{"note":"  You got a lot done today.  "}"#), "You got a lot done today.")
        XCTAssertEqual(try LLMResponseParser.summary(#"{"summary":"Nice week."}"#), "Nice week.")
        XCTAssertEqual(try LLMResponseParser.summary("Plain prose without JSON."), "Plain prose without JSON.")
        XCTAssertThrowsError(try LLMResponseParser.summary(#"{"note":""}"#))
    }

    // MARK: Through the service with a mocked network

    func testInterpretThroughService() async throws {
        let transport = MockTransport(answer: #"{"events":[{"type":"stop","text":"","ref":"r2","minutes_ago":0}],"confidence":0.9}"#)
        let result = try await makeService(transport).interpret(interpretationRequest)
        XCTAssertEqual(result.events, [.stop(ref: "r2")])
        XCTAssertEqual(transport.lastBody?["output_config"]?["format"]?["schema"], LLMPrompts.interpretationSchema)
    }

    func testSummaryThroughService() async throws {
        let transport = MockTransport(answer: #"{"note":"A calm day."}"#)
        let note = try await makeService(transport).summarize(SummaryRequest(period: .week, periodLabel: "This week", totals: [], topActivities: []))
        XCTAssertEqual(note, "A calm day.")
    }

    func testDisabledServiceNeverCalls() async {
        await assertThrows(LLMServiceError.notConfigured) { _ = try await DisabledLLMService().summarize(SummaryRequest(period: .day, periodLabel: "", totals: [], topActivities: [])) }
    }
}
