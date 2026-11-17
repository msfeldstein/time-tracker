import Foundation
import XCTest
import TimeTrackerCore

final class SummaryCalculatorTests: XCTestCase {
    private let dayStart = Date(timeIntervalSince1970: 1_799_107_200) // 2027-01-05 00:00 UTC
    private var day: DateInterval { DateInterval(start: dayStart, duration: 86400) }

    private func entry(_ name: String, _ category: String?, from: Double, to: Double?) -> SummaryEntry {
        SummaryEntry(name: name, category: category, startedAt: dayStart.addingTimeInterval(from * 3600), endedAt: to.map { dayStart.addingTimeInterval($0 * 3600) })
    }

    func testTotalsPerCategoryClippedToTheDay() {
        let entries = [
            entry("Dishes", "Chores", from: 9, to: 9.5),
            entry("Laundry", "Chores", from: 10, to: 11),
            entry("Night shift", "Work", from: -2, to: 1), // started yesterday
            entry("Mystery", nil, from: 12, to: 12.25),
        ]
        let totals = SummaryCalculator.categoryTotals(entries, in: day, now: dayStart.addingTimeInterval(20 * 3600))
        XCTAssertEqual(totals.map(\.category), ["Chores", "Work", CategoryDefaults.uncategorized])
        XCTAssertEqual(totals.map(\.minutes), [90, 60, 15])
    }

    func testRunningEntriesCountUntilNow() {
        let totals = SummaryCalculator.categoryTotals([entry("Homework", "Kids", from: 15, to: nil)], in: day, now: dayStart.addingTimeInterval(16 * 3600))
        XCTAssertEqual(totals.first?.minutes, 60)
    }

    func testActivityTotalsGroupByNormalizedName() {
        let entries = [entry("Dishes", "Chores", from: 9, to: 9.5), entry("the dishes", "Chores", from: 19, to: 19.25)]
        let activities = SummaryCalculator.activityTotals(entries, in: day, now: dayStart.addingTimeInterval(23 * 3600))
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.sessions, 2)
        XCTAssertEqual(activities.first?.minutes, 45)
    }

    func testFingerprintIgnoresRunningTimersAndSmallJitter() {
        let finished = [entry("Dishes", "Chores", from: 9, to: 9.5)]
        let base = SummaryCalculator.fingerprint(finished, in: day)
        XCTAssertEqual(base, SummaryCalculator.fingerprint(finished + [entry("Homework", "Kids", from: 15, to: nil)], in: day))
        XCTAssertEqual(base, SummaryCalculator.fingerprint([entry("Dishes", "Chores", from: 9, to: 9.51)], in: day))
        XCTAssertNotEqual(base, SummaryCalculator.fingerprint(finished + [entry("Walk", "Exercise", from: 7, to: 8)], in: day))
        XCTAssertNotEqual(base, SummaryCalculator.fingerprint([entry("Dishes", "Cooking", from: 9, to: 9.5)], in: day))
    }

    func testLocalNote() {
        XCTAssertEqual(SummaryCalculator.localNote(totals: [], period: .day), "Nothing tracked yet today.")
        let note = SummaryCalculator.localNote(totals: [CategoryTotal(category: "Chores", seconds: 5400), CategoryTotal(category: "Kids", seconds: 1800)], period: .week)
        XCTAssertEqual(note, "You tracked 2 hours this week, mostly chores (1h 30m).")
    }
}

final class StopSuggestionHeuristicsTests: XCTestCase {
    func testTypicalDurationIsTheMedian() {
        XCTAssertNil(StopSuggestionHeuristics.typicalDuration([600]))
        XCTAssertEqual(StopSuggestionHeuristics.typicalDuration([600, 1200, 6000]), 1200)
        XCTAssertEqual(StopSuggestionHeuristics.typicalDuration([600, 1200]), 900)
    }

    func testThresholds() {
        // No history: the 3 hour default.
        XCTAssertFalse(StopSuggestionHeuristics.looksForgotten(elapsed: 2.5 * 3600, typical: nil))
        XCTAssertTrue(StopSuggestionHeuristics.looksForgotten(elapsed: 3.1 * 3600, typical: nil))
        // A 20 minute habit looks forgotten after an hour.
        XCTAssertFalse(StopSuggestionHeuristics.looksForgotten(elapsed: 55 * 60, typical: 20 * 60))
        XCTAssertTrue(StopSuggestionHeuristics.looksForgotten(elapsed: 70 * 60, typical: 20 * 60))
        // Long activities get room, capped at 6 hours.
        XCTAssertEqual(StopSuggestionHeuristics.threshold(typical: 4 * 3600), 6 * 3600)
    }

    func testLocalSuggestionAndClamp() {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(5 * 3600)
        XCTAssertEqual(StopSuggestionHeuristics.localSuggestion(startedAt: start, typical: 1800, now: now), start.addingTimeInterval(1800))
        XCTAssertEqual(StopSuggestionHeuristics.localSuggestion(startedAt: start, typical: nil, now: now), start.addingTimeInterval(3600))
        XCTAssertEqual(StopSuggestionHeuristics.clamp(start, startedAt: start, now: now), start.addingTimeInterval(60))
        XCTAssertEqual(StopSuggestionHeuristics.clamp(now.addingTimeInterval(10), startedAt: start, now: now), now)
    }
}

final class CategoryKeyTests: XCTestCase {
    func testNormalizeSharesKeysForVariants() {
        XCTAssertEqual(CategoryKey.normalize("The Dishes"), CategoryKey.normalize("dishes"))
        XCTAssertEqual(CategoryKey.normalize("Dish"), CategoryKey.normalize("dishes"))
        XCTAssertNotEqual(CategoryKey.normalize("Dishes"), CategoryKey.normalize("Laundry"))
    }

    func testCanonicalReusesExistingSpelling() {
        XCTAssertEqual(CategoryKey.canonical("self care", existing: ["Self-care"]), "Self-care")
        XCTAssertEqual(CategoryKey.canonical("CHORES.", existing: ["Chores"]), "Chores")
        XCTAssertEqual(CategoryKey.canonical("garden", existing: ["Chores"]), "Garden")
        XCTAssertNil(CategoryKey.canonical("  ", existing: []))
    }
}

final class ResolverConfidenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func running(_ names: [String]) -> [RunningActivity] {
        names.enumerated().map { RunningActivity(id: UUID(), name: $1, startedAt: now.addingTimeInterval(Double(-$0 - 1) * 600)) }
    }

    func testClearMatchIsConfident() {
        let open = running(["Dishes", "Laundry"])
        let resolution = CommandResolver.resolveWithConfidence(CommandParser.parse("done with the dishes"), running: open, rawText: "")
        XCTAssertEqual(resolution.actions, [.stop(id: open[0].id)])
        XCTAssertTrue(resolution.lowConfidenceStops.isEmpty)
    }

    func testAmbiguousMatchIsLowConfidence() {
        let open = running(["Washing the car", "Car repair"])
        let resolution = CommandResolver.resolveWithConfidence(CommandParser.parse("done with the car"), running: open, rawText: "")
        XCTAssertEqual(resolution.actions.count, 1)
        XCTAssertEqual(resolution.lowConfidenceStops.count, 1)
    }

    func testBareStopIsNotLowConfidence() {
        let open = running(["Dishes", "Laundry"])
        XCTAssertTrue(CommandResolver.resolveWithConfidence([.stop(activity: nil)], running: open, rawText: "").lowConfidenceStops.isEmpty)
    }
}
