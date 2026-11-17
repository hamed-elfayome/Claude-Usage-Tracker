## Summary
Round 1 fixes the three Must-fix findings in verdict.md.
1. A Codex active profile stays shown and on today's path while Team tracking runs.
2. The single-mode popover now views `menuBarProfile` and never shows the active profile's console data under another account.
3. Console billing (and the single-mode status fetch) runs as before for profiles whose claude.ai usage the tracker skips.

## Changes
- `Claude Usage/MenuBar/MenuBarManager.swift`:
  - Must fix 1. `static menuBarProfile(...)` returns `active` when the active profile is not anthropic. With no active profile while running it returns the current account (an explicit decision, noted in a code comment; the tester's test expects this). `handleProfileSwitch` now calls the same static helper with `active: profile`, so it has the same Codex rule (and does not read a possibly stale `activeProfile`).
  - Must fix 2. `togglePopover`, single-mode branch: `clickedProfileId = menuBarProfile?.id`. New `shownAPIUsage` (instance) and pure `static shownAPIUsage(shown:activeId:live:)`: they return `apiUsage` only when the shown profile is the active one, else the shown profile's own saved `apiUsage` (nil if it has none).
  - Must fix 2, needed for it to hold (outside the verdict's exact lines):
    - `onCurrentChanged` (single mode) also sets `clickedProfileId = shown.id`. "Make current" and "Delete" in the popover's Teams section change the current pair while the popover is open. Without this, the open popover would mix the new account's usage with the old account's spend limit.
    - `setup()` loads `apiUsage` from the active profile, not from `menuBarProfile`. Every refresh writes the active profile's console data there. The round-0 line put another account's data in `apiUsage`, and that data would then show (and feed `checkAndRecordBillingCycleReset`) as the active profile's. With tracking off the two are the same profile.
  - Must fix 3, multi mode. `multiFetchPlan` now returns a `MultiFetchPlan` struct: `profiles`, `liveOrgIds`, `usageSkip` and `consoleSkip`. It keeps every selected profile in the loop, with the current account first (as a live copy). In the loop, the claude.ai usage part is wrapped in `if !usageSkip.contains(profile.id)` (re-indented only; `git diff -w` shows the real change). The console-billing block runs for every selected profile. It does not run for an unselected current account (`consoleSkip`), so console billing covers exactly today's set of profiles.
  - Must fix 3, single mode. `.skip` no longer returns early. It sets `skipsUsage`, so the Task skips only the usage fetch. The status fetch and the active profile's console billing still run, and the pass ends with `applyTeamLoginState()` as before. `async let statusResult` now starts before the conditional `async let usageResult`, so the two still run in parallel. The usage do/catch is re-indented inside `if !skipsUsage`.
- `Claude Usage/MenuBar/PopoverContentView.swift`: `displayAPIUsage` falls back to `manager.shownAPIUsage` instead of `manager.apiUsage`. The two viewed-profile doc comments now say "shown profile, `menuBarProfile`".
- `Claude UsageTests/TeamEventNotificationTests.swift` (`MenuBarTeamWiringTests`):
  - New tests: `testCodexActiveProfileStaysShownWhileRunning`, `testShownAPIUsageNeverShowsActiveConsoleDataForAnotherAccount` and `testMultiModeKeepsConsoleBillingForUsageSkippedAccounts`.
  - The three multi-plan tests now use the new contract. They keep their intent and add `usageSkip`/`consoleSkip` checks. The tracker-off test now compares the whole plan.
- `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift` (the tester's file): the multi-plan assertions use the new contract with the same intent:
  - "multi mode drops the account" is now "no usage fetch for any account" plus `usageSkip == [a, b]`.
  - "no duplicate, live copy first" now also expects `a` in the loop for console billing.
  - The tracker-off check compares the whole plan.
- No change to `AnthropicUsageProvider.swift` or `NotificationManager.swift` in this round.

## Acceptance
1. **Met.** With tracking off, every round-1 branch falls through to today's code:
   - `menuBarProfile` returns `active` (not running), so `togglePopover`, `handleProfileSwitch` and the `setup()` reads behave as before.
   - `shownAPIUsage` returns `apiUsage`, because the shown profile is the active one.
   - `multiFetchPlan` returns `MultiFetchPlan(profiles: selected)` with every set empty.
   - `skipsUsage` is false on `.legacy`.
   - `onCurrentChanged` only fires while running.
   - Tests: `testMultiModeUnchangedWhenTrackerOff` and `testTrackerOffIgnoresHandlerAndKeepsLegacyPath` (whole-plan equality), plus the full suite.
2. **Met** (unchanged from round 0). `testSingleModeFetchesCurrentByProfileWhenNotActive`; `activateProfile` is never called (code reading).
3. **Met.** No live target means no usage fetch for that account in that pass, and the cached value stays:
   - Single mode: `.skip` sets `skipsUsage`, and only the usage `async let` is skipped.
   - Multi mode: the account is in `usageSkip`.
   - Tests: `testSingleModeSkipsWithoutLiveTarget`, `testMultiModeFetchesUnselectedCurrentAndSkipsWithoutTarget`, `testRefreshRejectedFlowsToSkipBannerAndNotification`.
4. **Met.** Tracker-owned samples call `ingestLive` and skip the reset checks and recorders (unchanged). A Codex profile now keeps the old path even when it is the active profile while tracking runs: `testCodexActiveProfileStaysShownWhileRunning` (the shown profile is the Codex one and the plan is `.legacy`).
5. **Met.** Only the current account's claude.ai usage is fetched; the other anthropic accounts are visited for console billing only. Tests: `testMultiModeFetchesOnlyCurrentAccount` (usage fetched for [current, codex], `usageSkip` [a, c]) and `testMultiModeKeepsConsoleBillingForUsageSkippedAccounts`.
6. **Met** (unchanged). `testAdminMoveContent`.
7. **Met** (unchanged). `testNonNotifyingEventIsNotPosted`, `testEveryInvolvedProfileDisabledIsNotPosted`.
8. **Met** (unchanged). `testRefreshRejectedHandlerReportsProfile`, plus code reading.
9. **Met.** `applyTeamLoginState()` still ends every pass. On `.skip` it now runs in the Task's final block, not before an early return. Test: `testNeedsLoginShowsLogInAgain`; the setter is checked by code reading.
10. **Met** (code reading, unchanged).
11. **Met.** `bash scripts/validate-clt.sh` → `Executed 594 tests: 592 ok, 0 failed, 2 skipped`, exit 0. The 2 skips are the existing `ProfileKeychainMigrationTests` Keychain tests. The skip list is unchanged and empty.

Verdict "Tests to add":
- Codex `menuBarProfile` plus `.legacy`: `testCodexActiveProfileStaysShownWhileRunning`.
- Multi plan, `a` (with console credentials) visited for console billing but not for usage: `testMultiModeKeepsConsoleBillingForUsageSkippedAccounts`.
- Single-mode `.skip` still runs the active profile's console fetch: **code reading**. No pure seam exists. The `.skip` case only sets `skipsUsage = true`, and the console block (`if let profile = activeProfile, consoleBilling, apiSessionKey, apiOrganizationId`) sits after `if !skipsUsage { … }` in the same Task, with no return in between.
- Popover default viewed profile in single mode is `menuBarProfile`: **code reading** of `togglePopover` (`clickedProfileId = menuBarProfile?.id`) and `onCurrentChanged`. A helper returning `menuBarProfile?.id` would only test itself. The rule behind it is tested: `menuBarProfile` (Codex and current-account cases) and `shownAPIUsage`.

## Flow
1. Single mode, 30 s timer: `refreshUsage()` → subject = `menuBarProfile`:
   - a Codex active profile stays the subject;
   - otherwise, while running, the current account.
   Then `shownFetchPlan` decides:
   - `.legacy`: today's credentials guard, then the old fetch.
   - `.skip`: `skipsUsage = true`.
   - `.tracked`: `fetchUsage(for:)` or `fetchUsageForActiveProfile`.
   The Task starts `statusResult`. If `!skipsUsage`, it runs the usage `async let` and the do/catch (save, `ingestLive`, and so on). Then come status, then the active profile's console billing (writes `apiUsage` and `saveAPIUsage(active)`), then `applyTeamLoginState()`.
2. Multi mode: `refreshAllSelectedProfiles()` → `multiFetchPlan` → loop over `plan.profiles`:
   - usage part unless the profile is in `usageSkip`;
   - console-billing block unless it is in `consoleSkip`.
   After the loop: the error fields are reset, then `applyTeamLoginState()`.
3. Popover open in single mode: `togglePopover` sets `clickedProfileId = menuBarProfile?.id`; `PopoverContentView` reads:
   - `displayUsage` = `manager.usage` (the shown account);
   - `displayAPIUsage` = `manager.shownAPIUsage`;
   - provider and spend limit from `clickedProfileId`.
   Current pair change: `onCurrentChanged` updates `clickedProfileId` and `usage` to the new shown account, then refreshes.
4. Profile switch: `handleProfileSwitch(profile)` → `menuBarProfile(running:…, active: profile)` gives the usage to show. `apiUsage` = the new active profile's saved console data (as before).

## Tests
- `Claude UsageTests/TeamEventNotificationTests.swift`:
  - `TeamEventNotificationTests` (7 tests, unchanged).
  - `MenuBarTeamWiringTests` (12 tests): `menuBarProfile` (current/active/deleted, Codex active), `shownAPIUsage`, the single plan (AC2–AC4), the multi plan (AC5, console billing kept, unselected current, no target, tracker off), AC8 and AC9.
- `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift` (10 tests, from the tester): multi-plan assertions moved to the new contract with the same intent.
- Command: `bash scripts/validate-clt.sh` (CLT mode; no full Xcode on this machine) → `Executed 594 tests: 592 ok, 0 failed, 2 skipped`, `EXIT=0`. All 29 MT-7 tests report `ok`: 7 notification, 12 wiring and 10 edge tests.
- `git diff --check` → clean (exit 0). It also runs at the end of the validate script. The two untracked test files have no trailing whitespace (checked with grep).
- Mutation check (lesson MT-6). I applied five mutations together to an rsync copy of the worktree in the scratchpad, then ran `CLT_FORCE=1 bash scripts/validate-clt.sh --root <copy>`. Result: `Executed 594 tests: 584 ok, 8 failed, 2 skipped`. All 8 failures are MT-7 tests, and every mutation is caught by its own assertion (TNT = TeamEventNotificationTests.swift, Edge = MenuBarTeamWiringEdgeTests.swift):
  - M1, Codex guard removed from `menuBarProfile`: `testCodexActiveProfileStaysShownWhileRunning` (TNT:140 shown id; TNT:141 `tracked(orgId: "org-a", byProfile: true) != legacy`).
  - M2, `shownAPIUsage` always returns `live`: `testShownAPIUsageNeverShowsActiveConsoleDataForAnotherAccount` (TNT:151 spend 500 != 42; TNT:152 not nil).
  - M3, the `usageSkip` line removed:
    - `testMultiModeFetchesOnlyCurrentAccount` (TNT:187);
    - `testMultiModeKeepsConsoleBillingForUsageSkippedAccounts` (TNT:201);
    - `testMultiModeFetchesUnselectedCurrentAndSkipsWithoutTarget` (TNT:214);
    - Edge `testMultiFetchPlanWithoutTargetKeepsCodexProfiles` (Edge:126, Edge:127);
    - Edge `testRefreshRejectedFlowsToSkipBannerAndNotification` (Edge:201, Edge:202).
  - M4, the `consoleSkip` line removed: `testMultiModeFetchesUnselectedCurrentAndSkipsWithoutTarget` (TNT:212 `[] != [c]`).
  - M5, the round-0 loop filter put back (`selected.filter { $0.id != current.id && $0.provider != .anthropic }`):
    - `testMultiModeKeepsConsoleBillingForUsageSkippedAccounts` (TNT:199 `[b] != [b, a]`);
    - Edge `testMultiFetchPlanNoDuplicateAndUsesLiveProfileCopy` (Edge:114).
  - The tracker-off tests stayed green, as they should: the plan returns before any mutated line.
  - The copy's EXIT=129 is expected. It comes from the script's final `git diff --check`, and the copy has no `.git`. The worktree itself was never mutated (`cmp` shows the test files are the same; only the copy's MenuBarManager.swift differs).

## Edge cases
- **Handled:**
  - Codex active while running: shown, fetched on the old path, and not overwritten by tracker samples (`onSample` matches only `menuBarProfile`).
  - No active profile while running: the current account is shown, fetched per profile (`byProfile: true`), and its own `apiUsage` is shown.
  - Current pair changed while the popover is open ("Make current" or "Delete" in the Teams section): `onCurrentChanged` moves `clickedProfileId` and `usage` together.
  - The shown account is not active and has no saved console data: the popover shows no API section (nil). It does not borrow the active profile's data.
  - Unselected current account in multi mode: usage fetched, console billing not (as today, for any unselected profile).
  - No live target in multi mode: every selected anthropic profile is visited for console billing only; Codex is fetched as before.
- **Not handled:**
  - The shown account's saved `apiUsage` (when it is not active) is only as fresh as its last refresh as the active profile, or in multi mode. Single mode fetches console billing only for the active profile, because console billing is out of scope.
  - Single-mode menu bar API metric: it still shows the active profile's console data (`apiUsage`), per the arch note "console usage follows the active profile". Only the popover view changed.
  - Multi mode with a Codex active profile: `applyTeamLoginState` follows `menuBarProfile` (the Codex profile), so no "Log in again" banner appears for a hidden anthropic account. The Teams section row and the `loginLost` notification still report it.
  - The popover default viewed profile and the single-mode `.skip` console fetch are checked by code reading (see Acceptance).

## Shortcuts
none (no `ponytail:` comments).

## Lessons
- A plan that filters the loop list also drops every later block in the loop body (console billing here). Skip a single fetch with a skip set, and keep the list.
- A popover "viewed profile" captured at open time goes stale when an action inside the popover changes it ("Make current"). Update it in the same callback that changes the shown data.
