### MT-4 — API signals: tier fields, 404/429 mapping with Retry-After, usage-only fetch

Size: S
Risk: normal
Importance: normal
After: MT-0

**Goal:** Give the team tracker the API signals it needs without changing behaviour for existing callers:
optional seat-tier fields on the org list, a distinct "not found" error, `Retry-After` on 429, a 429 code on
the OAuth path, and a one-request usage fetch for probes. Spec `docs/specs/multi-team-tracking.md` §2 (status
mapping row), §6 (M, S1), §7.

**Files**
- `Claude Usage/Shared/Services/ClaudeAPIService+Types.swift` (`AccountInfo` :28-32)
- `Claude Usage/Shared/Services/ClaudeAPIService.swift` (1369 lines; touch only: next to `fetchUsageData(sessionKey:organizationId:)` :513-542, `fetchUsageData(oauthAccessToken:)` :545-570, the status switch used by `performRequest` :807-866)
- NEW `Claude Usage/Shared/MultiTeam/AppError+MultiTeam.swift`
- NEW `Claude UsageTests/ClaudeAPIServiceMultiTeamTests.swift`

**Steps**
1. `AccountInfo`: add `var rateLimitTier: String? = nil`, `var billingType: String? = nil`,
   `var ravenType: String? = nil` and `CodingKeys` mapping `uuid`, `name`, `capabilities`, `rate_limit_tier`,
   `billing_type`, `raven_type`. `uuid`, `name`, `capabilities` stay as required as today. The memberwise
   `AccountInfo(uuid:name:capabilities:)` must still compile (`PreferredOrganizationTests`).
2. Extract the status switch of `performRequest` into
   `static func error(forStatus status: Int, data: Data, response: HTTPURLResponse, endpoint: String) -> AppError?`
   (nil for 2xx). `performRequest` throws its result. Same messages as today, except:
   - 404 → `AppError(code: .apiNotFound, …)` (was `.apiGenericError`);
   - 429 → `technicalDetails` gains a line `Retry-After: <seconds>` when the header holds integer seconds
     (HTTP-date values ignored).
3. Before step 2's 404 change: `grep -rn "apiGenericError" "Claude Usage"` and confirm no caller depends on a 404
   being generic; write the result in the walkthrough.
4. `fetchUsageData(oauthAccessToken:)`: 429 → `.apiRateLimited` with the same `Retry-After` line; 401/403 →
   `.apiUnauthorized` as today; everything else unchanged.
5. `func fetchUsageOnly(sessionKey: String, organizationId: String) async throws -> ClaudeUsage` next to
   `fetchUsageData(sessionKey:organizationId:)`: one `performRequest` to `/organizations/<id>/usage`, then
   `parseUsageResponse`. No overage/credit/spend calls.
6. `AppError+MultiTeam.swift`: `extension AppError { var retryAfterSeconds: TimeInterval?` (parses the
   `Retry-After:` line, must be ≥ 0), `var isCloudflareChallenge: Bool { code == .apiServiceUnavailable }`,
   `var isMembershipFailure: Bool { code == .apiUnauthorized || code == .apiNotFound }`,
   `var isRateLimited: Bool { code == .apiRateLimited } }`.
7. Tests, then Validate.

**Acceptance criteria**
1. Decoding `[{"uuid":"a","name":"A","capabilities":["chat"],"rate_limit_tier":"t1","billing_type":"b","raven_type":"team"}]` → three fields set.
2. The same JSON without the three fields → nil fields, no error.
3. `error(forStatus: 404, …)` → `.apiNotFound`, `isMembershipFailure == true`.
4. `error(forStatus: 429, …)` with header `Retry-After: 120` → `.apiRateLimited`, `retryAfterSeconds == 120`, `isRateLimited`.
5. 429 without the header, or with `Retry-After: abc` → `retryAfterSeconds == nil`.
6. 403 with a body containing "Just a moment" → `.apiServiceUnavailable`, `isCloudflareChallenge`, not a membership failure.
7. 401 plain → `.apiUnauthorized`, `isMembershipFailure`.
8. 200 → nil; 500 → `.apiServerError` (as today).
9. `fetchUsageOnly` calls `performRequest` exactly once (code reading, noted in the walkthrough).
10. `grep` result of step 3 recorded; no behaviour change for other callers besides 404.
11. Full suite passes, including `PreferredOrganizationTests` and `ClaudeAPIServiceParsingTests`.

**Tests:** build `HTTPURLResponse(url:statusCode:httpVersion:headerFields:)` directly, no network. Edge cases:
`Retry-After: 0`, `cf-mitigated` header with 401, lower-case `retry-after` header name.

**Validate:** `scripts/validate-clt.sh` (runs `xcodebuild test` automatically when full Xcode is present) `git diff --check`

**Coverage limit:** without Xcode the harness does not build the widget extension, the asset catalog or other resources, and compiles DynamicNotchKit/Sparkle against stubs; one full `xcodebuild` build+test run is required at release time (see `multi-team.md`).
