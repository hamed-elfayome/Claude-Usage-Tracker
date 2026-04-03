import XCTest
@testable import Claude_Usage

final class CodexUsageTests: XCTestCase {
    func testRequestPercentageUsed() {
        let usage = CodexUsage(
            requestLimit: 100, requestsRemaining: 28,
            tokenLimit: 100000, tokensRemaining: 55000,
            requestResetTime: Date(), tokenResetTime: Date(),
            lastUpdated: Date()
        )
        XCTAssertEqual(usage.requestPercentageUsed, 72.0, accuracy: 0.001)
        XCTAssertEqual(usage.tokenPercentageUsed, 45.0, accuracy: 0.001)
    }

    func testZeroLimitReturnsZeroPercentage() {
        let usage = CodexUsage(
            requestLimit: 0, requestsRemaining: 0,
            tokenLimit: 0, tokensRemaining: 0,
            requestResetTime: Date(), tokenResetTime: Date(),
            lastUpdated: Date()
        )
        XCTAssertEqual(usage.requestPercentageUsed, 0)
        XCTAssertEqual(usage.tokenPercentageUsed, 0)
    }

    func testParseResetDurationMinutesSeconds() {
        let duration = CodexUsage.parseResetDuration("6m32.345s")
        XCTAssertNotNil(duration)
        XCTAssertEqual(duration!, 392.345, accuracy: 0.001)
    }

    func testParseResetDurationMilliseconds() {
        let duration = CodexUsage.parseResetDuration("432ms")
        XCTAssertNotNil(duration)
        XCTAssertEqual(duration!, 0.432, accuracy: 0.001)
    }

    func testParseResetDurationHoursMinutesSeconds() {
        let duration = CodexUsage.parseResetDuration("1h2m3s")
        XCTAssertNotNil(duration)
        XCTAssertEqual(duration!, 3723, accuracy: 0.001)
    }

    func testParseResetDurationZero() {
        let duration = CodexUsage.parseResetDuration("0s")
        XCTAssertNotNil(duration)
        XCTAssertEqual(duration!, 0, accuracy: 0.001)
    }

    func testFromHeaders() {
        let now = Date()
        let headers: [String: String] = [
            "x-ratelimit-limit-requests": "100",
            "x-ratelimit-remaining-requests": "72",
            "x-ratelimit-limit-tokens": "50000",
            "x-ratelimit-remaining-tokens": "35000",
            "x-ratelimit-reset-requests": "2m30s",
            "x-ratelimit-reset-tokens": "1m0s"
        ]
        let usage = CodexUsage.fromHeaders(headers, at: now)
        XCTAssertNotNil(usage)
        XCTAssertEqual(usage!.requestLimit, 100)
        XCTAssertEqual(usage!.requestsRemaining, 72)
        XCTAssertEqual(usage!.tokenLimit, 50000)
        XCTAssertEqual(usage!.tokensRemaining, 35000)
        XCTAssertEqual(usage!.requestResetTime.timeIntervalSince(now), 150, accuracy: 0.001)
        XCTAssertEqual(usage!.tokenResetTime.timeIntervalSince(now), 60, accuracy: 0.001)
    }

    func testFromHeadersMissingFieldReturnsNil() {
        let headers: [String: String] = [
            "x-ratelimit-limit-requests": "100"
        ]
        XCTAssertNil(CodexUsage.fromHeaders(headers))
    }

    func testCodableRoundTrip() throws {
        let usage = CodexUsage(
            requestLimit: 100, requestsRemaining: 72,
            tokenLimit: 50000, tokensRemaining: 35000,
            requestResetTime: Date(), tokenResetTime: Date(),
            lastUpdated: Date()
        )
        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(CodexUsage.self, from: data)
        XCTAssertEqual(usage, decoded)
    }
}
