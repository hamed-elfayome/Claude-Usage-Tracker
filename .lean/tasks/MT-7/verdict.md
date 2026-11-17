## Verdict
FAIL. The hunter's major finding reproduces. With Team tracking on and a Codex active profile in single mode, nothing polls the current anthropic pair, so it gets no live samples and loses to any small riser. This breaks R15, spec §7 ("Current pair: 30 s, existing loop"), the packet Goal, and AC2 for this case.

## How it's going
Grade B. Round 1 fixed all three previous Must fix lines cleanly, with a test for each and a mutation check. Gates are green: my rerun gave 599 tests, 597 ok, 0 failed, 2 skipped (this includes 3 reviewer repro tests), and `git diff --check` is clean.
The one gap left comes from my own round-0 prescription. Keeping Codex shown also needs a background poll of the current pair, as multi mode already does.

## Done well
- Must fix 1 met. `menuBarProfile` returns a non-anthropic active profile. `handleProfileSwitch` uses the same static helper. The nil-active case is decided and commented.
- Must fix 2 met:
  - single-mode `togglePopover` views `menuBarProfile`;
  - `shownAPIUsage` never shows the active profile's console data under another account;
  - `onCurrentChanged` moves `clickedProfileId` together with `usage`.
- Must fix 3 met:
  - `MultiFetchPlan` keeps every selected profile in the loop, with `usageSkip` and `consoleSkip`;
  - single-mode `.skip` skips only the usage fetch. Status, console billing and `applyTeamLoginState()` still run (read :1433-1668; no `return` in between).
- Test intent was kept when moving to the new plan contract (whole-plan equality for tracker-off). The tester's new unselected-current test catches a mutation that none of the builder's tests caught.
- No skips, `noqa` or weakened assertions were added. No tracked test file changed, and the CLT skip list is unchanged.

## Must fix
1. `Claude Usage/MenuBar/MenuBarManager.swift`, `refreshUsage()` single mode (plan block :1424-1460, Task :1463-1675).
   - Problem: with the tracker running and a Codex active profile, `menuBarProfile` is the Codex profile and `shownFetchPlan` is `.legacy`, so the 30 s loop fetches only Codex. `TeamTracker.runRound` skips the current pair on purpose (TeamTracker.swift:348). The current anthropic pair therefore gets no live sample at all:
     - no `ingestLive`;
     - no membership-failure or 429 handling;
     - a stale Teams row;
     - no per-pair history;
     - it cannot defend at detection. Reviewer repro: the user works on B (+30), A rises 2 points, and current flips to A. With an anthropic active profile, the same usage keeps B.
   - This breaks R15, spec §7, the packet Goal ("the existing 30 s loop polls only the current pair and hands every sample to the tracker"), and AC2: the current account differs from the active profile, yet it is never fetched.
   - Exact change: keep Codex shown and on `.legacy`. In the same pass, also fetch the tracker's live target without rendering it, the way multi mode fetches an unselected current account:
     - Add a pure `static func backgroundLiveTarget(subject: Profile, running: Bool, target: (profile: Profile, orgId: String)?) -> (profile: Profile, orgId: String)?`. It returns `target` only when `running && subject.provider != .anthropic`; otherwise nil.
     - When it is non-nil, the Task also calls `ProviderRegistry.service(for: .anthropic).fetchUsage(for: target.profile)`. Never `fetchUsageForActiveProfile`, and never activate the account.
     - On success, on the main actor: call `profileManager.saveClaudeUsage(newUsage, for: target.profile.id)` unless the reading is cached (`target.profile.claudeUsage == newUsage`). Then call `TeamTracker.shared.ingestLive(profileId: target.profile.id, orgId: target.orgId, result: .success(newUsage), isCachedReading:)`.
     - On error: `ingestLive(... .failure(error) ...)`.
     - Do not touch `usage`, `hasCredentialError`, `lastRefreshError`, the statusline, threshold notifications or auto-switch.
     - With tracking off, or an anthropic subject, the helper returns nil, so those paths stay exactly as they are.
     - Update the walkthrough's Acceptance lines for AC2 and AC4 with the new test.

## Tests to add
- Pure helper `backgroundLiveTarget`:
  - Codex subject, running, live target: returns the current pair, with its orgId;
  - Codex subject, no target: nil;
  - `running == false`: nil;
  - anthropic subject: nil.
- Real `TeamTracker` with fakes and a `ClockBox`, like `MenuBarTeamWiringEdgeTests.build`:
  - Setup: Codex active; tracked accounts A and B; current is B.
  - Loop passes use the helper and ingest B's sample at t0+10 (20%) and at t0+300 (50%).
  - Probe rounds run at t0+15 and t0+315, with A going from 10% to 12%.
  - Expected: `global.current` stays B, and B's `lastSampleAt` is set.
  - Today this flips to A (reviewer repro `testCurrentPairCannotDefendWhileCodexIsActive`).

## Hunter
- Major, "Codex active in single mode starves the current pair": **confirmed.**
  - Reran in a fresh scratch copy of the worktree. Output: `REVIEWER-REPRO1 shown=C plan=legacy liveTarget=Optional("org-b") currentPairUsageCalls=0 calls=["list:k-B"]`, the same as the hunter's.
  - Effect test: with Codex active, `switchedToA=true livePasses=0`. With an anthropic active profile, `switchedToA=false livePasses=2`.

## Improve later
- `.skip` and `.tracked` bypass the `hasAnyAvailableCredentials()` guard. Status (and console billing, if configured) can then run in a pass without usage credentials. Harmless.
- The single-mode catch passes the raw `error` to `ingestLive`. Passing `appError` would be tidier (arch note).
- The `UserDefaults.didChangeNotification` observer fires on every defaults write. A KVO on the one key would be tighter.
- `teamRows` builds a `StoredCredentialReader` on every body pass.
- With a Codex active profile, no "Log in again" banner appears for the hidden current account; only the Teams row and the `loginLost` notification report it. This matches spec §11 ("shown account").
