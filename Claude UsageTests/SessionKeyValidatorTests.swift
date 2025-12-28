//
//  SessionKeyValidatorTests.swift
//  Claude Usage Tests
//
//  Created on 2025-12-27.
//

import XCTest
@testable import Claude_Usage

final class SessionKeyValidatorTests: XCTestCase {

    var validator: SessionKeyValidator!

    override func setUp() {
        super.setUp()
        validator = SessionKeyValidator()
    }

    override func tearDown() {
        validator = nil
        super.tearDown()
    }

    // MARK: - Valid Session Key Tests

    func testValidSessionKey() {
        let validKey = "sk-ant-sid01-abcdefghijklmnopqrstuvwxyz1234567890"

        XCTAssertNoThrow(try validator.validate(validKey))
        XCTAssertTrue(validator.isValid(validKey))
    }

    func testValidSessionKeyWithUnderscores() {
        let validKey = "sk-ant-sid01_abcdefghijklmnopqrstuvwxyz_1234567890"

        XCTAssertNoThrow(try validator.validate(validKey))
    }

    func testValidSessionKeyWithHyphens() {
        let validKey = "sk-ant-sid01-abcd-efgh-ijkl-mnop-qrst"

        XCTAssertNoThrow(try validator.validate(validKey))
    }

    // MARK: - Empty/Whitespace Tests

    func testEmptySessionKey() {
        XCTAssertThrowsError(try validator.validate("")) { error in
            guard case SessionKeyValidationError.empty = error else {
                XCTFail("Expected empty error")
                return
            }
        }
    }

    func testWhitespaceOnlySessionKey() {
        XCTAssertThrowsError(try validator.validate("   ")) { error in
            guard case SessionKeyValidationError.empty = error else {
                XCTFail("Expected empty error")
                return
            }
        }
    }

    func testSessionKeyWithLeadingTrailingWhitespace() throws {
        let keyWithWhitespace = "  sk-ant-sid01-abcdefghijklmnopqrstuvwxyz  "

        // Should trim whitespace and validate
        XCTAssertNoThrow(try validator.validate(keyWithWhitespace))

        let sanitized = try validator.validate(keyWithWhitespace)
        XCTAssertFalse(sanitized.hasPrefix(" "))
        XCTAssertFalse(sanitized.hasSuffix(" "))
    }

    // MARK: - Prefix Tests

    func testInvalidPrefix() {
        let invalidKey = "invalid-prefix-abcdefghijklmnopqrstuvwxyz"

        XCTAssertThrowsError(try validator.validate(invalidKey)) { error in
            guard case SessionKeyValidationError.invalidPrefix = error else {
                XCTFail("Expected invalidPrefix error, got \(error)")
                return
            }
        }
    }

    func testMissingPrefix() {
        let invalidKey = "abcdefghijklmnopqrstuvwxyz1234567890"

        XCTAssertThrowsError(try validator.validate(invalidKey)) { error in
            guard case SessionKeyValidationError.invalidPrefix = error else {
                XCTFail("Expected invalidPrefix error")
                return
            }
        }
    }

    // MARK: - Length Tests

    func testTooShort() {
        let shortKey = "sk-ant-abc"

        XCTAssertThrowsError(try validator.validate(shortKey)) { error in
            guard case SessionKeyValidationError.tooShort = error else {
                XCTFail("Expected tooShort error")
                return
            }
        }
    }

    func testTooLong() {
        let longKey = "sk-ant-" + String(repeating: "a", count: 1000)

        XCTAssertThrowsError(try validator.validate(longKey)) { error in
            guard case SessionKeyValidationError.tooLong = error else {
                XCTFail("Expected tooLong error")
                return
            }
        }
    }

    // MARK: - Character Set Tests

    func testInvalidCharacters() {
        let invalidKey = "sk-ant-sid01-hello@world!#$%"

        XCTAssertThrowsError(try validator.validate(invalidKey)) { error in
            guard case SessionKeyValidationError.invalidCharacters = error else {
                XCTFail("Expected invalidCharacters error")
                return
            }
        }
    }

    func testInternalWhitespace() {
        let invalidKey = "sk-ant-sid01 abcd efgh"

        XCTAssertThrowsError(try validator.validate(invalidKey)) { error in
            guard case SessionKeyValidationError.containsWhitespace = error else {
                XCTFail("Expected containsWhitespace error")
                return
            }
        }
    }

    // MARK: - Security Tests

    func testNullBytes() {
        let invalidKey = "sk-ant-sid01-abc\0def"

        XCTAssertThrowsError(try validator.validate(invalidKey)) { error in
            guard case SessionKeyValidationError.potentiallyMalicious = error else {
                XCTFail("Expected potentiallyMalicious error")
                return
            }
        }
    }

    func testPathTraversal() {
        let invalidKey = "sk-ant-sid01-../etc/passwd"

        XCTAssertThrowsError(try validator.validate(invalidKey)) { error in
            guard case SessionKeyValidationError.potentiallyMalicious = error else {
                XCTFail("Expected potentiallyMalicious error")
                return
            }
        }
    }

    func testScriptInjection() {
        let invalidKey = "sk-ant-sid01-<script>alert('xss')</script>"

        XCTAssertThrowsError(try validator.validate(invalidKey)) { error in
            // Will fail on invalid characters first, which is fine
            XCTAssertTrue(error is SessionKeyValidationError)
        }
    }

    // MARK: - Format Tests

    func testValidFormat() {
        let validKey = "sk-ant-sid01-abc-def-ghi-jkl"

        XCTAssertNoThrow(try validator.validate(validKey))
    }

    func testInvalidFormatNoSeparators() {
        let invalidKey = "sk-ant-abcdefghijklmnopqrstuvwxyz"

        XCTAssertThrowsError(try validator.validate(invalidKey)) { error in
            guard case SessionKeyValidationError.invalidFormat = error else {
                XCTFail("Expected invalidFormat error")
                return
            }
        }
    }

    // MARK: - Relaxed Configuration Tests

    func testRelaxedConfiguration() {
        let relaxedValidator = SessionKeyValidator(configuration: .relaxed)
        let shortKey = "sk-ant-s-hort"  // Must have separator after prefix

        // Relaxed mode allows shorter keys
        XCTAssertNoThrow(try relaxedValidator.validate(shortKey))
    }

    // MARK: - Sanitization Tests

    func testSanitization() {
        let keyWithNewlines = "sk-ant-sid01-abcdefg\r\nhijklmn"
        let sanitized = validator.sanitizeForStorage(keyWithNewlines)

        XCTAssertFalse(sanitized.contains("\r"))
        XCTAssertFalse(sanitized.contains("\n"))
    }

    // MARK: - Validation Status Tests

    func testValidationStatusValid() {
        let validKey = "sk-ant-sid01-abcdefghijklmnopqrstuvwxyz"
        let status = validator.validationStatus(validKey)

        XCTAssertTrue(status.isValid)
        XCTAssertNil(status.errorMessage)
    }

    func testValidationStatusInvalid() {
        let invalidKey = "invalid-key"
        let status = validator.validationStatus(invalidKey)

        XCTAssertFalse(status.isValid)
        XCTAssertNotNil(status.errorMessage)
    }

    // MARK: - Result Type Tests

    func testValidateResultSuccess() {
        let validKey = "sk-ant-sid01-abcdefghijklmnopqrstuvwxyz"
        let result = validator.validateResult(validKey)

        switch result {
        case .success(let sanitizedKey):
            XCTAssertEqual(sanitizedKey, validKey)
        case .failure:
            XCTFail("Expected success")
        }
    }

    func testValidateResultFailure() {
        let invalidKey = "invalid"
        let result = validator.validateResult(invalidKey)

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error is SessionKeyValidationError)
        }
    }

    // MARK: - String Extension Tests

    func testStringExtensionValid() {
        let validKey = "sk-ant-sid01-abcdefghijklmnopqrstuvwxyz"

        XCTAssertTrue(validKey.isValidSessionKey)
        XCTAssertNoThrow(try validKey.validateAsSessionKey())
    }

    func testStringExtensionInvalid() {
        let invalidKey = "invalid-key"

        XCTAssertFalse(invalidKey.isValidSessionKey)
        XCTAssertThrowsError(try invalidKey.validateAsSessionKey())
    }

    // MARK: - Edge Cases

    func testMixedCasePrefix() {
        let mixedCaseKey = "SK-ANT-sid01-abcdefghijklmnopqrstuvwxyz"

        // Should fail - prefix is case-sensitive
        XCTAssertThrowsError(try validator.validate(mixedCaseKey))
    }

    func testUnicodeCharacters() {
        let unicodeKey = "sk-ant-sid01-héllo-wörld"

        // Should fail - only ASCII allowed
        XCTAssertThrowsError(try validator.validate(unicodeKey))
    }

    // MARK: - Error Messages Tests

    func testErrorMessages() {
        let testCases: [(key: String, expectedErrorType: SessionKeyValidationError.Type)] = [
            ("", SessionKeyValidationError.self),
            ("sk-ant-", SessionKeyValidationError.self),
            ("invalid", SessionKeyValidationError.self)
        ]

        for testCase in testCases {
            XCTAssertThrowsError(try validator.validate(testCase.key)) { error in
                XCTAssertTrue(error is SessionKeyValidationError)

                // Verify error has a localized description
                let localizedError = error as? LocalizedError
                XCTAssertNotNil(localizedError?.errorDescription)
            }
        }
    }

    func testRecoverySuggestions() {
        XCTAssertThrowsError(try validator.validate("")) { error in
            let localizedError = error as? LocalizedError
            XCTAssertNotNil(localizedError?.recoverySuggestion)
        }
    }

    // MARK: - Performance Tests

    func testValidationPerformance() {
        let validKey = "sk-ant-sid01-abcdefghijklmnopqrstuvwxyz1234567890"

        measure {
            for _ in 0..<1000 {
                _ = validator.isValid(validKey)
            }
        }
    }

    func testSanitizationPerformance() {
        let keyWithIssues = "  sk-ant-sid01-abcdefghijklmnopqrstuvwxyz\r\n  "

        measure {
            for _ in 0..<1000 {
                _ = validator.sanitizeForStorage(keyWithIssues)
            }
        }
    }

    // MARK: - Real-world Scenarios

    func testTypicalUserInput() {
        // Simulate user copying from browser with potential whitespace
        let copiedKey = """
        sk-ant-sid01-abcdefghijklmnopqrstuvwxyz1234567890-ABCDEFG
        """

        XCTAssertNoThrow(try validator.validate(copiedKey))
    }

    func testTypicalMistakes() {
        let mistakes = [
            "sk-ant",  // Too short
            "sk ant sid01 abcd",  // Spaces instead of hyphens
            "sessionKey=sk-ant-sid01-abcd"  // Copied the whole cookie line
        ]

        for mistake in mistakes {
            XCTAssertThrowsError(try validator.validate(mistake))
            XCTAssertFalse(validator.isValid(mistake))
        }
    }
}
