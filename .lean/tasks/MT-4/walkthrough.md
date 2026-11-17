## Summary
AccountInfo gains optional tier fields. The performRequest status switch is now `ClaudeAPIService.error(forStatus:data:response:endpoint:)`, with 404 mapped to apiNotFound and a Retry-After line added on 429. The OAuth path maps 429 to apiRateLimited, `fetchUsageOnly` is new, and there is an AppError helper extension.
Round 4: the code was already correct (see the root cause below). The xcodebuild gate is still red because this host has no Xcode, so the status is BLOCKED.

## Root cause of the repeated rounds (round 4)
- Must fix 1 is stale. `ClaudeAPIService.swift:867` reads `Self.retryAfterLine(httpResponse)`, and grep shows no `retryAfterLine(response)` anywhere. The file mtime (06:44:37) is later than verdict.md (06:44:20), so the verdict describes a copy from before the fix. `swiftc -typecheck` over Shared/{Services,MultiTeam,Models,Utilities} reports only `UpdateManager.swift:10: no such module 'Sparkle'`, which is the environment.
- Must fix 2 can never pass on this host. `/Applications/Xcode*` is absent, `mdfind com.apple.dt.Xcode` finds nothing, and `xcode-select -p` gives /Library/Developer/CommandLineTools. No code change can fix that: rounds keep failing on the environment, not on the code.

## Changes
- `Claude Usage/Shared/Services/ClaudeAPIService+Types.swift`: three optional fields and snake_case CodingKeys on AccountInfo. The memberwise init is kept.
- `Claude Usage/Shared/Services/ClaudeAPIService.swift`: static `error(forStatus:...)` (performRequest throws its result), `retryAfterLine`, `fetchUsageOnly`, OAuth 429 mapped to apiRateLimited with the Retry-After line.
- `Claude Usage/Shared/MultiTeam/AppError+MultiTeam.swift` (new): retryAfterSeconds, isCloudflareChallenge, isMembershipFailure, isRateLimited.
- `Claude UsageTests/ClaudeAPIServiceMultiTeamTests.swift` (new): 14 tests.
- No source change in round 4. Only this walkthrough changed.

## Acceptance
Evidence key: "harness" means a scratch run on this host. The real source snippets (AccountInfo, error(forStatus:), retryAfterLine, preferredOrganization, AppError core and AppError+MultiTeam) were extracted with sed and compiled with swiftc. The real test files were compiled unchanged except for the imports, against a tiny XCTest shim. Result: 18 tests run, `failures: 0`, exit 0. Mutation check: changing 404 to apiGenericError and `>= 0` to `>= 1` in the copy makes 3 assertions fail. This is NOT the packet's xcodebuild gate.
1. Met (harness): testDecodeTierFields.
2. Met (harness): testDecodeWithoutTierFields.
3. Met (harness): test404.
4. Met (harness): test429RetryAfter.
5. Met (harness): test429NoOrBadHeader.
6. Met (harness): testCloudflare403.
7. Met (harness): test401Plain.
8. Met (harness): test200Nil500Server.
9. Met by code reading: `fetchUsageOnly` (ClaudeAPIService.swift:545-548) makes one `performRequest` to `/organizations/<id>/usage`, then calls `parseUsageResponse`.
10. Met. `grep -rn apiGenericError "Claude Usage"` gives ClaudeAPIService.swift:431 (separate org-fetch path), :570 (OAuth fallback), :885 (status-switch default) and AutoStartSessionService+Requests.swift:32/101/144/198/230 (its own requests). None of them depends on performRequest's 404 being generic.
11. NOT met: the full suite cannot run here because xcodebuild needs Xcode. PreferredOrganizationTests passes in the harness (4/4). ClaudeAPIServiceParsingTests was not run.

## Flow
performRequest -> `Self.error(forStatus:data:response:endpoint:)`. It returns nil for 2xx, otherwise performRequest throws the AppError. On 429, `retryAfterLine` appends "\nRetry-After: N" to technicalDetails. fetchUsageData(oauthAccessToken:) uses the same line on 429. Callers read `AppError.retryAfterSeconds` and `isRateLimited`/`isMembershipFailure`/`isCloudflareChallenge`. Probes call `fetchUsageOnly`.

## Tests
- `Claude UsageTests/ClaudeAPIServiceMultiTeamTests.swift`: AC1-8 plus Retry-After 0, lowercase header, HTTP-date, "abc", -5, the OAuth-style line, cf-mitigated with 401, a plain 403 and 204.
- Packet Validate: `xcodebuild test ...` gives `xcode-select: error: tool 'xcodebuild' requires Xcode ... command line tools instance` with exit 1. `git diff --check` exits 0.
- Scratch harness (see Acceptance): 18 run, 0 failures.

## Edge cases
Handled: Retry-After 0, a lowercase header name, HTTP-date, non-numeric and negative values (all in retryAfterLine and retryAfterSeconds), cf-mitigated as a header or in the body. Side effect: performRequest now treats every 2xx as success (it was only 200), so 201 and 204 succeed.
Not handled: a leading `+` is accepted by Int() (harmless).

## Shortcuts
none

## Lessons
- This host has only CommandLineTools. xcodebuild cannot run, so the gate needs a machine with Xcode (or DEVELOPER_DIR pointing to one).
- For a quick check without Xcode, compile the extracted pure snippets plus an XCTest shim with swiftc. A full Shared typecheck stops on Sparkle and on the SwiftUI macro plugins.

## Round 2 fix
- Root cause: synthesized Decodable on `String?` throws typeMismatch on a non-string value (only missing/null give nil), so one odd tier value failed the whole org list.
- `ClaudeAPIService+Types.swift` AccountInfo: explicit memberwise init (defaults for tier fields) plus custom `init(from:)`: uuid/name/capabilities strict, the three tier fields via `try? decode(String.self)` so a bad value is nil. Encode stays synthesized.
- Tests added in `ClaudeAPIServiceMultiTeamTests`: `testNonStringTierFieldsDecodeAsNil` (object, number, bool, null), `testBadTierFieldKeepsGoodOnes`, `testMemberwiseInitStillWorks`.
- Note: 2xx other than 200 now return nil from `error(forStatus:)` (success), covered by `test204IsNil`.
- Validate: `validate-clt.sh --root .` -> Executed 407 tests: 405 ok, 0 failed, 2 skipped; `git diff --check` clean.
