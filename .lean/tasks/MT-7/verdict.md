## Verdict PASS
PASS. Round 2 fixes the one Must fix. With Team tracking on and a Codex active profile in single mode, every loop pass now also polls the current anthropic pair per profile (never activated, never shown) and hands each result to `ingestLive`. Gates are green on my own rerun.

## How it's going
Grade B. The round-2 change is small and matches the prescription: two pure static helpers and a 7-line call site, covered by a pure-helper test and three real-tracker tests that fail when the poll is removed.
It took two fix rounds, and the `refreshUsage()` call sites are still checked by code reading only.

## Done well
- Must fix 1 is met, point by point:
  - `backgroundLiveTarget(subject:running:target:)` (MenuBarManager.swift:175) returns the target only when `running && subject.provider != .anthropic`.
  - `pollLiveTarget` (:184) fetches only through `ProviderRegistry.service(for: .anthropic).fetchUsage(for:)`.
    - Success: saves the reading unless it is the cached one (`target.profile.claudeUsage == newUsage`), then calls `ingestLive(.success, isCachedReading:)`.
    - Error: calls `ingestLive(.failure)`.
    - It leaves `usage`, the banner, the statusline, threshold alerts and auto-switch alone.
  - It runs on the main actor. The app target and the CLT build both use default MainActor isolation, so the static func and its `Task` are main-actor isolated.
  - The call site (:1464-1470) starts the poll before the `.legacy` credentials guard (:1496), so a Codex profile without credentials does not starve the pair. The only earlier exits (multi mode, nil `menuBarProfile`) never have a Codex profile shown.
  - With the tracker off or an anthropic subject, the helper returns nil and no `Task` is created, so those paths are byte-for-byte unchanged.
- AC2 holds for the Codex case:
  - The polled account is never the active profile (Codex is), so `ensureFreshCredentials` never takes the system-keychain branch (ClaudeCodeSyncService.swift:1070) and never rotates an unpinned token (:1163).
  - `fetchUsage(for:)` reads the system keychain only for the active profile (AnthropicUsageProvider.swift:71).
  - `moveCurrent` keeps `organizationId == current.orgId` for session-key accounts (TeamTracker.swift:447), so each reading is filed under the right pair.
- Round 2 is purely additive. I diffed against the round-1 review copy. The only changes are:
  - the two helpers and the call site;
  - one pure-helper test and three real-tracker tests;
  - a mutable `ClockBox` in `build()` that stays at t0 for the old tests.
- Nothing was weakened or removed:
  - no assertion was weakened and no test deleted (596 tests became 600);
  - no skip was added, and the CLT skip list is still empty;
  - `scripts/` and the pbxproj are untouched (the test folder is a synchronized group);
  - no MT-7 file has a compiler warning (all 333 warning lines are in older files).
- The walkthrough's Acceptance section has one line with evidence per criterion. AC2 and AC4 name the new tests, as the last verdict asked.

## Must fix
(none)

## Tests to add
(none)

## Hunter
- No findings this round (HUNTER: []). No Gemini cross-review this round.
- The previous major finding, "Codex active in single mode starves the current pair", is fixed. I checked this with a reviewer mutation on a scratch copy: `backgroundLiveTarget` always returns nil, which is the round-1 behaviour.
  - Result: `Executed 600 tests: 594 ok, 4 failed, 2 skipped`. Only the four new tests failed.
  - `testCodexActiveLoopPollsCurrentPairSoItDefends` failed at :334 with current = `(A, org-a)`, the same flip as the round-1 repro, so the test checks real tracker behaviour and not only the fetch count.

## Improve later
- The `refreshUsage()` call site (:1464-1470) is checked by code reading only. The tests drive the same helpers, but not the `MenuBarManager.shared` path. A seam that returns the plan and the background target together would let one test cover the wiring.
- Two passes close together (the timer plus `onCurrentChanged`) poll the current pair twice. An in-flight flag would keep spec §7's budget of 4 requests per 30 s during bursts. The existing `.tracked` path behaves the same way.
- Carried over from earlier rounds:
  - `.skip` and `.tracked` bypass `hasAnyAvailableCredentials()`;
  - the catch paths pass the raw `error` to `ingestLive` (passing an `AppError` would be tidier);
  - the `UserDefaults.didChangeNotification` observer fires on every defaults write;
  - `teamRows` builds a `StoredCredentialReader` on every body pass;
  - with Codex shown, a hidden current account that needs a new login shows no banner. This matches spec §11 ("shown account").
