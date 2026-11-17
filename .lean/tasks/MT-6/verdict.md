## Verdict PASS — both round-1 Must fix lines are fixed, the 3 requested tests exist and each fails without its feature, and my STRICT gate rerun is green
PASS. This is round 2 of the re-review. The OAuth-only invariant-3 fix is applied exactly as the verdict wrote it. The AC5 test now depends on the 429 backoff. The AC9 "no lists while needsLogin" case is tested at a time when the list is due. I checked all three with my own mutation runs.

## How it's going
Grade B. The fix round is small and exact: one line in `process`, one corrected test and two new tests. No other code changed.
Every acceptance criterion now has a test that fails when its feature is removed. A few edge gaps that do not block remain below.

## Done well
- Must fix 1 (`TeamTracker.swift:517`) matches the verdict word for word. `AccountRules.swift:126` keeps the stored `credentialOrgId` when the token has none. So `r.state.credentialOrgId` is exactly the org that `runRound` probed (`credentialOrg(for:).orgId ?? state.credentialOrgId`).
  - Session-key accounts are unchanged.
  - Live readings still never save (`source != .live`).
  - `organizationId` is still never written for OAuth-only accounts (the test asserts this).
- Must fix 2: every item of the exact change is in `testGroupMovePeerBackingOffIsUnchecked`. It also asserts that the move is dated t0+915.
- `testNeedsLoginSkipsDueListAndProbe` covers both guards, `listItem` and `runRound`, at a time when both are due. The call keys match the fake (`list:<key>`, `usage:<key>|<org>`, `oauth:<uuid>`), so the zero-count asserts really check something.
- My mutation runs (scratch copies, `scripts/validate-clt.sh --root`):
  - Copy A had three changes: the old invariant-3 line, the AC5 test without its 429 line, and no auth check in `listItem`. Result: `Executed 565 tests: 560 ok, 3 failed, 2 skipped`. Exactly the 3 target tests failed:
    - `:269 Optional([]) != Optional([P2])` and `:270 3 != 1`;
    - `:366 2 != 1` and `:367 1 != 0`;
    - `:435 [] != [33.0]` and `:436 [] != [<id>]`.
  - Copy B listed group-move peers even while backing off: `562 ok, 1 failed`. Only `testGroupMovePeerBackingOffIsUnchecked` failed (`:270 Optional([]) != Optional([P2])`, `:271 2 != 1`).
  - These match the builder's and tester's reported numbers.
- STRICT gate rerun in the worktree: `scripts/validate-clt.sh` gave `Executed 565 tests: 563 ok, 0 failed, 2 skipped` and EXIT=0. That includes the script's own `git diff --check`.
  - All 24 TeamTrackerTests passed, with 0 compile errors.
  - The 2 skips are the known ProfileKeychainMigrationTests keychain skips.
- Footprint:
  - Since d2dcd10, only the packet's files and `.lean` docs changed.
  - The project uses synchronized folders (PBXFileSystemSynchronizedRootGroup), so no pbxproj edit is needed.
  - Tests went from 20 at HEAD to 24, with 0 removed (checked with `comm`).
  - No skip, xfail or disable markers were added, and the skip list is unchanged.
  - The test HEAD already had (`testSessionKeyAdded…`) only gained assertions.
- walkthrough.md `## Acceptance` now has one line per criterion, each naming its test, with the current counts.

## Must fix
None.

## Tests to add
None required.

## Hunter
- No findings were reported (an empty list), so there was nothing to confirm or reject.
- Gemini was not available this round.

## Improve later
- `makeCurrent` accepts an `old` or `unreachable` pair. Add a guard `status == .member`.
- When a group-move peer's forced list returns 401, the observation is dropped and `orgListAuthFailed` is never applied.
- The OAuth "no sample" check is skipped when `lastSampleAt` is nil, for example on a pair that rule T just added. After this round's fix, such a cached fall-back also fires `onSample` and writes the same cached value back to `claudeUsage`. Also reject `usage.lastUpdated <= p.claudeUsage?.lastUpdated`.
- When rule U renames during `ingestLive` success, `followedOrgId` is set, so `saveClaudeUsage` runs. It saves the same value the loop would save.
- The arch notes still apply:
  - a stop during a group move loses the withheld event;
  - the background forced-list Task runs outside `isTicking`;
  - `tick` returns early before persisting;
  - each round writes about 2N profiles, so MT-7 must check the observers of `profiles`.
