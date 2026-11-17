## Tester result
All green: 407 tests run, 405 ok, 0 failed, 2 skipped (pre-existing keychain skips); 0 new tests added (round 2 verdict lines already covered).

## Suites run
- `bash /Users/kuke/Coding/Claude-Usage-Tracker/scripts/validate-clt.sh --root .` (CLT path, no Xcode on host) → `Executed 407 tests: 405 ok, 0 failed, 2 skipped`, `EXIT=0`
  - MT-4 classes in that run: `ClaudeAPIServiceMultiTeamTests` 17/17 ok, `ClaudeAPIServiceParsingTests` 8/8 ok, `PreferredOrganizationTests` 4/4 ok
  - Skips: `ProfileKeychainMigrationTests.testFieldsAreIsolatedPerProfileAndField`, `ProfileKeychainMigrationTests.testProfileSecretRoundTrip` (data-protection keychain under ad-hoc signing; not related to MT-4)
- `rtk git diff --check` (run in the worktree) → exit 0, no output

## New tests
None added. This is a retest round, so only the verdict's "Tests to add" lines were in scope, and the builder's round-2 tests already cover all of them in `Claude UsageTests/ClaudeAPIServiceMultiTeamTests.swift`:
- Verdict line 1 (`billing_type` object → 1 org, `billingType` nil): `testNonStringTierFieldsDecodeAsNil`, case `{"billing_type":{"provider":"stripe"}}` (asserts `count == 1` and `billingType == nil`).
- Verdict line 2 (`rate_limit_tier: 5` and `raven_type: true` → decodes, field nil): `testNonStringTierFieldsDecodeAsNil`, cases `{"rate_limit_tier":5}` and `{"raven_type":true}`.
- Verdict line 3 (missing keys → nil; string values still decode): `testDecodeWithoutTierFields` (missing), `testDecodeTierFields` (strings); null → nil is `testNonStringTierFieldsDecodeAsNil`, case `{"billing_type":null}`.
- Regression check by reasoning (no mutation run, source is not editable here): if the custom `init(from:)` were removed, the synthesized `Decodable` would throw `typeMismatch` on the object, number and bool cases, so `testNonStringTierFieldsDecodeAsNil` would fail. Duplicating these as separate tests would add no new behaviour, so none were added.

Gap, not added (retest scope): `testOAuthStyleRetryAfterLine` builds the `AppError` by hand. The OAuth 429 mapping in `fetchUsageData(oauthAccessToken:)` (`ClaudeAPIService.swift` ~lines 566-575) is only covered by code reading, because it calls `URLSession.shared` directly.

## Bugs
No failing tests. One minor deviation from the packet:
- `Claude Usage/Shared/Services/ClaudeAPIService.swift`, `static func error(forStatus:…)`, `case 200..<300: return nil` (~line 822).
  - Input: HTTP 204 (also 201 and 299) on any endpoint.
  - Expected (packet step 2 and acceptance 10: "Same messages as today", "no behaviour change for other callers besides 404"): only 200 succeeds; other 2xx keep today's result.
  - Actual: any 2xx returns nil (success), and the body goes on to the parser. The walkthrough discloses this, and `ClaudeAPIServiceMultiTeamTests.test204IsNil` locks it in.
  - Reproduce: call `ClaudeAPIService.error(forStatus: 204, data: Data(), response: <HTTPURLResponse with status 204>, endpoint: "/x")`; it returns nil.
  - Severity: minor. Behaviour change outside the packet, no test failure. Fixing it means changing `case 200..<300` back to `case 200` and updating `test204IsNil`.
- Checked and clean: `apiNotFound` is used only in `AppError+MultiTeam.swift` and the new test. The `apiGenericError` callers (`ClaudeAPIService.swift:431`, `:570`, the default branch, `AutoStartSessionService+Requests.swift`) do not depend on a 404 being generic.
