import XCTest
@testable import TimeTrackerCore

final class DurationFormattingTests: XCTestCase {
    func testShort() {
        XCTAssertEqual(DurationFormatting.short(0), "0s")
        XCTAssertEqual(DurationFormatting.short(45), "45s")
        XCTAssertEqual(DurationFormatting.short(12 * 60 + 30), "12m")
        XCTAssertEqual(DurationFormatting.short(3600 + 5 * 60), "1h 05m")
        XCTAssertEqual(DurationFormatting.short(2 * 3600 + 45 * 60), "2h 45m")
        XCTAssertEqual(DurationFormatting.short(-10), "0s")
    }

    func testSpoken() {
        XCTAssertEqual(DurationFormatting.spoken(1), "1 second")
        XCTAssertEqual(DurationFormatting.spoken(60), "1 minute")
        XCTAssertEqual(DurationFormatting.spoken(3600 + 120), "1 hour 2 minutes")
    }

    func testForgotToStop() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(DurationFormatting.isProbablyForgotten(startedAt: start, endedAt: nil, now: start.addingTimeInterval(2 * 3600)))
        XCTAssertTrue(DurationFormatting.isProbablyForgotten(startedAt: start, endedAt: nil, now: start.addingTimeInterval(3 * 3600 + 1)))
        XCTAssertTrue(DurationFormatting.isProbablyForgotten(startedAt: start, endedAt: start.addingTimeInterval(4 * 3600)))
    }
}
