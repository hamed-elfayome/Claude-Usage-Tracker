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

    func testPersianCaseExists() {
        let fa = LanguageManager.SupportedLanguage(rawValue: "fa")
        XCTAssertNotNil(fa, "Persian ('fa') should be a supported language")
    }

    func testPersianProperties() {
        guard let fa = LanguageManager.SupportedLanguage(rawValue: "fa") else {
            return XCTFail("Persian case missing")
        }
        XCTAssertEqual(fa.code, "fa")
        XCTAssertEqual(fa.displayName, "فارسی")
        XCTAssertEqual(fa.englishName, "Persian")
        XCTAssertEqual(fa.flag, "🇮🇷")
    }

    func testSupportedLanguageCountIs15() {
        XCTAssertEqual(LanguageManager.SupportedLanguage.allCases.count, 15)
    }
}
