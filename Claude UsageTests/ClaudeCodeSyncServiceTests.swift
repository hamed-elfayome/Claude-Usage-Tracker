import XCTest
@testable import Claude_Usage

final class ClaudeCodeSyncServiceTests: XCTestCase {

    private let service = ClaudeCodeSyncService.shared

    // MARK: - Token Expiry Normalization (ms vs s)

    func testIsTokenExpired_SecondsEpoch_Expired() {
        // expiresAt in seconds, 1 hour ago → expired
        let past = Date().addingTimeInterval(-3600).timeIntervalSince1970
        let json = makeCredentialsJSON(expiresAt: past)
        XCTAssertTrue(service.isTokenExpired(json))
    }

    func testIsTokenExpired_SecondsEpoch_Valid() {
        // expiresAt in seconds, 1 hour from now → valid
        let future = Date().addingTimeInterval(3600).timeIntervalSince1970
        let json = makeCredentialsJSON(expiresAt: future)
        XCTAssertFalse(service.isTokenExpired(json))
    }

    func testIsTokenExpired_MillisecondsEpoch_Expired() {
        // expiresAt in milliseconds, 1 hour ago → should normalize and detect as expired
        let pastMs = Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000
        let json = makeCredentialsJSON(expiresAt: pastMs)
        XCTAssertTrue(service.isTokenExpired(json))
    }

    func testIsTokenExpired_MillisecondsEpoch_Valid() {
        // expiresAt in milliseconds, 1 hour from now → should normalize and detect as valid
        let futureMs = Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000
        let json = makeCredentialsJSON(expiresAt: futureMs)
        XCTAssertFalse(service.isTokenExpired(json))
    }

    func testIsTokenExpired_NoExpiresAt_AssumesValid() {
        let json = """
        {"claudeAiOauth":{"accessToken":"test"}}
        """
        XCTAssertFalse(service.isTokenExpired(json))
    }

    func testIsTokenExpired_InvalidJSON_AssumesValid() {
        XCTAssertFalse(service.isTokenExpired("not json"))
    }

    // MARK: - extractTokenExpiry normalization

    func testExtractTokenExpiry_NormalizesMilliseconds() {
        let nowSeconds = Date().timeIntervalSince1970
        let nowMs = nowSeconds * 1000
        let json = makeCredentialsJSON(expiresAt: nowMs)

        guard let expiry = service.extractTokenExpiry(from: json) else {
            XCTFail("Expected non-nil expiry")
            return
        }

        // Should be within 1 second of now (normalized from ms)
        XCTAssertEqual(expiry.timeIntervalSince1970, nowSeconds, accuracy: 1.0)
    }

    func testExtractTokenExpiry_PassthroughSeconds() {
        let nowSeconds = Date().timeIntervalSince1970
        let json = makeCredentialsJSON(expiresAt: nowSeconds)

        guard let expiry = service.extractTokenExpiry(from: json) else {
            XCTFail("Expected non-nil expiry")
            return
        }

        XCTAssertEqual(expiry.timeIntervalSince1970, nowSeconds, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func makeCredentialsJSON(expiresAt: TimeInterval) -> String {
        """
        {"claudeAiOauth":{"accessToken":"test-token","expiresAt":\(expiresAt)}}
        """
    }
}
