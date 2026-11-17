## Tester result
all green (retest round 2: 600 tests, 598 ok, 0 failed, 2 skipped; no new tests needed, both verdict "Tests to add" lines already exist and pass the mutation checks)

## Suites run
- `bash scripts/validate-clt.sh` (worktree, unchanged) → `Executed 600 tests: 598 ok, 0 failed, 2 skipped`, EXIT=0. The 2 skips are the existing `ProfileKeychainMigrationTests` Keychain tests.
- `git diff --check` → clean (exit 0)
- Mutation checks: `scripts/validate-clt.sh` on a scratch copy (separate `git init`; the worktree was never edited):
  - M1, `backgroundLiveTarget` always returns nil (the reviewer's repro state) → `594 ok, 4 failed`: `testBackgroundLiveTargetOnlyForNonAnthropicSubjectWhileRunning`, `testCodexActiveLoopPollsCurrentPairSoItDefends` (the :334 assertion shows current flipped to `org-a`, the same as the reviewer's repro), `testCodexActiveBackgroundPollFailureReachesTrackerAndNextPassSkips`, `testCodexActiveBackgroundPollCachedReadingIsNoSample`.
  - M2, `pollLiveTarget` drops the success `ingestLive` (it still saves) → `597 ok, 1 failed`: `testCodexActiveLoopPollsCurrentPairSoItDefends`.
  - M3, the helper ignores `running` → `597 ok, 1 failed`: `testBackgroundLiveTargetOnlyForNonAnthropicSubjectWhileRunning`.
  - M4, the helper ignores the provider (anthropic subject gets a second fetch) → `597 ok, 1 failed`: `testBackgroundLiveTargetOnlyForNonAnthropicSubjectWhileRunning`.

## New tests
None added this round. The builder already wrote both verdict "Tests to add" lines, matching their spec, so a copy would only duplicate them:
- Pure helper (Codex + running + target → the pair with its orgId; no target → nil; `running == false` → nil; anthropic subject → nil): `Claude UsageTests/TeamEventNotificationTests.swift:148` `testBackgroundLiveTargetOnlyForNonAnthropicSubjectWhileRunning`. M1, M3 and M4 each fail it.
- Real `TeamTracker` with fakes and a `ClockBox` (Codex active, A and B tracked, current B; loop passes ingest B at t0+10 = 20% and t0+300 = 50%; probe rounds at t0+15 and t0+315 see A go from 10% to 12%; `global.current` stays B; B's `lastSampleAt` = t0+300): `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift:322` `testCodexActiveLoopPollsCurrentPairSoItDefends`. M1 and M2 each fail it, and under M1 current flips to A, as in the reviewer's repro.
- The builder also added `testCodexActiveBackgroundPollFailureReachesTrackerAndNextPassSkips` (a 429 backs off, and the next pass fetches and saves nothing) and `testCodexActiveBackgroundPollCachedReadingIsNoSample` (cached fallback: nothing saved, no sample).
- Remaining gap: the call site in `refreshUsage()` (`Claude Usage/MenuBar/MenuBarManager.swift:1464-1470`) is checked by code reading only. It starts the poll `Task` before the `.legacy` credentials guard (:1496) and uses `ProviderRegistry.service(for: .anthropic).fetchUsage(for:)`, never `fetchUsageForActiveProfile` or `activateProfile`. The tests drive the same production helpers (`shownFetchPlan`, `backgroundLiveTarget`, `pollLiveTarget`) but not the `MenuBarManager.shared` instance path.

## Bugs
None found.
