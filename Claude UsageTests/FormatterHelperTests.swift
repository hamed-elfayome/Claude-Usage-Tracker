import XCTest
@testable import Claude_Usage

final class FormatterHelperTests: XCTestCase {
    func testAbbreviatedCount() {
        XCTAssertEqual(FormatterHelper.abbreviatedCount(0), "0")
        XCTAssertEqual(FormatterHelper.abbreviatedCount(999), "999")
        XCTAssertEqual(FormatterHelper.abbreviatedCount(1_000), "1K")
        XCTAssertEqual(FormatterHelper.abbreviatedCount(1_500), "1.5K")
        XCTAssertEqual(FormatterHelper.abbreviatedCount(21_062_418), "21.1M")
        XCTAssertEqual(FormatterHelper.abbreviatedCount(10_000_000), "10M")
        XCTAssertEqual(FormatterHelper.abbreviatedCount(1_200_000_000), "1.2B")
    }
}
