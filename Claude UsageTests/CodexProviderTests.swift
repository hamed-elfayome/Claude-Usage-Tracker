import XCTest
@testable import Claude_Usage

/// Codex provider: auth.json parsing (both shapes, both key styles), JWT
/// claim extraction, write-back key preservation, wham/usage decoding
/// tolerance, window normalization by duration, and usage mapping.
final class CodexProviderTests: XCTestCase {

    // MARK: - auth.json parsing

    func testParseOAuthTokensSnakeCase() throws {
        let json = """
        {
            "tokens": {
                "access_token": "at-123",
                "refresh_token": "rt-456",
                "id_token": "id-789",
                "account_id": "acc-1"
            },
            "last_refresh": "2026-07-10T12:00:00.000Z"
        }
        """
        let credentials = try XCTUnwrap(CodexAuthService.parse(Data(json.utf8)))
        XCTAssertEqual(credentials.accessToken, "at-123")
        XCTAssertEqual(credentials.refreshToken, "rt-456")
        XCTAssertEqual(credentials.idToken, "id-789")
        XCTAssertEqual(credentials.accountId, "acc-1")
        XCTAssertNotNil(credentials.lastRefresh)
    }

    func testParseOAuthTokensCamelCase() throws {
        let json = """
        {
            "tokens": {
                "accessToken": "at-123",
                "refreshToken": "rt-456",
                "idToken": "id-789",
                "accountId": "acc-1"
            },
            "last_refresh": "2026-07-10T12:00:00Z"
        }
        """
        let credentials = try XCTUnwrap(CodexAuthService.parse(Data(json.utf8)))
        XCTAssertEqual(credentials.accessToken, "at-123")
        XCTAssertEqual(credentials.refreshToken, "rt-456")
        XCTAssertNotNil(credentials.lastRefresh, "non-fractional ISO8601 must parse too")
    }

    func testParseAPIKeyOnlyShape() throws {
        let json = """
        {"OPENAI_API_KEY": "sk-test-123"}
        """
        let credentials = try XCTUnwrap(CodexAuthService.parse(Data(json.utf8)))
        XCTAssertEqual(credentials.accessToken, "sk-test-123")
        XCTAssertTrue(credentials.refreshToken.isEmpty)
        XCTAssertFalse(credentials.needsRefresh, "API-key credentials must never be refreshed")
    }

    func testParseGarbageReturnsNil() {
        XCTAssertNil(CodexAuthService.parse(Data("not json".utf8)))
        XCTAssertNil(CodexAuthService.parse(Data("{}".utf8)))
        XCTAssertNil(CodexAuthService.parse(Data("{\"tokens\": {}}".utf8)))
    }

    // MARK: - Refresh policy

    func testNeedsRefreshWhenLastRefreshOld() {
        let old = Date().addingTimeInterval(-9 * 24 * 60 * 60)
        let credentials = CodexCredentials(accessToken: "at", refreshToken: "rt", idToken: nil, accountId: nil, lastRefresh: old)
        XCTAssertTrue(credentials.needsRefresh)
    }

    func testNoRefreshWhenRecent() {
        let recent = Date().addingTimeInterval(-1 * 24 * 60 * 60)
        let credentials = CodexCredentials(accessToken: "at", refreshToken: "rt", idToken: nil, accountId: nil, lastRefresh: recent)
        XCTAssertFalse(credentials.needsRefresh)
    }

    func testNeedsRefreshWhenLastRefreshMissing() {
        let credentials = CodexCredentials(accessToken: "at", refreshToken: "rt", idToken: nil, accountId: nil, lastRefresh: nil)
        XCTAssertTrue(credentials.needsRefresh)
    }

    // MARK: - JWT claims

    private func makeJWT(payload: [String: Any]) -> String {
        let header = Data("{\"alg\":\"none\"}".utf8).base64EncodedString()
        let body = try! JSONSerialization.data(withJSONObject: payload)
        let payloadSegment = body.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(payloadSegment).sig"
    }

    func testAccountIdFromNestedAuthClaim() {
        let jwt = makeJWT(payload: [
            "email": "dev@example.com",
            "https://api.openai.com/auth": ["chatgpt_account_id": "acc-jwt-1"]
        ])
        let credentials = CodexCredentials(accessToken: "at", refreshToken: "rt", idToken: jwt, accountId: nil, lastRefresh: nil)
        XCTAssertEqual(credentials.resolvedAccountId, "acc-jwt-1")
        XCTAssertEqual(credentials.email, "dev@example.com")
    }

    func testAccountIdFromTopLevelClaim() {
        let jwt = makeJWT(payload: ["chatgpt_account_id": "acc-top"])
        let credentials = CodexCredentials(accessToken: "at", refreshToken: "rt", idToken: jwt, accountId: nil, lastRefresh: nil)
        XCTAssertEqual(credentials.resolvedAccountId, "acc-top")
    }

    func testExplicitAccountIdWinsOverJWT() {
        let jwt = makeJWT(payload: ["chatgpt_account_id": "acc-jwt"])
        let credentials = CodexCredentials(accessToken: "at", refreshToken: "rt", idToken: jwt, accountId: "acc-explicit", lastRefresh: nil)
        XCTAssertEqual(credentials.resolvedAccountId, "acc-explicit")
    }

    // MARK: - Write-back serialization

    func testSerializePreservesUnknownTopLevelKeys() throws {
        let existing = """
        {"tokens": {"access_token": "old"}, "some_future_key": {"a": 1}, "OPENAI_API_KEY": "sk-x"}
        """
        let credentials = CodexCredentials(accessToken: "new-at", refreshToken: "new-rt", idToken: "new-id", accountId: "acc", lastRefresh: Date())
        let serialized = try XCTUnwrap(CodexAuthService.serializeAuthJSON(credentials, mergingInto: existing))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(serialized.utf8)) as? [String: Any])

        XCTAssertNotNil(dict["some_future_key"], "unknown keys written by the Codex CLI must survive write-back")
        XCTAssertEqual(dict["OPENAI_API_KEY"] as? String, "sk-x")
        let tokens = try XCTUnwrap(dict["tokens"] as? [String: Any])
        XCTAssertEqual(tokens["access_token"] as? String, "new-at")
        XCTAssertEqual(tokens["refresh_token"] as? String, "new-rt")
        XCTAssertNotNil(dict["last_refresh"])
    }

    // MARK: - wham/usage decoding

    private func decodeResponse(_ json: String) throws -> CodexUsageResponse {
        try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
    }

    func testDecodeFullResponse() throws {
        let json = """
        {
            "plan_type": "plus",
            "rate_limit": {
                "primary_window": {"used_percent": 42, "reset_at": 1789000000, "limit_window_seconds": 18000},
                "secondary_window": {"used_percent": 17, "reset_at": 1789500000, "limit_window_seconds": 604800}
            },
            "credits": {"has_credits": true, "unlimited": false, "balance": "12.50"}
        }
        """
        let response = try decodeResponse(json)
        XCTAssertEqual(response.planType, "plus")
        XCTAssertEqual(response.rateLimit?.primaryWindow?.usedPercent, 42)
        XCTAssertEqual(response.rateLimit?.secondaryWindow?.limitWindowSeconds, 604800)
        XCTAssertEqual(response.credits?.balance, 12.50, "string balances must parse")
    }

    func testDecodeMissingSecondaryWindowAndCredits() throws {
        let json = """
        {
            "plan_type": "free",
            "rate_limit": {"primary_window": {"used_percent": 90, "reset_at": 1789000000, "limit_window_seconds": 18000}}
        }
        """
        let response = try decodeResponse(json)
        XCTAssertNil(response.rateLimit?.secondaryWindow)
        XCTAssertNil(response.credits)
    }

    func testDecodeToleratesUnknownAndMalformedFields() throws {
        let json = """
        {
            "plan_type": "some_new_plan",
            "rate_limit": {
                "primary_window": {"used_percent": 10, "reset_at": 1789000000, "limit_window_seconds": 18000},
                "individual_limit": {"limit": "weird"}
            },
            "individual_limit": [1, 2],
            "additional_rate_limits": [{"limit_name": "GPT-5.3-Codex-Spark", "rate_limit": "garbage"}],
            "credits": {"has_credits": "not-a-bool"}
        }
        """
        let response = try decodeResponse(json)
        XCTAssertEqual(response.planType, "some_new_plan", "unknown plan types must pass through as raw strings")
        XCTAssertEqual(response.rateLimit?.primaryWindow?.usedPercent, 10)
        XCTAssertEqual(response.credits?.hasCredits, false, "malformed bool degrades to false")
    }

    // MARK: - Window normalization (by duration, not position)

    private func window(_ percent: Double, minutes: Int?) -> CodexRateWindow {
        CodexRateWindow(usedPercent: percent, resetAt: 1789000000, limitWindowSeconds: minutes.map { $0 * 60 })
    }

    func testNormalizeStandardOrder() {
        let result = CodexRateWindowNormalizer.normalize(
            primary: window(42, minutes: 300),
            secondary: window(17, minutes: 10080)
        )
        XCTAssertEqual(result.session?.usedPercent, 42)
        XCTAssertEqual(result.weekly?.usedPercent, 17)
    }

    func testNormalizeSwappedOrder() {
        let result = CodexRateWindowNormalizer.normalize(
            primary: window(17, minutes: 10080),
            secondary: window(42, minutes: 300)
        )
        XCTAssertEqual(result.session?.usedPercent, 42, "windows must be classified by duration, not position")
        XCTAssertEqual(result.weekly?.usedPercent, 17)
    }

    func testNormalizeLoneWeeklyWindow() {
        let result = CodexRateWindowNormalizer.normalize(
            primary: window(17, minutes: 10080),
            secondary: nil
        )
        XCTAssertNil(result.session)
        XCTAssertEqual(result.weekly?.usedPercent, 17)
    }

    func testNormalizeUnknownDurationDefaultsToSession() {
        let result = CodexRateWindowNormalizer.normalize(
            primary: window(50, minutes: 123),
            secondary: nil
        )
        XCTAssertEqual(result.session?.usedPercent, 50)
        XCTAssertNil(result.weekly)
    }

    func testNormalizeUnknownPrimaryWithSessionSecondary() {
        // A recognized session window must win the session slot even when the
        // other window has an unrecognized duration (e.g. a future 6h window).
        let result = CodexRateWindowNormalizer.normalize(
            primary: window(50, minutes: 360),
            secondary: window(42, minutes: 300)
        )
        XCTAssertEqual(result.session?.usedPercent, 42)
        XCTAssertEqual(result.weekly?.usedPercent, 50)
    }

    // MARK: - Usage mapping

    func testMapToUsagePopulatesPercentagesAndZeroTokens() throws {
        let response = try decodeResponse("""
        {
            "plan_type": "pro",
            "rate_limit": {
                "primary_window": {"used_percent": 42, "reset_at": 1789000000, "limit_window_seconds": 18000},
                "secondary_window": {"used_percent": 17, "reset_at": 1789500000, "limit_window_seconds": 604800}
            },
            "credits": {"has_credits": true, "unlimited": true, "balance": 3.5}
        }
        """)
        let usage = CodexAPIService.mapToUsage(response)

        XCTAssertEqual(usage.sessionPercentage, 42)
        XCTAssertEqual(usage.sessionResetTime, Date(timeIntervalSince1970: 1789000000))
        XCTAssertEqual(usage.weeklyPercentage, 17)
        XCTAssertEqual(usage.weeklyResetTime, Date(timeIntervalSince1970: 1789500000))
        XCTAssertEqual(usage.sessionTokensUsed, 0)
        XCTAssertEqual(usage.weeklyTokensUsed, 0)
        XCTAssertEqual(usage.weeklyLimit, 0, "no placeholder token limit for Codex")
        XCTAssertEqual(usage.opusWeeklyTokensUsed, 0)
        XCTAssertEqual(usage.planType, "pro")
        XCTAssertEqual(usage.creditsBalance, 3.5)
        XCTAssertEqual(usage.creditsUnlimited, true)
    }

    func testMapToUsageMissingWeeklyGivesZeroPercent() throws {
        let response = try decodeResponse("""
        {"rate_limit": {"primary_window": {"used_percent": 99, "reset_at": 1789000000, "limit_window_seconds": 18000}}}
        """)
        let usage = CodexAPIService.mapToUsage(response)
        XCTAssertEqual(usage.sessionPercentage, 99)
        XCTAssertEqual(usage.weeklyPercentage, 0)
    }

    func testMapToUsageMissingResetAtReusesPreviousResetTimes() throws {
        // Without reset_at, a now-relative fallback would change every fetch
        // and MenuBarManager's reset detection would record a bogus reset per
        // refresh. The previous usage's future reset times must be reused.
        let response = try decodeResponse("""
        {"rate_limit": {
            "primary_window": {"used_percent": 10, "limit_window_seconds": 18000},
            "secondary_window": {"used_percent": 5, "limit_window_seconds": 604800}
        }}
        """)
        var previous = ClaudeUsage.empty
        previous.sessionResetTime = Date().addingTimeInterval(2 * 60 * 60)
        previous.weeklyResetTime = Date().addingTimeInterval(3 * 24 * 60 * 60)

        let usage = CodexAPIService.mapToUsage(response, previous: previous)
        XCTAssertEqual(usage.sessionResetTime, previous.sessionResetTime)
        XCTAssertEqual(usage.weeklyResetTime, previous.weeklyResetTime)
    }

    func testMapToUsageMissingResetAtIgnoresExpiredPreviousResetTimes() throws {
        let response = try decodeResponse("""
        {"rate_limit": {"primary_window": {"used_percent": 10, "limit_window_seconds": 18000}}}
        """)
        var previous = ClaudeUsage.empty
        previous.sessionResetTime = Date().addingTimeInterval(-60)  // already elapsed

        let usage = CodexAPIService.mapToUsage(response, previous: previous)
        XCTAssertGreaterThan(usage.sessionResetTime, Date(), "an elapsed previous reset must not be carried forward")
    }

    // MARK: - config.toml base URL

    func testParseChatGPTBaseURLFromConfig() {
        let toml = """
        # codex config
        model = "gpt-5"
        chatgpt_base_url = "https://enterprise.example.com/proxy"  # comment
        """
        XCTAssertEqual(CodexAPIService.parseChatGPTBaseURL(from: toml), "https://enterprise.example.com/proxy")
    }

    func testParseChatGPTBaseURLIgnoresCommentedOutLine() {
        let toml = """
        # chatgpt_base_url = "https://old-proxy.corp.com"
        model = "gpt-5"
        """
        XCTAssertNil(CodexAPIService.parseChatGPTBaseURL(from: toml), "a fully commented-out line must not be treated as the active setting")
    }

    func testUsageURLDefaultsToWhamPath() {
        let url = CodexAPIService.shared.usageURL(env: [:], configContents: "")
        XCTAssertEqual(url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
    }

    func testUsageURLNonBackendBaseUsesCodexPath() {
        let url = CodexAPIService.shared.usageURL(env: [:], configContents: "chatgpt_base_url = \"https://proxy.corp.com\"")
        XCTAssertEqual(url.absoluteString, "https://proxy.corp.com/api/codex/usage")
    }

    func testUsageURLBareChatGPTHostGetsBackendAPI() {
        let url = CodexAPIService.shared.usageURL(env: [:], configContents: "chatgpt_base_url = \"https://chatgpt.com/\"")
        XCTAssertEqual(url.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
    }
}
