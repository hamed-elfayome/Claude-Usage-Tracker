## Summary
Pure per-account rules U,L,M,T,S,R,X (`AccountRules.apply`) and `CredentialOrgParser`, with tests for AC1-21 plus edge cases.
No network/Keychain/Date(); thresholds follow spec §6.

## Changes
- Shared/MultiTeam/AccountRules.swift: types + rules, one private static func per rule.
- Shared/MultiTeam/CredentialOrgParser.swift: org/seat parsing, never throws.
- Claude UsageTests/AccountRulesTests.swift, CredentialOrgParserTests.swift: tests.

## Acceptance
AC1: met - testAdminMoveAfterThreeLists (ok)
AC2: met - testMembershipFailureConfirmsImmediately (ok)
AC3: met - testPeerConfirmedRemoval (ok)
AC4: met - testNilOrEmptyListChangesNothing (ok)
AC5: met - testTeamRemovedWithoutTarget (ok)
AC6: met - testRejoin (ok)
AC7: met - testNewOrgAdded (ok)
AC8: met - testOAuthOnlyTeamChange (ok)
AC9: met - testSeatChangeFingerprint, testSeatSourceChangeIsSilent (ok)
AC10: met - testInferredSeatChangeConfirmed, testInferredSeatChangeDiscarded, testMaxToProShapeIsSeatCandidate (ok)
AC11: met - testEarlyResetConfirmed, testEarlyResetBounceBack (ok)
AC12: met - testNaturalResetSnapshotOnly (ok)
AC13: met - testResetTimeMovedWithoutDropIsQuiet (ok)
AC14: met - testNoFiveHourSampleGivesNoSessionEvent (ok)
AC15: met - testStalePendingDiscarded (ok)
AC16: met - testRefreshRejectedThenRestored (ok)
AC17: met - testListAuthFailedNeedsLogin, testOAuthUnauthorizedTwice (ok)
AC18: met - testOldTeamExpiry (ok)
AC19: met - testUnknownOrgRenamed, testUnresolvedPlaceholderIsNeverConfirmedGone (ok)
AC20: met - testSampleForOldOrgIgnored (ok)
AC21: met - CredentialOrgParserTests (all) (ok)
AC22: met - scripts/validate-clt.sh: Executed 492 tests: 490 ok, 0 failed, 2 skipped (pre-existing).

## Flow
Caller (MT-3) builds AccountObservation -> apply(): U, L (may block), fingerprint store, M, T, S, R, record samples, X -> AccountResult.

## Tests
`scripts/validate-clt.sh`: Executed 492 tests: 490 ok, 0 failed, 2 skipped. Round 1 added testUnresolvedPlaceholderIsNeverConfirmedGone, testMaxToProShapeIsSeatCandidate, testPerModelWindowsQualifyWhenPresent. `git diff --check` clean.

## Edge cases
Round 1: unknown-org placeholder is never counted missing (only U removes it); per-model windows (opus/sonnet) count only when new value > 0 because the API maps null to 0.
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

## Round 2 fix
- Root cause: round 1 patched the "missing" loop only; the followed-org fallback in `ruleM` (AccountRules.swift ~276) used the same candidate set without the `TrackedOrg.unknownOrgId` exclusion. Added it.
- Test added: `testFollowedFallbackNeverPicksPlaceholder` (placeholder first in state order, A followed, list [B,C] twice -> `teamRemoved(A)`, `followedOrgId == "B"`). Fails without the exclusion.
- Result: `scripts/validate-clt.sh` -> `Executed 493 tests: 491 ok, 0 failed, 2 skipped`, rc=0; `git diff --check` clean.
