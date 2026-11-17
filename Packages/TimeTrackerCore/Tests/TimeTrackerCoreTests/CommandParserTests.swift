import XCTest
@testable import TimeTrackerCore

final class CommandParserTests: XCTestCase {
    private func parse(_ text: String) -> [ParsedCommand] {
        CommandParser.parse(text)
    }

    // MARK: Start phrases

    func testStartingX() {
        XCTAssertEqual(parse("starting dishes"), [.start(activity: "dishes")])
    }

    func testStartX() {
        XCTAssertEqual(parse("Start laundry"), [.start(activity: "laundry")])
    }

    func testImDoingX() {
        XCTAssertEqual(parse("I'm doing homework"), [.start(activity: "homework")])
        XCTAssertEqual(parse("I am doing homework"), [.start(activity: "homework")])
        XCTAssertEqual(parse("Im doing homework"), [.start(activity: "homework")])
    }

    func testCurlyApostropheFromSpeechRecognizer() {
        XCTAssertEqual(parse("I\u{2019}m doing the dishes."), [.start(activity: "dishes")])
    }

    func testArticlesAndFillersAreStripped() {
        XCTAssertEqual(parse("Okay, um, starting the dishes now."), [.start(activity: "dishes")])
        XCTAssertEqual(parse("starting to do the laundry"), [.start(activity: "laundry")])
        XCTAssertEqual(parse("start my workout please"), [.start(activity: "workout")])
    }

    func testOtherStartVariants() {
        XCTAssertEqual(parse("I'm going to start cooking dinner"), [.start(activity: "cooking dinner")])
        XCTAssertEqual(parse("time for a walk"), [.start(activity: "walk")])
        XCTAssertEqual(parse("I'm working on taxes"), [.start(activity: "taxes")])
        XCTAssertEqual(parse("Doing yoga"), [.start(activity: "yoga")])
    }

    func testMultiWordActivityKeepsInnerWords() {
        XCTAssertEqual(parse("starting mac and cheese"), [.start(activity: "mac and cheese")])
        XCTAssertEqual(parse("starting folding the laundry"), [.start(activity: "folding the laundry")])
    }

    func testBareStartIsANote() {
        XCTAssertEqual(parse("start"), [.note("start")])
    }

    // MARK: Stop phrases

    func testDoneWithX() {
        XCTAssertEqual(parse("done with dishes"), [.stop(activity: "dishes")])
        XCTAssertEqual(parse("Done with the dishes."), [.stop(activity: "dishes")])
        XCTAssertEqual(parse("I'm done with the dishes"), [.stop(activity: "dishes")])
    }

    func testFinishedX() {
        XCTAssertEqual(parse("finished laundry"), [.stop(activity: "laundry")])
        XCTAssertEqual(parse("I finished the laundry"), [.stop(activity: "laundry")])
        XCTAssertEqual(parse("finished with laundry"), [.stop(activity: "laundry")])
    }

    func testStopX() {
        XCTAssertEqual(parse("stop dishes"), [.stop(activity: "dishes")])
        XCTAssertEqual(parse("stop doing the dishes"), [.stop(activity: "dishes")])
    }

    func testBareStopAndDone() {
        XCTAssertEqual(parse("stop"), [.stop(activity: nil)])
        XCTAssertEqual(parse("Stop."), [.stop(activity: nil)])
        XCTAssertEqual(parse("done"), [.stop(activity: nil)])
        XCTAssertEqual(parse("I'm done"), [.stop(activity: nil)])
        XCTAssertEqual(parse("all done!"), [.stop(activity: nil)])
        XCTAssertEqual(parse("okay stop it"), [.stop(activity: nil)])
        XCTAssertEqual(parse("stop the timer"), [.stop(activity: nil)])
        XCTAssertEqual(parse("finished"), [.stop(activity: nil)])
    }

    func testStopAll() {
        XCTAssertEqual(parse("stop everything"), [.stopAll])
        XCTAssertEqual(parse("I'm done for the day"), [.stopAll])
        XCTAssertEqual(parse("stop all timers"), [.stopAll])
    }

    func testSuffixDoneForms() {
        XCTAssertEqual(parse("dishes done"), [.stop(activity: "dishes")])
        XCTAssertEqual(parse("the dishes are done"), [.stop(activity: "dishes")])
        XCTAssertEqual(parse("laundry is finished"), [.stop(activity: "laundry")])
    }

    // MARK: Compound phrases

    func testStopThenStartWithAnd() {
        XCTAssertEqual(
            parse("done with dishes and starting laundry"),
            [.stop(activity: "dishes"), .start(activity: "laundry")]
        )
    }

    func testStopThenStartWithPunctuation() {
        XCTAssertEqual(
            parse("Finished the dishes. Now I'm doing laundry."),
            [.stop(activity: "dishes"), .start(activity: "laundry")]
        )
    }

    func testStopThenStartWithoutConnector() {
        XCTAssertEqual(
            parse("done with dishes starting laundry"),
            [.stop(activity: "dishes"), .start(activity: "laundry")]
        )
    }

    func testTwoStartsWithThen() {
        XCTAssertEqual(
            parse("start cooking and then start the laundry"),
            [.start(activity: "cooking"), .start(activity: "laundry")]
        )
    }

    // MARK: Notes

    func testUnparseableTextIsKeptVerbatim() {
        XCTAssertEqual(parse("The dog threw up on the rug"), [.note("The dog threw up on the rug")])
        XCTAssertEqual(parse("how long did the dishes take?"), [.note("how long did the dishes take?")])
    }

    func testEmptyTextProducesNothing() {
        XCTAssertEqual(parse("   "), [])
        XCTAssertEqual(parse(""), [])
    }

    func testMixedSentencesKeepTheNotePart() {
        XCTAssertEqual(
            parse("Starting dishes. Remember to buy soap."),
            [.start(activity: "dishes"), .note("remember to buy soap")]
        )
        XCTAssertEqual(
            parse("Remember the soap. Starting dishes"),
            [.note("remember the soap"), .start(activity: "dishes")]
        )
    }

    func testFillerOnlySentencesAreIgnored() {
        XCTAssertEqual(parse("Okay. Um. Starting dishes."), [.start(activity: "dishes")])
    }
}
