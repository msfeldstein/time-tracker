import Foundation
import XCTest
import TimeTrackerCore

final class LLMPromptsTests: XCTestCase {
    private let prompts = LLMPrompts(timeZone: TimeZone(identifier: "UTC")!)
    // Tue 2027-01-05 14:00 UTC
    private let now = Date(timeIntervalSince1970: 1_799_157_600)

    func testCategorizationPromptListsActivitiesAndExistingCategories() {
        let prompt = prompts.categorize(CategorizationRequest(activities: ["Dishes", "Pick up kids"], existingCategories: ["Chores", "Kids", "Garden"]))
        XCTAssertTrue(prompt.user.contains("Existing categories: Chores, Kids, Garden"))
        XCTAssertTrue(prompt.user.contains("- Dishes\n- Pick up kids"))
        XCTAssertTrue(prompt.system.contains("Reuse one of the existing categories"))
        XCTAssertEqual(prompt.schema, LLMPrompts.categorizationSchema)
    }

    func testCategorizationFallsBackToDefaultVocabulary() {
        let prompt = prompts.categorize(CategorizationRequest(activities: ["Dishes"], existingCategories: []))
        XCTAssertTrue(prompt.user.contains("Chores, Cooking, Kids, Errands, Work, Self-care"))
    }

    func testInterpretationPromptContainsOnlyRefsNamesAndTimes() {
        let laundryID = UUID()
        let prompt = prompts.interpret(InterpretationRequest(
            transcript: "ok so the washing thing is done\nand now kids",
            running: [LLMRunningActivity(ref: "r1", name: "Laundry", startedAt: now.addingTimeInterval(-3600))],
            spokenAt: now
        ))
        XCTAssertTrue(prompt.user.contains("Spoken at: Tue 2027-01-05 14:00 (time zone "))
        XCTAssertTrue(prompt.user.contains("- r1: Laundry (started 13:00)"))
        XCTAssertTrue(prompt.user.contains("\u{201C}ok so the washing thing is done and now kids\u{201D}"))
        XCTAssertFalse(prompt.user.contains(laundryID.uuidString))
        XCTAssertEqual(prompt.schema, LLMPrompts.interpretationSchema)
    }

    func testInterpretationPromptWithNothingRunning() {
        let prompt = prompts.interpret(InterpretationRequest(transcript: "hmm", running: [], spokenAt: now))
        XCTAssertTrue(prompt.user.contains("Running activities: none"))
    }

    func testStopSuggestionPromptIncludesHistory() {
        let prompt = prompts.suggestStop(StopSuggestionRequest(
            activity: "Vacuuming", category: "Chores",
            startedAt: now.addingTimeInterval(-4 * 3600), now: now, typicalMinutes: 30,
            history: [PastSession(startedAt: now.addingTimeInterval(-86400), minutes: 25)],
            laterActivities: [PastSession(startedAt: now.addingTimeInterval(-3 * 3600), minutes: 40)]
        ))
        XCTAssertTrue(prompt.user.contains("Activity: Vacuuming (category: Chores)"))
        XCTAssertTrue(prompt.user.contains("Started: Tue 2027-01-05 10:00"))
        XCTAssertTrue(prompt.user.contains("240 minutes so far"))
        XCTAssertTrue(prompt.user.contains("Usual length: about 30 minutes"))
        XCTAssertTrue(prompt.user.contains("- Mon 2027-01-04 14:00, 25 min"))
        XCTAssertTrue(prompt.user.contains("Started after it:\n- 11:00, 40 min"))
    }

    func testSummaryPrompt() {
        let prompt = prompts.summarize(SummaryRequest(
            period: .day, periodLabel: "Today, Tuesday Jan 5",
            totals: [CategoryTotal(category: "Chores", seconds: 3900)],
            topActivities: [ActivityTotal(name: "Dishes", category: "Chores", seconds: 2700, sessions: 2)]
        ))
        XCTAssertTrue(prompt.user.contains("Period: Today, Tuesday Jan 5"))
        XCTAssertTrue(prompt.user.contains("- Chores: 1h 05m"))
        XCTAssertTrue(prompt.user.contains("- Dishes (Chores): 45m, 2 times"))
        XCTAssertTrue(prompt.system.contains("warm"))
    }

    func testSchemasAreStrict() {
        for schema in [LLMPrompts.categorizationSchema, LLMPrompts.interpretationSchema, LLMPrompts.stopSuggestionSchema, LLMPrompts.summarySchema] {
            assertStrict(schema)
        }
    }

    func testInterpretationSchemaShape() {
        let event = LLMPrompts.interpretationSchema["properties"]?["events"]?["items"]
        XCTAssertEqual(event?["properties"]?["type"]?["enum"], ["start", "stop", "note"])
        XCTAssertEqual(event?["required"], ["minutes_ago", "ref", "text", "type"])
    }

    /// Every object closes additionalProperties and requires all of its properties
    /// (the API's structured outputs need the former; the latter keeps the grammar simple).
    private func assertStrict(_ schema: JSONValue, file: StaticString = #filePath, line: UInt = #line) {
        if schema["type"]?.stringValue == "object" {
            XCTAssertEqual(schema["additionalProperties"], .bool(false), file: file, line: line)
            guard case .object(let properties)? = schema["properties"] else { return XCTFail("No properties", file: file, line: line) }
            XCTAssertEqual(Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []), Set(properties.keys), file: file, line: line)
            properties.values.forEach { assertStrict($0, file: file, line: line) }
        }
        if let items = schema["items"] { assertStrict(items, file: file, line: line) }
        for unsupported in ["minimum", "maximum", "minLength", "maxLength"] {
            XCTAssertNil(schema[unsupported], file: file, line: line)
        }
    }
}
