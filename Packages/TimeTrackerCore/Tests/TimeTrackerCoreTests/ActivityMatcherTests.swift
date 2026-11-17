import XCTest
@testable import TimeTrackerCore

final class ActivityMatcherTests: XCTestCase {
    func testArticleAndPluralDifferences() {
        XCTAssertEqual(ActivityMatcher.bestMatch(for: "the dishes", in: ["Dishes"]), 0)
        XCTAssertEqual(ActivityMatcher.bestMatch(for: "dish", in: ["Dishes"]), 0)
    }

    func testPicksTheRightOneAmongSeveral() {
        let running = ["Laundry", "Dishes", "Homework"]
        XCTAssertEqual(ActivityMatcher.bestMatch(for: "dishes", in: running), 1)
        XCTAssertEqual(ActivityMatcher.bestMatch(for: "the laundry", in: running), 0)
        XCTAssertEqual(ActivityMatcher.bestMatch(for: "homework", in: running), 2)
    }

    func testPartialWordsMatch() {
        XCTAssertEqual(ActivityMatcher.bestMatch(for: "washing", in: ["Washing the car", "Dishes"]), 0)
        XCTAssertEqual(ActivityMatcher.bestMatch(for: "car", in: ["Dishes", "Washing the car"]), 1)
        XCTAssertEqual(ActivityMatcher.bestMatch(for: "cooking", in: ["Cooking dinner"]), 0)
    }

    func testSmallSpeechRecognitionErrors() {
        XCTAssertEqual(ActivityMatcher.bestMatch(for: "laundree", in: ["Dishes", "Laundry"]), 1)
        XCTAssertEqual(ActivityMatcher.bestMatch(for: "vacuuming", in: ["Vacumming"]), 0)
    }

    func testUnrelatedTextDoesNotMatch() {
        XCTAssertNil(ActivityMatcher.bestMatch(for: "taxes", in: ["Dishes", "Laundry"]))
        XCTAssertNil(ActivityMatcher.bestMatch(for: "walk", in: ["Work"]))
    }

    func testTieGoesToFirstCandidate() {
        XCTAssertEqual(ActivityMatcher.bestMatch(for: "dishes", in: ["Dishes", "Dishes"]), 0)
    }

    func testScoreIsSymmetricForIdenticalKeys() {
        XCTAssertEqual(ActivityMatcher.score("The Dishes", "dishes"), 1)
    }

    func testStemmer() {
        XCTAssertEqual(ActivityMatcher.stem("dishes"), "dish")
        XCTAssertEqual(ActivityMatcher.stem("washing"), "wash")
        XCTAssertEqual(ActivityMatcher.stem("groceries"), "grocery")
        XCTAssertEqual(ActivityMatcher.stem("cat"), "cat")
    }
}
