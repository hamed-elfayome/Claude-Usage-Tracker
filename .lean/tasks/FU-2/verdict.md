## Verdict
FAIL. The hunter's major finding holds when I read the code. While a fetch of the old pair is in flight, the gate drops the refresh for the new current pair. The old fetch then writes its reading into the single-mode `self.usage`, so the menu bar shows the previous account's usage under the new current account until the next timer pass.

## How it's going
Grade C. The gate is small and correct for the duplicate-of-the-same-pair case. All release paths use a `defer` (I checked the single, multi and background sites), and the tests are real and not hollow.
But one plain bool gate also swallows passes for a *different* pair. That turns a race the old code healed within about a second into wrong data on screen for up to a whole refresh interval.

## Done well
- `LivePollGate` is minimal. The multi-mode release invariant is pinned by `testMultiFetchPlanLiveAccountIsReleasable`.
- `startGatedLivePoll` is a clean test seam. Success, throw, cancel and 429 all release the gate, and the tests drive the production helper.
- No test was weakened or deleted. No skip, xfail or ignore was added. Only the two allowed files changed. Gates are green (610 tests, 0 failed; `git diff --check` clean).

## Must fix
- `Claude Usage/MenuBar/MenuBarManager.swift`, single-mode `.tracked` Task (around lines 1565-1640).
  - Problem: when `onCurrentChanged` fires during an in-flight fetch of pair B, the handler (line 261-268) sets `usage` to A's cached value. Its `refreshUsage()` is then dropped by the gate. When B's fetch ends, it runs `self.usage = newUsage` and `updateAllStatusBarIcons()` with B's reading while `menuBarProfile` is A. Nothing fetches A until the next timer pass.
  - The same drop happens every time a live sample switches the current account: `ingestLive`, then `moveCurrent`, then `onCurrentChanged`, which runs synchronously while the gate is still held (see the tester's note). Before FU-2, the new current account was fetched at once.
  - Exact change, part 1: when tracker-owned, write `self.usage`, the statusline cache and the icons only if `profile.id == self.menuBarProfile?.id`. The `saveClaudeUsage` and `ingestLive` calls for B stay as they are.
  - Exact change, part 2: after the gate is released, if the tracker's `liveTarget()` is non-nil and differs from the pair just fetched (profile id or org id), call `refreshUsage()` once. That restores the immediate fetch of the new current account. Apply the same re-run in the `startGatedLivePoll` release path (background site) and the multi-mode loop `defer`.
  - Keep the gate's skip for a pass that targets the *same* pair. That is the duplicate the packet exists to stop.

## Tests to add
- Through the seam (background site): B's fetch is parked, then `tracker.makeCurrent(A)`, then B is resumed. Expected: A is fetched once after B's release with no new timer pass, and there are never two fetches in flight at once.
- Live-sample switch: B's fetch returns a reading that makes the tracker move the current account to A. Expected: after the release, A is fetched once.
- Same pair: a pass for B while B is in flight. Expected: still dropped, with no re-run fetch of B after the release (guards against the fix doubling requests).
- If the stale-write guard is pulled into a pure helper, test it. Expected: a tracker-owned reading for B is not applied while A is shown, and is applied while B is shown.

## Hunter
- Major (gate drops the new current pair's refresh, and the stale old-pair reading is shown in single mode): CONFIRMED by reading.
  - Line 1516: the gate is a plain bool, so `begin()` returns false for any pair.
  - Line 265: `onCurrentChanged` sets the cached A value. Then `self.usage = newUsage` in the `.tracked` Task runs with no check against `menuBarProfile`.
  - Before FU-2, A's own fetch overwrote it. Now nothing does until `refreshInterval`.
  - I did not rerun the repro test. Its only runtime claim, that the second `begin()` returns false, follows directly from the single-bool gate.

## Improve later
- The stale `end()` after a toggle off and on can clear a newer holder (the documented `ponytail`). Fix it with a generation token in `begin()`/`end()`.
- The `.tracked` site, the multi-mode loop `defer` and the toggle reset are covered only by reading. Consider pulling out small pure helpers so they can be tested.
