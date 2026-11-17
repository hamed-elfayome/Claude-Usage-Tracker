## Summary
Round 2 fixes the one Must fix in verdict.md: with Team tracking on and a Codex active profile in single mode, the 30 s loop now also polls the current anthropic pair.
The Codex profile stays shown and on today's path; the current pair is fetched per profile (`fetchUsage(for:)`, never activated, not shown) and every result goes to `ingestLive`.
Root cause: `TeamTracker.runRound` never probes the current pair (TeamTracker.swift:348), so the loop is its only live source, but single mode fetched only the shown profile, and the round-1 Codex rule made "shown" differ from "current".

## Changes
- `Claude Usage/MenuBar/MenuBarManager.swift`:
  - New pure `static backgroundLiveTarget(subject:running:target:)` (:175). It returns the live target only when the tracker runs and the shown profile is not anthropic, else nil (exactly the verdict's signature and rule).
  - New `static pollLiveTarget(_:tracker:store:fetch:)` (:184). Fetches the target, saves the reading to that account unless it is the cached fallback (`target.profile.claudeUsage == newUsage`), then `ingestLive(.success, isCachedReading:)`; on error, logs and `ingestLive(.failure)`. It touches nothing else: no `usage`, banner, statusline, threshold alerts or auto-switch.
  - `refreshUsage()` single mode (:1460-1470): when the helper returns a target, a `Task` runs `pollLiveTarget` with `ProviderRegistry.service(for: .anthropic).fetchUsage(for:)`. It starts before the `.legacy` credentials guard (:1496), because that guard checks the active (Codex) profile and can return before the main Task.
- `Claude UsageTests/TeamEventNotificationTests.swift` (`MenuBarTeamWiringTests`): new `testBackgroundLiveTargetOnlyForNonAnthropicSubjectWhileRunning` (:148), the verdict's four helper cases.
- `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift`: new "Fix round 2" block (:289-372): helpers `codexPass` and `probeRound` plus three tests with a real `TeamTracker`, fakes and a `ClockBox` (reusing `build`).
- No change to `PopoverContentView.swift`, `AnthropicUsageProvider.swift` or `NotificationManager.swift` in this round.
- Note: the round-2 code was already in the wip commit `4ce2059` (an earlier round-2 run was stopped before validation and walkthrough). This run checked it against the verdict, found nothing missing, validated it, ran the mutation checks below and wrote this file. No source edit was needed.

## Acceptance
1. **Met.** Tracker off: `backgroundLiveTarget` returns nil (`running == false`), so no poll; all round-0/1 guards unchanged (`menuBarProfile` → active, `shownFetchPlan` → `.legacy`, `multiFetchPlan` → selection with empty sets, `onCurrentChanged`/`onSample` fire only while running). Tests: `testBackgroundLiveTargetOnlyForNonAnthropicSubjectWhileRunning` (running false → nil), `testTrackerOffIgnoresHandlerAndKeepsLegacyPath`, `testMultiModeUnchangedWhenTrackerOff`, full suite.
2. **Met.** Current account ≠ active profile is fetched with `fetchUsage(for:)` in both single-mode cases:
   - anthropic active: `.tracked(byProfile: true)` (`testSingleModeFetchesCurrentByProfileWhenNotActive`);
   - Codex active (new): the background poll (`testBackgroundLiveTargetOnlyForNonAnthropicSubjectWhileRunning`, `testCodexActiveLoopPollsCurrentPairSoItDefends`: the poll fetches B twice, never the Codex profile).
   - Code reading: the poll calls `ProviderRegistry.service(for: .anthropic).fetchUsage(for:)` only; no `activateProfile` or `fetchUsageForActiveProfile` in the diff (`git diff cf254fb HEAD | grep activateProfile` → none). For a profile that is not active, `ensureFreshCredentials` never writes the system keychain: the system branch is only for the active profile (ClaudeCodeSyncService.swift:1070), an unpinned one is never refreshed (:1163), and a pinned one writes only its own entry. So the active profile's Claude Code credentials are untouched.
3. **Met.** No live target → no fetch, cached value stays: single `.skip`, multi `usageSkip`, and now the background poll (helper nil without a target). Tests: `testSingleModeSkipsWithoutLiveTarget`, `testMultiModeFetchesUnselectedCurrentAndSkipsWithoutTarget`, `testRefreshRejectedFlowsToSkipBannerAndNotification`, `testCodexActiveBackgroundPollFailureReachesTrackerAndNextPassSkips` (after a 429 the next pass fetches nothing and saves nothing).
4. **Met.** Tracker-owned samples call `ingestLive` and skip the reset checks and recorders. The background poll calls only `saveClaudeUsage` + `ingestLive` (code reading of `pollLiveTarget`, :184-198). Codex keeps the old path: `testCodexActiveProfileStaysShownWhileRunning`, and every `codexPass` in the new tests asserts `.legacy` for the Codex profile. New: `testCodexActiveLoopPollsCurrentPairSoItDefends` (B's samples reach the tracker; `lastSampleAt` = t0+300), `testCodexActiveBackgroundPollCachedReadingIsNoSample` (cached fallback: nothing saved, no sample).
5. **Met** (unchanged). `testMultiModeFetchesOnlyCurrentAccount`, `testMultiModeKeepsConsoleBillingForUsageSkippedAccounts`.
6. **Met** (unchanged). `testAdminMoveContent`.
7. **Met** (unchanged). `testNonNotifyingEventIsNotPosted`, `testEveryInvolvedProfileDisabledIsNotPosted`.
8. **Met** (unchanged). `testRefreshRejectedHandlerReportsProfile`. The background poll uses the same `fetchUsage(for:)`, which passes the handler, so an `invalid_grant` during that fetch (a pinned profile's refresh) also reaches `reportRefreshRejected`.
9. **Met** (unchanged). `testNeedsLoginShowsLogInAgain`; `applyTeamLoginState()` still ends every pass.
10. **Met** (code reading, unchanged).
11. **Met.** `bash scripts/validate-clt.sh` → `Executed 600 tests: 598 ok, 0 failed, 2 skipped`, `EXIT=0`.

Verdict "Tests to add":
- Pure helper (Codex+running+target → the pair with its orgId; no target → nil; not running → nil; anthropic subject → nil): `testBackgroundLiveTargetOnlyForNonAnthropicSubjectWhileRunning`.
- Real tracker (Codex active, A and B tracked, current B; loop passes ingest B at t0+10 = 20 % and t0+300 = 50 %; probe rounds at t0+15 and t0+315 see A 10 % → 12 %; `global.current` stays B, B's `lastSampleAt` set): `testCodexActiveLoopPollsCurrentPairSoItDefends`. With the helper disabled (mutation M-B1 below) the same test flips current to A, as in the reviewer's repro.

## Flow
1. Timer (active profile's interval, 30 s default) → `refreshUsage()`. Multi mode → `refreshAllSelectedProfiles()` (unchanged; it already fetches the current account).
2. Single mode: `profile = menuBarProfile` (Codex active → the Codex profile). `liveTarget = tracker.liveTarget()` (nil: off, no current, backing off, needsLogin). `plan = shownFetchPlan(...)` → `.legacy` for Codex.
3. `backgroundLiveTarget(subject: profile, running:, target: liveTarget)` → non-nil only for a non-anthropic subject while running → `Task { pollLiveTarget(target, tracker: .shared, store: profileManager, fetch: ProviderRegistry.service(for: .anthropic).fetchUsage(for:)) }` (the `AnthropicUsageProvider`).
   - success, fresh → `profileManager.saveClaudeUsage(u, for: B)` → `tracker.ingestLive(B, org, .success(u), isCachedReading: false)` → per-pair history and `lastSampleAt` (a live sample never fires `onSample`, TeamTracker.swift:516, so the Codex display is untouched).
   - success, cached fallback → `ingestLive(..., isCachedReading: true)` (ignored by the tracker), nothing saved.
   - error → `ingestLive(.failure)` → 429 back-off (next pass: `liveTarget()` nil, no poll), membership failure → forced list; Cloudflare ignored.
4. Same pass, independent of the poll: the `.legacy` credentials guard and the Codex fetch, status, console billing, `applyTeamLoginState()`, exactly as before.
5. Probe rounds (`TeamTracker.tick`, every 300 s) skip the current pair; `detect` now sees B's fresh live samples, so B can defend against a small riser.
6. Root-cause check: every pass with a live target now fetches it.
   - Single mode, shown = current account (anthropic or no active profile): `.tracked`.
   - Single mode, shown = Codex active profile: the background poll.
   - Single mode, shown = active because there is no current pair or its profile is gone: `liveTarget()` is nil too (`trackedProfiles` are the anthropic `profiles`), so there is nothing to poll.
   - Multi mode: `multiFetchPlan` puts the current account first, selected or not.

## Tests
- `Claude UsageTests/TeamEventNotificationTests.swift`:
  - `TeamEventNotificationTests` (7, unchanged): AC6, AC7, every kind's title, group/deleted-profile edges.
  - `MenuBarTeamWiringTests` (13): `menuBarProfile`, `shownAPIUsage`, `backgroundLiveTarget` (new), single plan (AC2–AC4), multi plan (AC5, console billing, unselected current, no target, tracker off), AC8, AC9.
- `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift` (15): tester edge and integration tests, plus the three new real-tracker tests:
  - `testCodexActiveLoopPollsCurrentPairSoItDefends`: the verdict's scenario.
  - `testCodexActiveBackgroundPollFailureReachesTrackerAndNextPassSkips`: a 429 from the poll backs B off; the next pass has no target, fetches and saves nothing.
  - `testCodexActiveBackgroundPollCachedReadingIsNoSample`: the provider's cached fallback is not saved and is no sample; the target stays.
- Command: `bash scripts/validate-clt.sh` (CLT mode, no full Xcode) → `Executed 600 tests: 598 ok, 0 failed, 2 skipped`, `EXIT=0`. All 35 MT-7 tests `ok`. The 2 skips are the existing `ProfileKeychainMigrationTests` Keychain tests; the skip list is unchanged and empty.
- `git diff --check` → clean (exit 0); `git diff --check cf254fb HEAD` (all MT-7 changes, since they sit in the wip commit) → clean (exit 0).
- Mutation check (lesson MT-6), on rsync copies in the scratchpad, `CLT_FORCE=1 bash scripts/validate-clt.sh --root <copy>`; the worktree was never mutated:
  - Run A, four mutations at once, each caught by its own test → `Executed 600 tests: 594 ok, 4 failed, 2 skipped`:
    - M-A1, provider check dropped from `backgroundLiveTarget` (an anthropic subject would be fetched twice): `testBackgroundLiveTargetOnlyForNonAnthropicSubjectWhileRunning` (TNT:155).
    - M-A2, no `ingestLive` on success: `testCodexActiveLoopPollsCurrentPairSoItDefends` (Edge:334 current flips to A; Edge:335 `lastSampleAt` nil).
    - M-A3, no `ingestLive` on failure: `testCodexActiveBackgroundPollFailureReachesTrackerAndNextPassSkips` (Edge:350 target still live after the 429; Edge:352 the next pass fetches B; Edge:353 a reading is saved).
    - M-A4, cached check removed (`isCachedReading = false`): `testCodexActiveBackgroundPollCachedReadingIsNoSample` (Edge:368 the cached reading is saved).
  - Run B, M-B1: the helper always returns nil (the round-1 behaviour) → `Executed 600 tests: 594 ok, 4 failed, 2 skipped`, all four new tests fail. `testCodexActiveLoopPollsCurrentPairSoItDefends` fails at Edge:333 (nothing fetched), Edge:334 (current flips to A, the reviewer's repro), Edge:335 and Edge:336.
  - Run C, M-C1: the `running` check dropped from the helper → `Executed 600 tests: 597 ok, 1 failed, 2 skipped`. Only `testBackgroundLiveTargetOnlyForNonAnthropicSubjectWhileRunning` fails, at TNT:154: tracker off still returns the B target.
  - In every run all other tests stayed green, so each failure is a real catch. EXIT=129 in the copies comes from the script's final `git diff --check` (the copy has no `.git`).
  - TNT = `TeamEventNotificationTests.swift`, Edge = `MenuBarTeamWiringEdgeTests.swift`.

## Edge cases
- **Handled:**
  - Codex active whose own credentials are missing: the `.legacy` guard returns before the main Task, but the poll already started (it runs before the guard).
  - No live target (tracker off, no current pair, current account backing off or needsLogin): no poll, cached value stays (`backgroundLiveTarget` nil).
  - Provider falls back to the cached reading (no usable live credential): nothing saved, `isCachedReading: true` (`pollLiveTarget`).
  - Poll failure: only the tracker learns of it; `usage`, `hasCredentialError`, `lastRefreshError` and the banner stay with the shown Codex profile.
  - Anthropic subject: helper nil, so the current account is never fetched twice in one pass (`shownFetchPlan` already fetches it).
  - Two passes close together (timer plus `onCurrentChanged`): two polls; each compares against the snapshot it fetched with, and the tracker takes repeated samples (as in multi mode).
- **Not handled:**
  - With Codex shown, a hidden current account that needs a login shows no "Log in again" banner; the Teams row and the `loginLost` notification report it (spec §11 "shown account"; verdict "Improve later").
  - The poll runs at the existing loop's interval, which is the active (Codex) profile's `refreshInterval` (30 s default), like the loop for any active profile (spec §7 "existing loop").
  - `refreshUsage()` itself cannot be run in tests (`MenuBarManager` needs the status bar), so the call site (:1460-1470) is checked by code reading; the helper and the poll it calls are tested with a real tracker.

## Shortcuts
none (no `ponytail:` comments).

## Lessons
- `TeamTracker` never probes the current pair: the menu bar loop is its only live source. Any rule that changes what the menu bar shows must keep `liveTarget()` fetched in every pass, or the current pair starves and loses detection.
- A "shown profile" fix and a "polled profile" fix are two things: decide both whenever the shown profile can differ from the tracker's current account.
