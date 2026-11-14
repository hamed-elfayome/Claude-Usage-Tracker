### MT-3 — API layer: tier fields, 404/429 mapping with Retry-After, usage-only fetch

Size: S
Risk: normal
Importance: normal

**Goal:** Give the multi-team code the API signals it needs, without changing today's behaviour for
existing callers. Spec: `docs/specs/multi-team-tracking.md` §2 (status mapping row), §4, §6.

**Files**
- `Claude Usage/Shared/Services/ClaudeAPIService+Types.swift` (`AccountInfo` :28-32)
- `Claude Usage/Shared/Services/ClaudeAPIService.swift` (1369 lines; touch only: `fetchUsageData(sessionKey:organizationId:)` area :513, `fetchUsageData(oauthAccessToken:)` :545-570, `performRequest` status switch :807-866)
- NEW `Claude Usage/Shared/MultiTeam/AppError+MultiTeam.swift`
- NEW `Claude UsageTests/ClaudeAPIServiceMultiTeamTests.swift`

**Steps**
1. `AccountInfo`: add `var rateLimitTier: String? = nil`, `var billingType: String? = nil`,
   `var ravenType: String? = nil` and a `CodingKeys` enum mapping `uuid`, `name`, `capabilities`,
   `rate_limit_tier`, `billing_type`, `raven_type`. Keep `uuid`, `name`, `capabilities` required (as
   today). Existing memberwise calls `AccountInfo(uuid:name:capabilities:)` must still compile
   (`PreferredOrganizationTests`).
2. Extract the status switch of `performRequest` into
   `static func error(forStatus status: Int, data: Data, response: HTTPURLResponse, endpoint: String) -> AppError?`
   (nil for 200). `performRequest` calls it and throws the result. Same messages as today, plus:
   - `404` → `AppError(code: .apiNotFound, …)` (was `.apiGenericError`);
   - `429` → `technicalDetails` gains a line `Retry-After: <seconds>` when the header is present
     (integer seconds; ignore HTTP-date values).
3. `fetchUsageData(oauthAccessToken:)`: map 429 → `.apiRateLimited` with the same `Retry-After` line;
   keep 401/403 → `.apiUnauthorized`, everything else → `.apiGenericError`.
4. Add `func fetchUsageOnly(sessionKey: String, organizationId: String) async throws -> ClaudeUsage`
   next to `fetchUsageData(sessionKey:organizationId:)`: one `performRequest` to
   `/organizations/<id>/usage` then `parseUsageResponse`. No overage/credit/spend calls.
5. `AppError+MultiTeam.swift`: `extension AppError { var retryAfterSeconds: TimeInterval? }` (parse the
   `Retry-After:` line of `technicalDetails`), `var isCloudflareChallenge: Bool { code == .apiServiceUnavailable }`,
   `var isMembershipFailure: Bool { code == .apiUnauthorized || code == .apiNotFound }`,
   `var isRateLimited: Bool { code == .apiRateLimited }`.
6. Before changing 404, `grep -rn "apiGenericError" "Claude Usage"` and confirm no caller depends on a
   404 being generic; note the result in the walkthrough.
7. Tests, then Validate.

**Acceptance criteria**
1. Decoding `[{"uuid":"a","name":"A","capabilities":["chat"],"rate_limit_tier":"t1","billing_type":"b","raven_type":"team"}]` → fields set.
2. Decoding the same without the three fields → nil fields, no error.
3. `error(forStatus: 404, …)` → code `.apiNotFound`.
4. `error(forStatus: 429, …)` with header `Retry-After: 120` → `.apiRateLimited`, `retryAfterSeconds == 120`.
5. 429 without the header → `retryAfterSeconds == nil`.
6. 403 with body containing "Just a moment" → `.apiServiceUnavailable`, `isCloudflareChallenge == true`, `isMembershipFailure == false`.
7. 401 plain → `.apiUnauthorized`, `isMembershipFailure == true`.
8. 200 → nil.
9. `fetchUsageOnly` issues exactly one request (verified by reading the code path; it calls `performRequest` once).
10. Full suite passes (incl. `PreferredOrganizationTests`, `ClaudeAPIServiceParsingTests`).

**Tests:** build `HTTPURLResponse(url:statusCode:httpVersion:headerFields:)` objects directly — no
network. Edge cases: `Retry-After: abc`, `Retry-After: 0`, Cloudflare header `cf-mitigated` with 401,
500 still → `.apiServerError`.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`
