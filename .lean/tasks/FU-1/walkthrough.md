## Summary
Closed four TeamTracker failure modes. `makeCurrent` now refuses pairs that can never be live. A peer's 401 during a group move now applies rule L. An OAuth-only first reading older than one round no longer counts as a sample.
BoundedTaskRunner ignores a non-finite timeout (it starts no timer) and clamps a finite one to the range 0 to 86,400 s, so it can no longer trap.
Added 12 tests. The full CLT suite is green, and mutation runs show the new tests fail without the fixes.

## Changes
- `Claude Usage/Shared/MultiTeam/TeamTracker.swift`: three edits.
  - `makeCurrent` guard: the org must be `.member`, `authState` must be `.ok`, and the account must not be backing off. These are the conditions `liveTarget()` uses. `now` is read before the guard.
  - `runGroupMove`: when the list result has `orgListAuthFailed`, the code calls `apply(..., withholding: [], allowGroup: false)` without `peerConfirmedRemovals` and marks the peer `.unchecked`.
  - `runRound` OAuth check: a reading counts only when `usage.lastUpdated > (lastSampleAt ?? now - policy.roundInterval)`.
- `Claude Usage/Shared/MultiTeam/BoundedTaskRunner.swift`: the timer starts only when `timeout` is set and finite. The value is clamped to `min(max(0, t), 86_400)`.
- `Claude UsageTests/Fixtures/TeamTrackerFakes.swift` (not named in the packet, but the change was unavoidable): `setOAuth` gains `lastUpdated: Date = .distantFuture`.
  - Why: test clocks are set in 2027, but `ClaudeUsage.lastUpdated` is wall-clock now. The new cutoff would otherwise reject the reading in the existing `testOAuthOnlyProbeOfCredentialOrgSavesClaudeUsage`.
  - The default models a fresh fetch, and the existing test is unchanged.
- `Claude UsageTests/TeamTrackerTests.swift`: 9 new tests for AC1-4, 6, 7, 8 and 9, plus the backoff edge case.
- `Claude UsageTests/BoundedTaskRunnerTests.swift`: 3 new tests (infinity, NaN, and a huge finite timeout of 1e300).

## Acceptance
1. Met: `testMakeCurrentRefusesOldPair`.
2. Met: `testMakeCurrentRefusesUnreachablePair`.
3. Met: `testMakeCurrentRefusesPairOfLoggedOutAccount`.
4. Met: `testMakeCurrentRefusesPairOfBackingOffAccountThenAcceptsHealthyPair`. The test also includes a healthy-pair control.
5. Met: `testManualPickHoldsOneRound` (existing) still passes, and so does the control in the AC4 test.
6. Met: `testGroupMovePeerListUnauthorizedAppliesRuleLAndCountsUnchecked`. P2 ends in `needsLogin("claude.ai session expired", since: t0)` with a `loginLost` event, org-a stays `.member`, and the group move lists P2 as unchecked.
7. Met: `testGroupMovePeerListCloudflareLeavesPeerUnchanged`.
8. Met: `testOAuthOnlyFirstReadingOlderThanOneRoundIsNoSample`.
9. Met: `testOAuthOnlyFirstReadingAtRoundTimeIsSample`.
10. Met: `testInfiniteTimeoutReturnsAllResults`.
11. Met: `testNaNTimeoutReturnsAllResults`.
12. Met: `bash scripts/validate-clt.sh` reports "Executed 612 tests: 610 ok, 0 failed, 2 skipped". The 2 skips are the existing keychain skips (ad-hoc signing). No existing test was changed.

## Flow
- UI → `TeamTracker.makeCurrent(pair)`:
  - The guard now checks profile, then `orgTracking`, then `authState`, then org status, then `scheduler.isBackingOff`.
  - If the guard fails, the call returns with no state change.
  - Otherwise it sets `manualPickAt`, calls `moveCurrent` and then `persistGlobal`.
- Group move path:
  - Either `ingestLive` (404) → `forcedLists` → `applyAndRun`, or `runDueLists` → `applyAndRun`. Both reach `apply`, which builds a `GroupJob`, then `runGroupMoves` → `runGroupMove`.
  - `runGroupMove` calls `fetchLists` (`BoundedTaskRunner`, 60 s timeout), then `listObservation` for each peer.
  - New branch: an obs with `orgListAuthFailed` goes to `apply` (AccountRules rule L sets needsLogin and emits `loginLost`), and the peer becomes `.unchecked`.
  - The outcomes then go to `GroupMoveAggregator.event`.
- `tick` → `runRound`: for an OAuth-only item, the reading must be newer than `lastSampleAt`, or newer than `now - roundInterval` when there is no sample yet. Otherwise the code hits `continue`: no `scheduler.record`, no sample, no `onSample`.
- `BoundedTaskRunner.run`: when `timeout` is set and finite, it is clamped and a sleep task is added that returns `.timedOut`. Otherwise no timer starts.

## Tests
- `Claude UsageTests/TeamTrackerTests.swift`:
  - makeCurrent refusals (old, unreachable, needsLogin, backoff), with a healthy control in the backoff test.
  - Group-move peer list 401 (rule L, unchecked), Cloudflare (unchanged, unchecked), and a backing-off peer (no list, no apply, unchecked).
  - OAuth first reading older than one round (rejected) and at round time (accepted).
- `Claude UsageTests/BoundedTaskRunnerTests.swift`: `.infinity`, `.nan` and 1e300 timeouts all return `[1, 2, 3]`.
- Command: `bash scripts/validate-clt.sh` → "Executed 612 tests: 610 ok, 0 failed, 2 skipped", exit 0. `git diff --check` → clean.
- Mutation runs:
  - Reverting `TeamTracker.swift` to HEAD fails exactly these 6 tests: 4 makeCurrent, the AC6 test, and the AC8 test.
  - Reverting `BoundedTaskRunner.swift` traps with "Double value cannot be converted to UInt64 because it is either infinite or NaN".
  - Under the old code, `max(0, .nan)` returns 0, which gives a zero timer. The NaN test then sees nil results and fails.

## Edge cases
- Handled:
  - A peer in backoff during a group move: `forceList` returns false, so the peer is unchecked and no apply runs (test added).
  - A Cloudflare challenge on the peer list: `listObservation` returns nil, so the peer is unchecked and unchanged.
  - A reading exactly at `now - roundInterval`: rejected, because the check is `<=`.
  - A huge finite timeout: clamped to 86,400 s.
  - A negative timeout: clamped to 0 (as before).
- Not handled: a 401 on the trigger's own list. That goes through `runDueLists` / `forcedLists` and was already handled; it is out of scope.

## Shortcuts
- None. No `ponytail:` comments.

## Lessons
- Test clocks (`t0` around 1.8e9, in 2027) are ahead of the wall clock, and `ClaudeUsage` stamps `lastUpdated` with `Date()`. Any rule that compares `lastUpdated` with the tracker's `now` needs an explicit stamp in fakes (`FakeTeamFetcher.setOAuth(..., lastUpdated:)`).
- In Swift, `max(0, Double.nan)` returns 0, not NaN. A NaN timeout therefore silently became a zero timer rather than a trap. Check `isFinite` before converting.
- The packet's `policy.round` is `PollPolicy.roundInterval` in the code.
