## Tester result
All green (retest round 1).

## Suites run
- `bash scripts/validate-clt.sh` → "Executed 619 tests: 617 ok, 0 failed, 2 skipped", exit 0 (the 2 skips are the existing keychain tests; 614 from the fix round + 5 new).
- `git diff --check` → no output, exit 0.
- Mutation check (scratch copies of the worktree; production file in the worktree untouched; the mutant runs exit 129 only from the script's trailing `git diff --check` outside a git repo):
  - m1, `endGatedLivePoll` calls `rerun` before `release`: "619 tests: 612 ok, 5 failed", including the new `testEndGatedLivePollReleasesFirstAndOnce`, `testMovedWhileInFlightRerunsNewPairAfterFailedFetch` and `testRerunItselfRerunsWhenCurrentMovesAgain`.
  - m2, re-run whenever a target exists (same pair too): "610 ok, 7 failed", including the new `testMovedAwayAndBackWhileInFlightDoesNotRerun`, `testEndGatedLivePollReleasesFirstAndOnce` and `testRerunItselfRerunsWhenCurrentMovesAgain`.
  - m3, no re-run: "611 ok, 5 failed", including the new `testMovedWhileInFlightRerunsNewPairAfterFailedFetch`, `testRerunItselfRerunsWhenCurrentMovesAgain` and `testEndGatedLivePollReleasesFirstAndOnce`.

## New tests
The builder's fix round already covers each verdict "Tests to add" line: `testCurrentMovedWhileFetchInFlightFetchesNewPairOnceAfterRelease`, `testLiveSampleSwitchFetchesNewPairOnceAfterRelease`, `testSamePairPassWhileInFlightStaysDroppedWithoutRerun` and `testTrackedReadingReachesMenuBarOnlyWhileItsAccountIsShown`. I checked that each one asserts what its verdict line asks for. The tests below cover the edges of those lines that the builder left open.
File: `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift`, section "FU-2 tester, retest round 1". Every test drives the background-site seam (`startGatedLivePoll` + `endGatedLivePoll`) with a real `TeamTracker` and the production `onCurrentChanged` → pass hop. There are 5 tests.
- `testMovedWhileInFlightRerunsNewPairAfterFailedFetch`: a table over three ways B's fetch can fail after A was made current: timeout, `CancellationError`, and 429 (`Retry-After: 120`). In every case A is re-run exactly once, the re-run takes the gate, B's failure saves nothing, there is never more than one fetch in flight, and the gate ends free. The 429 row matters because a backoff on B must not suppress A's fetch.
- `testMovedAwayAndBackWhileInFlightDoesNotRerun`: while B is in flight, the current pair moves A → B. Both passes are dropped, and at release the target is the fetched pair again, so nothing re-runs (no duplicate B request).
- `testTrackerStoppedWhileInFlightReleasesWithoutRerun`: A is made current, then tracking is stopped while B is in flight. The release frees the gate and starts nothing.
- `testRerunItselfRerunsWhenCurrentMovesAgain`: a chain. While A's re-run is in flight, the current pair moves back to B, and A's release re-runs B once. B's own release ends the chain. Fetch order is [B, A, B], and there is never more than one fetch in flight.
- `testEndGatedLivePollReleasesFirstAndOnce`: pure ordering. The calls run as `release` and then `rerun` when the target moved, and only `release` for the same pair. Release runs exactly once either way.

## Bugs
None found.
Notes, from reading the code only (both are already documented, so I do not count them as bugs):
- The `.tracked` defer, the multi-mode loop defer, the `isShown` call site and the toggle reset are still covered only by reading, as the walkthrough states. I read them: each successful `begin()` reaches `endLivePoll` with the pair it fetched.
- The `ponytail` problem still applies. After the toggle goes off and on, a stale `end()` can clear a newer holder, and its re-run check can start one extra pass. That is one duplicate at most, it is documented, and I did not test it.
