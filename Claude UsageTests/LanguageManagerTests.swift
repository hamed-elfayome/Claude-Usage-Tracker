import XCTest
@testable import Claude_Usage

final class LanguageManagerTests: XCTestCase {

    func testVietnameseCaseExists() {
        let vi = LanguageManager.SupportedLanguage(rawValue: "vi")
        XCTAssertNotNil(vi, "Vietnamese ('vi') should be a supported language")
    }

    func testVietnameseProperties() {
        guard let vi = LanguageManager.SupportedLanguage(rawValue: "vi") else {
            return XCTFail("Vietnamese case missing")
        }
        XCTAssertEqual(vi.code, "vi")
        XCTAssertEqual(vi.displayName, "Tiếng Việt")
        XCTAssertEqual(vi.englishName, "Vietnamese")
        XCTAssertEqual(vi.flag, "🇻🇳")
    }

    func testSupportedLanguageCountIs14() {
        XCTAssertEqual(LanguageManager.SupportedLanguage.allCases.count, 14)
    }
}
