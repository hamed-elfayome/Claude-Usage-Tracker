## Summary
Fix round 2 (review r1 = FAIL, 2 must-fix lines). A probe of a non-current OAuth-only account now updates its `claudeUsage` and fires `onSample`. Root cause: `process` took `organizationId` as every account's followed org, but that field is set only for session-key accounts (spec §3 invariant 2). OAuth-only accounts follow their credential org (§4, §6 T), which is kept in `state.credentialOrgId`.
The AC5 test is no longer hollow. Root cause: P1 started with `missing: 1` and no `lastOrgListAt`, so its boot list confirmed the move at t0, before P2's 429. The group move now fires at t0+915 while P2 is backing off, and P2 has a list that would say "moved". The verdict's AC9 test (no lists while `needsLogin`, at a time the list is due) is added.
A stopped run had already written these edits after the verdict but never ran them. This round checked each edit against the code and the spec, then ran the full suite (green) and two mutation runs (each new test fails without its feature).

## Changes
- `Claude Usage/Shared/MultiTeam/TeamTracker.swift` (`process`, invariant-3 block, lines 513-521): `followed = r.followedOrgId ?? (session key ? p.organizationId : r.state.credentialOrgId)`, plus a comment explaining why. This is the verdict's exact change. The round-1 `syncAccounts` fix is still uncommitted and unchanged.
- `Claude UsageTests/TeamTrackerTests.swift`, `testGroupMovePeerBackingOffIsUnchecked` (Must fix 2): `three[0].lastOrgListAt = t0-30`, so the boot list cannot count A missing. It asserts no group move after boot, gives k2 an `orgsB` list after round 0, then at t0+915 asserts exactly one group move dated t0+915 with `unchecked == [P2]` and `list:k2 == 1`.
- `Claude UsageTests/TeamTrackerTests.swift`, new `testOAuthOnlyProbeOfCredentialOrgSavesClaudeUsage` (verdict "Tests to add" 2, the Must fix 1 regression test).
- `Claude UsageTests/TeamTrackerTests.swift`, new `testNeedsLoginSkipsDueListAndProbe` (verdict "Tests to add" 3).
- `.lean/tasks/MT-6/walkthrough.md`: rewritten for this round, with one criterion per line and current counts (the verdict's "Improve later" walkthrough note).

## Acceptance
- Must fix 1 (OAuth-only probe → `claudeUsage`): met. `testOAuthOnlyProbeOfCredentialOrgSavesClaudeUsage` ok. Mutation copy A, with the old `r.followedOrgId ?? p.organizationId` line, gives `TeamTrackerTests.swift:436 [] != [33.0]` and `:437 [] != [<id>]`. That is the verdict's repro.
- Must fix 2 (AC5 test hollow): met. `testGroupMovePeerBackingOffIsUnchecked` ok.
  - Copy A, where group-move peers are listed even while backing off: `:270 Optional([]) != Optional([P2])`, `:271 2 != 1` (list:k2).
  - Copy B, the test with its 429 line removed (verdict probe A): `:269 Optional([]) != Optional([P2])`, `:270 3 != 1`. Only this test fails, so it is no longer hollow.
- Tests to add 3 (AC9, no lists while `needsLogin` when the list is due): met. `testNeedsLoginSkipsDueListAndProbe` ok. Copy A, where `listItem` has no `authState == .ok` check: `:367 2 != 1` (list:k1). Then `:368 1 != 0`, because the list restores login and the round probes P1.
- AC1 detected switch: met, `testDetectedSwitchNotifiesOnceThenFlapGuard`.
- AC2 manual pick: met, `testManualPickHoldsOneRound`.
- AC3 admin move: met, `testAdminMoveFromProbe`, `testAdminMoveCurrentFollowsViaLiveFailure`.
- AC4 group move: met, `testGroupMoveOneNotificationAndNotMoved`.
- AC5 group move with a backing-off peer: met, `testGroupMovePeerBackingOffIsUnchecked` (corrected this round, see Must fix 2).
- AC6 seat change: met, `testSeatChangeNotifiesOnce`.
- AC7 early reset: met, `testEarlyResetViaIngestLiveRecordsHistory`.
- AC8 429: met, `testRateLimitedAccountSkippedAndLiveTargetNil`.
- AC9 login loss: met, `testLoginLossAndRestoreByFingerprint` + `testNeedsLoginSkipsDueListAndProbe`.
- AC10 migration: met, `testLegacyProfileRecordsHistoryUnderUuid`.
- AC11 old team: met, `testOldTeamExpiryAndManualDelete`.
- AC12 invariant 3: met, `testProbeOfFollowedOrgSavesClaudeUsageOthersDoNot` (session key) + `testOAuthOnlyProbeOfCredentialOrgSavesClaudeUsage` (OAuth-only).
- AC13 stop during a round: met, `testStopDuringRoundPersistsNothing`.
- AC14 tracking disabled: met, `testDisabledStartDoesNothing`.
- AC15 full suite: met. `scripts/validate-clt.sh` → `Executed 565 tests: 563 ok, 0 failed, 2 skipped`, `EXIT=0`. This includes the script's own `git diff --check`. The 2 skips are the known ProfileKeychainMigrationTests keychain skips.

## Flow
- OAuth-only probe (Must fix 1):
  - `tick` → `runRound`: an account with no session key and a credential gets one `ProbeItem` for `credentials.credentialOrg(p).orgId ?? state.credentialOrgId`, if that pair is an eligible `member`.
  - → `fetcher.fetchUsageViaProvider(p)` → `Gathered.samples[org]`.
  - → `applyAndRun` → `apply` → `AccountRules.apply`: `recordSamples` puts the sample in `acceptedSamples`, and line 126 writes `obs.credentialOrgId` into `state.credentialOrgId`.
  - → `process`: for a non-current account, the followed org is `r.followedOrgId` (a change, for example rule T), else `organizationId` (session key), else `r.state.credentialOrgId` (OAuth-only). Its accepted sample → `store.saveClaudeUsage` + `onSample`. `organizationId` is never written for OAuth-only accounts.
- AC5 test timeline:
  - boot t0: P1's list is debounced (last list 30 s ago), so A stays at `missing 1`. P3 counts A missing once. P2's list fails, so its next list is t0+900.
  - round 0 (t0+15): P2's probe gets a 429 with Retry-After 3000, so P2 backs off until t0+3015.
  - t0+915: P1's and P3's lists are due. Whichever is applied first counts A missing twice and confirms it gone. `runGroupMove` → `scheduler.forceList(P2)` returns false (backing off) → `.unchecked`. The other peer is force-listed and moved. One `groupMove` is logged.

## Tests
- `Claude UsageTests/TeamTrackerTests.swift`: 24 tests, up from 20 at HEAD (`comm` of the names: 0 removed, 4 added, 2 of them this round).
  - Criteria 1-14.
  - The round-1 arch fix (3 tests).
  - The 3 tests this verdict asked for: AC5 corrected, OAuth-only claudeUsage, AC9 lists while `needsLogin`.
  - Edge cases: profile deleted mid-probe, Cloudflare probe, same org id on two profiles, no profiles.
  - Command `scripts/validate-clt.sh` (CLT mode, no full Xcode): `Executed 565 tests: 563 ok, 0 failed, 2 skipped`, `EXIT=0`. All 24 TeamTrackerTests ok.
- `git diff --check`: exit 0.
- Mutation runs (scratch copies, `scripts/validate-clt.sh --root <copy>`; `EXIT=129` there only because the copy has no `.git`):
  - Copy A, 3 code mutations (old invariant-3 line; peers listed while backing off; no `authState` check in `listItem`): `Executed 565 tests: 560 ok, 3 failed, 2 skipped`. The 3 failures are exactly the 3 tests above.
  - Copy B, the AC5 test without its 429 line: `Executed 565 tests: 562 ok, 1 failed, 2 skipped`. The one failure is `testGroupMovePeerBackingOffIsUnchecked`.
- `Claude UsageTests/Fixtures/TeamTrackerFakes.swift`: unchanged.

## Edge cases
- Handled (`process`): an OAuth-only account whose credential org changes in the same apply. Rule T sets `followedOrgId = C1`, so `r.followedOrgId` wins over `credentialOrgId`.
- Handled: credential org unknown (no org in the token and none stored). `runRound` probes nothing, and `followed` is nil, so nothing is saved.
- Handled: the current account is never saved by the invariant-3 block (guard `global.current?.profileId != id`). Live success still never saves (`source != .live`).
- Handled: an OAuth-only account that is also current. `moveCurrent` saves its pair's `lastUsage` on a switch, and the loop saves live readings (MT-7).
- Checked for the same root cause, no change needed (other reads of `organizationId`):
  - `apply` passes nil as `followedOrgId` for OAuth-only accounts. AccountRules uses `followed` only in list paths and in rule U's `followed == unknown`, and rule T sets it itself.
  - `repairCurrent` falls back to the first member org.
  - `moveCurrent` and `process` write `organizationId` only for session-key accounts.
- Not handled (out of scope, "Improve later" in the verdict): `makeCurrent` on an `old` pair; a group-move peer's 401 list is not applied; the OAuth "no sample" check when `lastSampleAt` is nil; rule U renaming during `ingestLive`; arch notes 1-4.

## Shortcuts
- No new `ponytail:` comments. Kept from the build: init params `isEnabled` and `runsLoop` (both have defaults) beyond the packet signature, so tests can run without the loop. `shared` and the §10 contract are unchanged.

## Lessons
- "Followed org" depends on the account type. Session key: `profile.organizationId` (spec §3 invariant 2). OAuth-only: `state.credentialOrgId`; `organizationId` is nil there and the tracker must never write it. Any code that needs "the followed pair" must branch on `credentials.sessionKey(for:)`.
- In a group-move test, a trigger with `missing: 1` and no `lastOrgListAt` confirms the removal at the boot list, before any probe runs. Set `lastOrgListAt` less than 60 s before t0 to debounce the boot count, and give every peer a list, so "unchecked" can only come from the condition under test.
- Mutation runs: copy the tree without `build` and `.git` to a scratch dir, mutate it there, and run `scripts/validate-clt.sh --root <copy>`. Read the `Executed` line: the final `git diff --check` fails there because the copy is not a git repo.
