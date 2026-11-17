## Tester result
all green (retest round 1)

## Suites run
- `bash scripts/validate-clt.sh` (CLT mode, no full Xcode) → `Executed 596 tests: 594 ok, 0 failed, 2 skipped` (EXIT=0). The 2 skips are the existing `ProfileKeychainMigrationTests` Keychain tests. Both new tests report `ok`.
- `git diff --check` → clean (exit 0). The untracked test files have no trailing whitespace.
- Mutation check (lesson MT-6) on an rsync copy in the scratchpad, `CLT_FORCE=1 bash scripts/validate-clt.sh --root <copy>` → `Executed 596 tests: 591 ok, 3 failed, 2 skipped`. EXIT=129 comes from the final `git diff --check`, because the copy has no `.git`. Mutations:
  - M1: Codex guard removed from `menuBarProfile`. Fails the new `testCodexActiveStaysShownAndLegacyWithRealTrackerBeforeAndAfterTargetLoss` and the builder's `testCodexActiveProfileStaysShownWhileRunning`.
  - M2: `multiFetchPlan` keeps only `[current]` when the current account is not selected, so the selected accounts lose their console billing. Fails **only** the new `testMultiPlanUnselectedCurrentKeepsSelectedAccountsForConsoleBilling`. None of the builder's tests caught it.
  - The worktree itself was never mutated.

## New tests
`Claude UsageTests/MenuBarTeamWiringEdgeTests.swift` (2 tests, under "Retest round 1"):
- `testCodexActiveStaysShownAndLegacyWithRealTrackerBeforeAndAfterTargetLoss` (verdict line 1, with a real running `TeamTracker` and fakes). The active profile is Codex and the current pair is anthropic. The test checks two phases: first with a live target, then after `refreshRejectedHandler` removes the target. In both phases:
  - `menuBarProfile` returns the Codex profile.
  - `shownFetchPlan` is `.legacy`, never `.skip`.
  - `teamLoginMessage` is nil.
  - `shownAPIUsage` returns the live console data. This covers the popover side of verdict line 4 for a Codex active profile.
- `testMultiPlanUnselectedCurrentKeepsSelectedAccountsForConsoleBilling` (verdict line 2, unselected-current variant). The selection is `[a (with apiSessionKey/apiOrganizationId), b]` and the target is an unselected `c`. Expected:
  - loop order `[c, a, b]`;
  - usage is fetched only for `c`;
  - `usageSkip == [a, b]` and `consoleSkip == [c]`;
  - the console-billing visits are exactly `[a, b]`.

Verdict "Tests to add" coverage:
- Line 1 (Codex `menuBarProfile` + `.legacy`): the builder's `testCodexActiveProfileStaysShownWhileRunning`, plus the new real-tracker test above.
- Line 2 (multi plan: `a` visited for console billing, not for usage): the builder's `testMultiModeKeepsConsoleBillingForUsageSkippedAccounts`, plus the new unselected-current test.
- Line 3 (single-mode `.skip` still runs the active profile's console fetch): **code reading**, because no pure seam exists and the verdict accepts code reading.
  - `MenuBarManager.swift:1436-1439`: `.skip` only sets `skipsUsage = true`.
  - In the Task, `if !skipsUsage {` (:1482) wraps only the usage do/catch. The status fetch (:1616) and the console block on `activeProfile` (:1632-1660) come after it. `applyTeamLoginState()` (:1668) ends the pass.
  - An awk scan of lines 1482-1612 finds no `return` in between.
- Line 4 (single-mode popover default viewed profile is `menuBarProfile`): **code reading**.
  - `togglePopover` single-mode branch: `clickedProfileId = menuBarProfile?.id`.
  - `onCurrentChanged` updates `clickedProfileId` when the shown account changes.
  - `MenuBarManager` cannot be built in tests (status bar side effects), so no runtime test is possible. The helpers behind the rule (`menuBarProfile`, `shownAPIUsage`) are tested.

## Bugs
none
