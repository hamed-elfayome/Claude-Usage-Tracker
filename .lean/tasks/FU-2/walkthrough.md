## Summary
Fix round 1. The one-in-flight `LivePollGate` no longer loses a pass for a *different* pair: when a tracker live fetch ends, `endGatedLivePoll` frees the gate first and then, if the tracker's live target moved to another pair meanwhile, runs `refreshUsage()` once (all three sites).
In single mode a tracker-owned reading reaches `usage`, the statusline cache and the icons only while its account is still the shown one (`showsFetchedReading`); its save and `ingestLive` are unchanged.
A pass for the *same* pair is still dropped and is never re-run, so the fix adds no duplicate request.

## Changes
- `Claude Usage/MenuBar/MenuBarManager.swift`:
  - `static func endGatedLivePoll(fetched:tracker:release:rerun:)` (~221): calls `release`, then `rerun` once when `tracker.liveTarget()` is non-nil and its pair differs from `fetched` (profile id or org id). Pure seam the tests drive with a real tracker.
  - `static func showsFetchedReading(trackerOwned:fetchedId:shownId:)` (~232): the stale-write rule, `!trackerOwned || fetchedId == shownId`.
  - `private func endLivePoll(fetched:)` (~279): wires the seam to `livePollGate.end()` and `refreshUsage()`.
  - The three gated sites now end through `endLivePoll` instead of a bare `end()`: background site release closure (~1529), single-mode `.tracked` defer (~1602), multi-mode loop defer (~1304).
  - Single-mode `.tracked` Task (~1636-1667): `self.usage`, the session-limit `updateMenuBarDisplay`, the statusline cache and `updateAllStatusBarIcons()` run only when `isShown`. `saveClaudeUsage`, notifications, auto-switch and `ingestLive` for the fetched account are unchanged (verdict part 1).
  - `ponytail` comment in `teamTrackingSettingChanged` (~330) now also names the re-run check; `LivePollGate` doc comment names the re-run.
- `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift`: section "FU-2 fix round 1": helpers `rerunningPass` (the background site's exact wiring: gate, poll, `endGatedLivePoll` whose re-run starts the pass again) and `passOnCurrentChanged` (the production `onCurrentChanged` → `refreshUsage()` hop), and 4 tests.

## Acceptance
Packet criteria:
1. Met. `testLivePollGateBeginEnd`.
2. Met. `testSecondLivePassWhileFirstInFlightDoesNotFetch` (fetcher called once); `testSamePairPassWhileInFlightStaysDroppedWithoutRerun` (the dropped duplicate is not re-run after the release either).
3. Met. `testLivePassFailureReleasesGate`; also cancel (`testCancelledLivePassReleasesGate`) and 429 (`testRateLimitedLivePassReleasesGateAndFetchesAfterBackoff`).
4. Met. Tracker off: `.legacy` never calls `begin()` or `endLivePoll`, and `showsFetchedReading(trackerOwned: false, …)` is always true (last assertion of `testTrackedReadingReachesMenuBarOnlyWhileItsAccountIsShown`), so every write runs as before. All 610 pre-existing tests pass unchanged.
5. Met. `testToggleOffWhileInFlightThenOnFetchesAgain`. With the tracker stopped, `liveTarget()` is nil, so an old fetch's end never re-runs.
6. Met. `bash scripts/validate-clt.sh`: "Executed 614 tests: 612 ok, 0 failed, 2 skipped", exit 0.

Verdict "Must fix":
- Part 1 (stale write in single-mode `.tracked`): met. `testTrackedReadingReachesMenuBarOnlyWhileItsAccountIsShown` (helper with the real `menuBarProfile` rule and a real tracker: B shown, A made current mid-fetch, tracker stopped). The call site (~1639) is covered by reading.
- Part 2 (re-run once after the release when the live target moved, all three sites): met. `testCurrentMovedWhileFetchInFlightFetchesNewPairOnceAfterRelease` (user `makeCurrent`) and `testLiveSampleSwitchFetchesNewPairOnceAfterRelease` (switch inside the fetch's own `ingestLive`), both through the background-site seam. The `.tracked` and multi-mode defers call the same `endLivePoll` (reading).
- Keep the same-pair skip: met. `testSamePairPassWhileInFlightStaysDroppedWithoutRerun`.

## Flow
- Inputs: the 30 s timer, `TeamTracker.onCurrentChanged` and the toggle all call `refreshUsage()`.
- Single mode, Codex shown: `backgroundLiveTarget` → `startGatedLivePoll(&livePollGate, release: endLivePoll(fetched))` → Task { defer release; `pollLiveTarget` → fetch → save → `tracker.ingestLive` }. If that sample moves the current pair, `onCurrentChanged` → `refreshUsage()` runs synchronously and finds the gate busy (dropped). Then release → `endGatedLivePoll`: `livePollGate.end()`, then `liveTarget()` ≠ fetched pair → `refreshUsage()` once, which now takes the gate.
- Single mode, anthropic shown: `shownFetchPlan` → `.tracked` → `begin()` → Task: fetch → MainActor block { `isShown = showsFetchedReading(…, shownId: menuBarProfile?.id)`; if shown: `usage`, display rebuild, statusline, icons; always: save, notify, `ingestLive` } → end of the usage block: defer → `endLivePoll(fetched)`.
- Multi mode: `multiFetchPlan` → `begin()` when `liveOrgIds` is not empty → the loop visits the current account first; its usage block's defer → `endLivePoll(fetched)`; a re-run starts a fresh `refreshAllSelectedProfiles()` pass.
- Toggle off: `tracker.stop()` → `livePollGate = LivePollGate()`; an old fetch's end then sees `liveTarget()` nil and does not re-run.

## Tests
- `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift`, section "FU-2 fix round 1" (real `TeamTracker`, fake fetch parked on a continuation, a counter of fetches in flight):
  - `testCurrentMovedWhileFetchInFlightFetchesNewPairOnceAfterRelease`: B parked, `makeCurrent(A)` → A's pass dropped; resume B → exactly one re-run, A fetched once, never two in flight, A's own release does not re-run, B's reading still saved.
  - `testLiveSampleSwitchFetchesNewPairOnceAfterRelease`: OAuth-only B whose credential now names org-a; B's sample moves current to (B, org-a) inside `ingestLive` (pass dropped); after the release (B, org-a) is fetched once and sampled. Same profile, other org: pins the org-id half of the pair comparison.
  - `testSamePairPassWhileInFlightStaysDroppedWithoutRerun`: a timer pass for B while B is in flight is dropped, and B's release starts nothing.
  - `testTrackedReadingReachesMenuBarOnlyWhileItsAccountIsShown`: the stale-write rule over shown / moved / stopped, and today's path never filtered.
- Command: `bash scripts/validate-clt.sh` → "Executed 614 tests: 612 ok, 0 failed, 2 skipped" (the 2 skips are the existing keychain tests), exit 0. `git diff --check` → no output, exit 0.
- Mutation check (scratch copies, production file in the worktree untouched; trimmed suite = Fixtures + this test file):
  - No re-run in `endGatedLivePoll` + `showsFetchedReading` always true: "29 tests: 26 ok, 3 failed": `testCurrentMovedWhileFetchInFlightFetchesNewPairOnceAfterRelease` (:673, 0 != 1), `testLiveSampleSwitchFetchesNewPairOnceAfterRelease` (:714), `testTrackedReadingReachesMenuBarOnlyWhileItsAccountIsShown`. The same-pair test stays green, as it should.
  - Re-run whenever a target exists (same pair too): "26 ok, 3 failed": `testSamePairPassWhileInFlightStaysDroppedWithoutRerun` (:740), plus the two re-run tests (:682 and :722, 2 != 1 re-runs).
  - Pair compared by profile id only: "28 ok, 1 failed": `testLiveSampleSwitchFetchesNewPairOnceAfterRelease` (:714).
  - (The mutant runs end with exit 129 from the script's trailing `git diff --check` in a non-git scratch copy; the runner lines above are the test outcome.)
- Covered by reading only (`MenuBarManager` needs `ProfileManager.shared`, `TeamTracker.shared` and a status bar): the `isShown` call site, the `endLivePoll` calls in the `.tracked` defer and the multi-mode loop defer, the reset in `teamTrackingSettingChanged`.

## Edge cases
- Handled: current moved by the user, or by the fetch's own live sample, while a fetch is in flight → the release re-runs once (`endGatedLivePoll`). The release runs after `ingestLive`, so a switch the sample itself causes is seen.
- Handled: same profile, other org → the pair is compared by profile id and org id, so it re-runs.
- Handled: same pair → no re-run (no added request).
- Handled: the new target backed off (429 on the same account) or the tracker stopped → `liveTarget()` nil → no re-run.
- Handled: failure and cancellation still reach `endLivePoll` (defers).
- Handled: the gate is freed before the re-run, so the re-run takes it; never two tracker fetches in flight (`maxFetchesInFlight == 1`).
- Handled: B's late reading while A is shown is saved to B and given to the tracker, but not shown; B's threshold notification keeps B's own name and settings (unchanged).
- Not handled: toggle off/on during a fetch: the old fetch's `end()` can clear a newer holder, and its re-run check can start one more pass (the `ponytail`).
- Not handled (by design, same as before FU-2): a re-run repeats the whole pass, so in multi mode status and console billing run again and with Codex shown the Codex fetch runs again. That is the pass `onCurrentChanged` started at once before FU-2, so the request count matches pre-FU-2.
- Not handled (pre-existing, outside FU-2): a `.legacy` fetch started with the tracker off still writes `usage` if tracking is turned on mid-fetch.

## Shortcuts
- `ponytail:` in `teamTrackingSettingChanged` (disabled branch): a stale `end()` after a toggle off/on can clear a newer fetch's gate, and its re-run check can start one more pass (one duplicate at most). Upgrade path: `begin()` returns a generation token, `end(token)` and the re-run check act only for a matching generation.

## Lessons
- `TeamTracker.onCurrentChanged` fires synchronously inside `ingestLive` (and `makeCurrent`), so any pass it starts while a gated fetch is still running always finds the gate held. A gate that drops passes must re-check the tracker's live target after it releases, or the new current account waits a full timer interval.
