## Summary
Added `LivePollGate`, which lets only one Team-tracking live fetch of the current pair run at a time, across the three tracker live-fetch sites in `MenuBarManager`.
When a pass finds the gate busy, it skips the usage fetch and keeps the cached value, the same way the existing `.skip` does.
A `defer` in the async body releases the gate after success, failure or cancellation. When tracking is turned off, the gate is reset.

## Changes
- `Claude Usage/MenuBar/MenuBarManager.swift`:
  - Added `struct LivePollGate` at the end of the file.
  - Added `private var livePollGate`.
  - Added the static helper `startGatedLivePoll(gate:release:poll:)`, which the background (Codex-shown) poll site uses. It is also the test seam.
  - Gated the single-mode `.tracked` branch. When the gate is busy, that branch falls through to the skip path, and a `defer` in the `if !skipsUsage` block releases the gate.
  - Gated the multi-mode current-account fetch. When the gate is busy, `liveOrgIds` is emptied and the current account is added to `usageSkip`. A `defer` in the loop's usage block releases the gate at the current account.
  - Reset the gate in the disabled branch of `teamTrackingSettingChanged`.
- `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift`: added 4 tests (FU-2 section). They use a real tracker and a fake fetch that waits on a continuation.

## Acceptance
1. Met. `testLivePollGateBeginEnd`.
2. Met. `testSecondLivePassWhileFirstInFlightDoesNotFetch`: two passes start back to back, the second both before and after the first fetch is suspended, and the fetcher is called once. Once it ends, the next pass fetches.
3. Met. `testLivePassFailureReleasesGate`: the fetch throws `URLError`, after which `gate.inFlight` is false and the next pass fetches.
4. Met. The tracker-off and codex/legacy paths are not gated (`.legacy` is untouched, and multi mode only calls `begin()` when `plan.liveOrgIds` is not empty, which is empty with the tracker off). All existing tests pass unchanged.
5. Met. `testToggleOffWhileInFlightThenOnFetchesAgain`. The test does the reset itself, the same way `teamTrackingSettingChanged` does. The production reset line is covered by reading only (see Tests).
6. Met. `bash scripts/validate-clt.sh` gives "Executed 604 tests: 602 ok, 0 failed, 2 skipped" (the 2 skipped are the existing keychain tests), exit 0. `git diff --check` is clean.

## Flow
- Inputs to the gate: the 30 s timer, `TeamTracker.onCurrentChanged`, and the toggle all call `refreshUsage()`.
- Single mode:
  - Codex shown: `backgroundLiveTarget` → `startGatedLivePoll(&livePollGate, release: end)` → Task { defer release; `pollLiveTarget` → fetch → `tracker.ingestLive` }. Returns nil when the gate is busy.
  - Anthropic shown: `shownFetchPlan` → `.tracked` → `livePollGate.begin()`. If true: the usual fetch, and the Task's `if !skipsUsage` block ends with `end()` in a defer. If false: same as `.skip` (status and console billing still run, then `applyTeamLoginState`).
- Multi mode: `multiFetchPlan` → when `liveOrgIds` is not empty, `begin()`. If false: the current account goes into `usageSkip` (its console billing still runs if it is selected). If true: the loop visits the current account first and its usage block's defer calls `end()`.
- Toggle off: `teamTrackingSettingChanged` → `tracker.stop()` → `livePollGate = LivePollGate()`.
- One gate is shared by all three sites, so a single-mode fetch and a multi-mode pass (for example after a display-mode switch) cannot overlap either.

## Tests
- `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift`, 4 new tests:
  - `testLivePollGateBeginEnd` (AC1)
  - `testSecondLivePassWhileFirstInFlightDoesNotFetch` (AC2)
  - `testLivePassFailureReleasesGate` (AC3)
  - `testToggleOffWhileInFlightThenOnFetchesAgain` (AC5)

  AC2 and AC3 drive the production `startGatedLivePoll` together with `pollLiveTarget`.
- Command: `bash scripts/validate-clt.sh`, result "Executed 604 tests: 602 ok, 0 failed, 2 skipped", exit 0. `git diff --check`: no output, exit 0.
- Mutation check: I removed `guard !inFlight` from `begin()` and the `defer { release() }` from the helper. Result: `testLivePollGateBeginEnd` FAIL, `testLivePassFailureReleasesGate` FAIL, `testSecondLivePassWhileFirstInFlightDoesNotFetch` TIMEOUT. I restored the code afterwards.
- Covered by reading only, because `MenuBarManager` cannot be built in tests (it uses `ProfileManager.shared` and `TeamTracker.shared` and needs a status bar):
  - the `begin()` and `defer end()` in single-mode `.tracked` inside `refreshUsage()`
  - the multi-mode `begin()` and the loop `defer` in `refreshAllSelectedProfiles()`
  - the reset in `teamTrackingSettingChanged()`
  - the call site of `startGatedLivePoll` in `refreshUsage()`

## Edge cases
- Handled: a fetch that throws, or a Task that is cancelled, still releases the gate, because the release is in a `defer`.
- Handled: in multi mode, the current account is always first in `plan.profiles` and never in `plan.usageSkip`, so the loop `defer` is always reached when the gate was taken. The `begin()` call comes after the empty-selection guard, so no early return can leave the gate held.
- Handled: an unselected current account in multi mode with the gate busy gets neither a usage fetch nor console billing, as before.
- Handled: in single mode, the `.legacy` early return (no credentials) happens before any `begin()`.
- Not handled: after a toggle off/on while a fetch is in flight, the old fetch's `end()` can clear a newer fetch's gate, which allows at most one duplicate. This is a deliberate shortcut, see below.
- Not handled: `onCurrentChanged` firing while the old pair's fetch is in flight skips the new current's fetch, so it waits until the next timer pass (up to 30 s). This is inherent to the one-in-flight spec.

## Shortcuts
- `ponytail:` in `teamTrackingSettingChanged` (disabled branch): the stale-`end()` issue described above. Upgrade path: `begin()` returns a generation token and `end(token)` only clears a matching generation.

## Lessons
- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so `Task {}` in `MenuBarManager` runs on the main actor and a `defer` that mutates `self.livePollGate` is safe. Pass a `var` struct property as `inout` only when the escaping closures that touch it run later, never synchronously during the call, or exclusivity traps.
- Captured `var`s in `Task {}` closures should be turned into `let` copies before the Task (as `liveOrgIds`/`usageSkip` are here).
