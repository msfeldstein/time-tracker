import XCTest
import TimeTrackerCore

final class BundledAPIKeyTests: XCTestCase {
    func testEmptyAndMissingValuesAreIgnored() {
        XCTAssertNil(BundledAPIKey.sanitize(nil))
        XCTAssertNil(BundledAPIKey.sanitize(""))
        XCTAssertNil(BundledAPIKey.sanitize("   "))
        XCTAssertNil(BundledAPIKey.sanitize("\"\""))
    }

    func testUnexpandedBuildSettingIsIgnored() {
        XCTAssertNil(BundledAPIKey.sanitize("$(ANTHROPIC_API_KEY)"))
    }

    func testDashesAndUnderscoresSurvive() {
        XCTAssertEqual(BundledAPIKey.sanitize("sk-ant-fa_ke-Key_09"), "sk-ant-fa_ke-Key_09")
    }

    func testWhitespaceAndQuotesAreTrimmed() {
        XCTAssertEqual(BundledAPIKey.sanitize("  sk-ant-fake_key \n"), "sk-ant-fake_key")
        XCTAssertEqual(BundledAPIKey.sanitize("\"sk-ant-fake_key\""), "sk-ant-fake_key")
    }

    func testValuesWithInnerSpacesAreRejected() {
        XCTAssertNil(BundledAPIKey.sanitize("sk-ant fake"))
    }
}
