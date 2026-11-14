import XCTest
@testable import Claude_Usage

final class ClaudeAPIServiceMultiTeamTests: XCTestCase {
    private func err(_ status: Int, body: String = "", headers: [String: String] = [:]) -> AppError? {
        let r = HTTPURLResponse(url: URL(string: "https://claude.ai/x")!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return ClaudeAPIService.error(forStatus: status, data: Data(body.utf8), response: r, endpoint: "/x")
    }

    func testDecodeTierFields() throws {
        let j = #"[{"uuid":"a","name":"A","capabilities":["chat"],"rate_limit_tier":"t1","billing_type":"b","raven_type":"team"}]"#
        let o = try JSONDecoder().decode([ClaudeAPIService.AccountInfo].self, from: Data(j.utf8))
        XCTAssertEqual(o[0].rateLimitTier, "t1")
        XCTAssertEqual(o[0].billingType, "b")
        XCTAssertEqual(o[0].ravenType, "team")
    }

    func testDecodeWithoutTierFields() throws {
        let j = #"[{"uuid":"a","name":"A","capabilities":["chat"]}]"#
        let o = try JSONDecoder().decode([ClaudeAPIService.AccountInfo].self, from: Data(j.utf8))
        XCTAssertNil(o[0].rateLimitTier)
        XCTAssertNil(o[0].billingType)
        XCTAssertNil(o[0].ravenType)
    }

    func testNonStringTierFieldsDecodeAsNil() throws {
        let cases = [
            #"{"billing_type":{"provider":"stripe"}}"#,
            #"{"rate_limit_tier":5}"#,
            #"{"raven_type":true}"#,
            #"{"billing_type":null}"#,
        ]
        for extra in cases {
            let j = #"[{"uuid":"a","name":"A","capabilities":["chat"],"# + String(extra.dropFirst()) + "]"
            let o = try JSONDecoder().decode([ClaudeAPIService.AccountInfo].self, from: Data(j.utf8))
            XCTAssertEqual(o.count, 1, extra)
            XCTAssertNil(o[0].billingType, extra)
            XCTAssertNil(o[0].rateLimitTier, extra)
            XCTAssertNil(o[0].ravenType, extra)
        }
    }

    func testBadTierFieldKeepsGoodOnes() throws {
        let j = #"[{"uuid":"a","name":"A","capabilities":["chat"],"rate_limit_tier":"t1","billing_type":{"x":1},"raven_type":"team"}]"#
        let o = try JSONDecoder().decode([ClaudeAPIService.AccountInfo].self, from: Data(j.utf8))
        XCTAssertEqual(o[0].rateLimitTier, "t1")
        XCTAssertNil(o[0].billingType)
        XCTAssertEqual(o[0].ravenType, "team")
    }

    func testMemberwiseInitStillWorks() {
        let a = ClaudeAPIService.AccountInfo(uuid: "u", name: "n", capabilities: [])
        XCTAssertNil(a.rateLimitTier)
    }

    func test404() {
        let e = err(404)
        XCTAssertEqual(e?.code, .apiNotFound)
        XCTAssertTrue(e?.isMembershipFailure == true)
    }

    func test429RetryAfter() {
        let e = err(429, headers: ["Retry-After": "120"])
        XCTAssertEqual(e?.code, .apiRateLimited)
        XCTAssertEqual(e?.retryAfterSeconds, 120)
        XCTAssertTrue(e?.isRateLimited == true)
    }

    func test429RetryAfterZeroAndLowercase() {
        XCTAssertEqual(err(429, headers: ["Retry-After": "0"])?.retryAfterSeconds, 0)
        XCTAssertEqual(err(429, headers: ["retry-after": "7"])?.retryAfterSeconds, 7)
    }

    func test429NoOrBadHeader() {
        XCTAssertNil(err(429)?.retryAfterSeconds)
        XCTAssertNil(err(429, headers: ["Retry-After": "abc"])?.retryAfterSeconds)
        XCTAssertNil(err(429, headers: ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"])?.retryAfterSeconds)
    }

    func testCloudflare403() {
        let e = err(403, body: "<title>Just a moment</title>")
        XCTAssertEqual(e?.code, .apiServiceUnavailable)
        XCTAssertTrue(e?.isCloudflareChallenge == true)
        XCTAssertFalse(e?.isMembershipFailure == true)
    }

    func testCfMitigatedHeaderWith401() {
        let e = err(401, headers: ["cf-mitigated": "challenge"])
        XCTAssertTrue(e?.isCloudflareChallenge == true)
    }

    func test401Plain() {
        let e = err(401, body: "nope")
        XCTAssertEqual(e?.code, .apiUnauthorized)
        XCTAssertTrue(e?.isMembershipFailure == true)
    }

    func test200Nil500Server() {
        XCTAssertNil(err(200))
        XCTAssertEqual(err(500)?.code, .apiServerError)
    }

    func testNegativeRetryAfterIsNil() {
        XCTAssertNil(err(429, headers: ["Retry-After": "-5"])?.retryAfterSeconds)
    }

    func testOAuthStyleRetryAfterLine() {
        let e = AppError(code: .apiRateLimited, message: "m", technicalDetails: "Endpoint: oauth/usage\nRetry-After: 5", isRecoverable: true)
        XCTAssertEqual(e.retryAfterSeconds, 5)
    }

    func test403PlainIsUnauthorizedNotCloudflare() {
        let e = err(403, body: "forbidden")
        XCTAssertEqual(e?.code, .apiUnauthorized)
        XCTAssertFalse(e?.isCloudflareChallenge == true)
    }

    func test204IsNil() {
        XCTAssertNil(err(204))
    }
}
