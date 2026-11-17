## Tester result
all green

## Suites run
- `scripts/validate-clt.sh` (CLT mode) → `Executed 565 tests: 563 ok, 0 failed, 2 skipped` (EXIT=0). All 24 TeamTrackerTests ok. The 2 skips are the known ProfileKeychainMigrationTests.
- `git diff --check` → exit 0, no output.
- Mutation run (scratch only; source restored, `cmp` identical, gate rerun green afterwards) → `Executed 565 tests: 560 ok, 3 failed, 2 skipped`. Exactly the three verdict tests failed (see below).

## New tests
Retest round 2. The builder's fix round already added all three "Tests to add" lines from verdict.md, as the verdict specified. So I added no duplicates. I checked each one against the verdict and ran a mutation check on each:
- `Claude UsageTests/TeamTrackerTests.swift` → `testGroupMovePeerBackingOffIsUnchecked` (Tests to add 1, AC5 corrected). P1 has `lastOrgListAt = t0-30`, so the boot list cannot confirm. The test asserts no group move after boot. At round(0) P2's probe gets a 429. Then k2's list is set to orgsB, and the tick at t0+915 gives exactly one group move dated t0+915 with `unchecked == [P2]` and `list:k2 == 1`. Mutation: in `runGroupMove`, ignore the `forceList` result (`|| true`), so a backing-off peer is listed. The test FAILS.
- `Claude UsageTests/TeamTrackerTests.swift` → `testOAuthOnlyProbeOfCredentialOrgSavesClaudeUsage` (Tests to add 2). The account is OAuth-only and not current (P1 is current). After `setOAuth(p.id, u(33))`, boot and round(0): `savedUsage` for p is `[33]`, `onSample == [p.id]`, and organizationId stays nil with no orgId writes. Mutation: revert TeamTracker.swift:517 to `r.followedOrgId ?? p.organizationId` (the pre-fix code). The test FAILS.
- `Claude UsageTests/TeamTrackerTests.swift` → `testNeedsLoginSkipsDueListAndProbe` (Tests to add 3, AC9 at a time when the list is due). Boot lists k1 once, then `reportRefreshRejected(P1)` and a tick at t0+915: `list:k1` stays at 1, `usage:k1 == 0`, and the round ran. P2 is current, so the probe of P1's org-a would also be due. Mutation: drop the `authState == .ok` check from `listItem`. The test FAILS.

## Bugs
none. Must fix 1 is applied at `Claude Usage/Shared/MultiTeam/TeamTracker.swift:517`, exactly as the verdict wrote it.
