import XCTest
@testable import TimeTrackerCore

final class CommandResolverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func activity(_ name: String, minutesAgo: Double) -> RunningActivity {
        RunningActivity(id: UUID(), name: name, startedAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func resolve(_ text: String, running: [RunningActivity]) -> [PlannedAction] {
        CommandResolver.resolve(CommandParser.parse(text), running: running, rawText: text)
    }

    func testStartCreatesDisplayName() {
        XCTAssertEqual(resolve("starting the dishes", running: []), [.start(name: "Dishes")])
    }

    func testOverlappingStartsAreAllowed() {
        let laundry = activity("Laundry", minutesAgo: 10)
        XCTAssertEqual(resolve("starting dishes", running: [laundry]), [.start(name: "Dishes")])
    }

    func testStartingSomethingAlreadyRunningIsANoOp() {
        let dishes = activity("Dishes", minutesAgo: 5)
        XCTAssertEqual(resolve("starting the dishes", running: [dishes]), [.alreadyRunning(id: dishes.id)])
    }

    func testFuzzyStopMatchesRunningActivity() {
        let laundry = activity("Laundry", minutesAgo: 30)
        let dishes = activity("Dishes", minutesAgo: 20)
        XCTAssertEqual(resolve("done with the dishes", running: [laundry, dishes]), [.stop(id: dishes.id)])
        XCTAssertEqual(resolve("finished laundry", running: [laundry, dishes]), [.stop(id: laundry.id)])
    }

    func testBareStopStopsMostRecent() {
        let older = activity("Laundry", minutesAgo: 30)
        let newer = activity("Dishes", minutesAgo: 2)
        XCTAssertEqual(resolve("stop", running: [older, newer]), [.stop(id: newer.id)])
        XCTAssertEqual(resolve("done", running: [newer, older]), [.stop(id: newer.id)])
    }

    func testBareStopWithNothingRunning() {
        XCTAssertEqual(resolve("stop", running: []), [.nothingRunning])
    }

    func testStopAllStopsEverything() {
        let a = activity("Laundry", minutesAgo: 30)
        let b = activity("Dishes", minutesAgo: 2)
        XCTAssertEqual(resolve("stop everything", running: [a, b]), [.stop(id: b.id), .stop(id: a.id)])
    }

    func testUnmatchedStopKeepsTheText() {
        let dishes = activity("Dishes", minutesAgo: 2)
        XCTAssertEqual(
            resolve("done with taxes", running: [dishes]),
            [.noMatch(query: "taxes", text: "done with taxes")]
        )
    }

    func testStopListWithAnd() {
        let a = activity("Laundry", minutesAgo: 30)
        let b = activity("Dishes", minutesAgo: 2)
        XCTAssertEqual(resolve("done with dishes and laundry", running: [a, b]), [.stop(id: b.id), .stop(id: a.id)])
    }

    func testActivityNameContainingAndStillMatchesWhole() {
        let mac = activity("Mac and cheese", minutesAgo: 10)
        let dishes = activity("Dishes", minutesAgo: 2)
        XCTAssertEqual(resolve("done with the mac and cheese", running: [mac, dishes]), [.stop(id: mac.id)])
    }

    func testCompoundStopAndStart() {
        let dishes = activity("Dishes", minutesAgo: 20)
        XCTAssertEqual(
            resolve("done with dishes and starting laundry", running: [dishes]),
            [.stop(id: dishes.id), .start(name: "Laundry")]
        )
    }

    func testTwoBareStopsStopTwoDifferentActivities() {
        let a = activity("Laundry", minutesAgo: 30)
        let b = activity("Dishes", minutesAgo: 2)
        let actions = CommandResolver.resolve([.stop(activity: nil), .stop(activity: nil)], running: [a, b], rawText: "")
        XCTAssertEqual(actions, [.stop(id: b.id), .stop(id: a.id)])
    }

    func testNotePassesThrough() {
        XCTAssertEqual(resolve("buy more soap", running: []), [.note(text: "buy more soap")])
    }
}
