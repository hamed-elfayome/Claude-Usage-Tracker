## Tester result
All green.

## Suites run
- `bash scripts/validate-clt.sh` gives "Executed 610 tests: 608 ok, 0 failed, 2 skipped" and exits 0. The 2 skipped are the existing keychain tests. The builder's run had 604 tests; this run adds the 6 new ones.
- `git diff --check` prints nothing and exits 0.
- Mutation check (production file restored afterwards, verified with `cmp`): I made two changes in `startGatedLivePoll`. First, the busy branch calls `release()`. Second, the Task calls `release()` before `await poll()` instead of in a `defer`. With both in place, `testGatedLivePollBusyRunsNothingAndKeepsHolderGate` FAIL (:502, 1 != 0), `testGatedLivePollReleasesOnceAfterPollReturns` FAIL (:518, 1 != 0) and `testCancelledLivePassReleasesGate` FAIL (:541). After that, the run stopped with "Fatal access conflict" in one of the builder's tests, because the mutated busy branch calls `release()` while the `inout` gate is still being accessed.

## New tests
File: `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift`, section "FU-2 tester", 6 tests.
- `testGatedLivePollBusyRunsNothingAndKeepsHolderGate`: a busy pass returns nil. It never runs `poll` and never calls `release`, so it cannot free the gate that the in-flight fetch holds.
- `testGatedLivePollReleasesOnceAfterPollReturns`: the gate stays held for the whole time the fetch is suspended. `release` runs exactly once, after `poll` returns.
- `testCancelledLivePassReleasesGate`: the pass Task is cancelled while the real-tracker fetch is suspended (`Task.sleep` throws `CancellationError`). The gate is released, nothing is saved, and the next pass fetches.
- `testRateLimitedLivePassReleasesGateAndFetchesAfterBackoff`: this is the case the packet was written for. A 429 (`AppError .apiRateLimited`, Retry-After 120) still releases the gate. During the backoff the pass has no target and does not touch the gate. After the backoff ends, the next pass fetches.
- `testBackgroundSiteNeverTakesGateWithoutTarget`: covers AC4 for the background site. With an anthropic subject, or with the tracker off, there is no target, no gate is taken and no fetch runs. With the tracker off, multi-mode `liveOrgIds` is empty, so the multi site never calls `begin()`.
- `testMultiFetchPlanLiveAccountIsReleasable`: a table over 6 selection shapes (empty, current only, current last or middle, Codex mixed in, current unselected). In every shape, `liveOrgIds` has exactly the current account as its key, that account is `profiles[0]` and appears only once, and it is never in `usageSkip`. This pins the release invariant that arch-review.md says would break silently.

## Bugs
None found.

Notes (by reading the code, not bugs against the spec):
- Live-sample switch delays the new current's fetch. In `TeamTracker.swift:439`, `apply` calls `moveCurrent`, and that calls `onCurrentChanged` synchronously inside `ingestLive`. All three gated sites call `ingestLive` while they still hold the gate. So when a live sample causes a switch, the `refreshUsage()` that `onCurrentChanged` starts always finds the gate busy, and the new current account waits for the next 30 s tick. The walkthrough lists the general case as "Not handled". This case happens every time, not just in a rare race. If that matters, the fix is a per-pair gate or releasing the gate before `ingestLive`.
- The stale `end()` after a toggle off/on is the documented `ponytail` shortcut. I did not test it.
- The single-mode `.tracked` site, the multi-mode loop `defer` and the reset in `teamTrackingSettingChanged` can still only be checked by reading the code. I read them: every `begin()` that succeeds reaches its `defer`.
