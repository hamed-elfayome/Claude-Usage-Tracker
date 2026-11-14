## Summary
Pure per-account rules U,L,M,T,S,R,X (`AccountRules.apply`) and `CredentialOrgParser`, with tests for AC1-21 plus edge cases.
No network/Keychain/Date(); thresholds follow spec §6.

## Changes
- Shared/MultiTeam/AccountRules.swift: types + rules, one private static func per rule.
- Shared/MultiTeam/CredentialOrgParser.swift: org/seat parsing, never throws.
- Claude UsageTests/AccountRulesTests.swift, CredentialOrgParserTests.swift: tests.

## Acceptance
AC1-21 met: one test each (comments "// ACn" in AccountRulesTests; parser tests = AC21). AC22: validate-clt.sh, 473 ok, 0 failed, 2 skipped (pre-existing).

## Flow
Caller (MT-3) builds AccountObservation -> apply(): U, L (may block), fingerprint store, M, T, S, R, record samples, X -> AccountResult.

## Tests
`scripts/validate-clt.sh`: Executed 475 tests: 473 ok, 0 failed, 2 skipped. `git diff --check` clean.

## Edge cases
API-only list (chat list empty) = no membership change (but lastOrgListAt set). Move target must be listed, not itself gone; move target is marked identity (skips S/R, baseline restarts). Ties on firstSeenAt: first in list. Pending (either kind) older than 30 min discarded. While needsLogin, samples are ignored unless fingerprint changed or a non-empty list arrived. A pair whose pending was resolved/created in a run does not get a fresh candidate that run. Not handled: first-sighting of an OAuth credential org on an empty state (MT-3).

## Shortcuts
none

## Lessons
`ClaudeUsage` fixtures differ by `lastUpdated`; compare fields, not whole structs. Closures passed to `state.updateOrg` must not read `self.now` of the same struct (exclusivity error).

## Fix round 1 (arch review)
- ruleL: L3 now needs `obs.oauthUnauthorized` in this call; counter resets to 0 when not unauthorized and (fingerprint changed or samples non-empty). Restore = fingerprintChanged || listSucceeded || samples non-empty.
- ruleS: sweep at start clears any pending older than 30 min (pair added to resolved); S1 clears a `.seatInferred` pending. ruleR: age check runs before the `present` guard; pending discarded when the window is absent.
- Minor: followed-org fallback in M excludes goneIds.
- Tests added: testL3LockoutClearedByNewFingerprint, testSuccessfulSampleRestoresLogin, testEarlyResetPendingClearedWhenWindowAbsent, testSeatFingerprintClearsInferredPending.
- Changed existing test testRefreshRejectedThenRestored: its "still blocked" step sent a sample, which now restores per spec; the step now sends no sample/list (a sample-restores case has its own test).
- Result: scripts/validate-clt.sh: Executed 479 tests: 477 ok, 0 failed, 2 skipped; git diff --check clean.
- MT-3 must state it handles the first sighting of an OAuth-only credential org on an empty state.
