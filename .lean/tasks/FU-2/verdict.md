## Verdict
PASS. Both r0 Must-fix parts are in place at all three gated sites, and the same-pair skip is kept. I reran the gates myself (STRICT): validate-clt exit 0, 619 tests, 0 failed. `git diff --check` is clean.

## How it's going
Grade A. The fix is small and exact. One release helper (`endGatedLivePoll`, wired by `endLivePoll`) serves the background site, the single-mode `.tracked` defer and the multi-mode loop defer. One pure rule (`showsFetchedReading`) keeps a late tracker-owned reading off the menu bar.
The tests drive the production helpers with a real `TeamTracker`. They cover a user move, a live-sample move (other org), the same pair, move away and back, failure, cancel, 429, tracker stop and a re-run chain, and the mutation runs show the tests fail when the fix is removed.

## Done well
- `endGatedLivePoll` frees the gate first and then re-runs only when `liveTarget()` is a different pair (profile id or org id). A dropped pass for a new current pair now runs right after the fetch ends, and a duplicate for the same pair is never re-sent.
- I checked by reading that every `global.current` change in `TeamTracker` (`moveCurrent`, `repairCurrent`, `deleteOldPair`, the old/unreachable path in `apply`) fires `onCurrentChanged`. So each re-run stands in for exactly one dropped pass. The fetched pair always equals `liveTarget()` at pass start, so a re-run cannot loop.
- Every successful `begin()` still reaches exactly one `endLivePoll`. No `endLivePoll` runs without a `begin()`: the guards are `trackerOrgId`, `holdsLiveGate` plus `liveOrgIds`, and the release closure inside the Task. `endLivePoll` is only called from Task bodies, so `refreshUsage()` never re-enters itself.
- Single mode now writes `usage`, the session-limit rebuild, the statusline and the icons only while the fetched account is shown. Save, notifications, auto-switch and `ingestLive` are unchanged, as r0 asked. This also stops a late reading from overwriting a Codex profile the user just activated.
- Hard rules: only `MenuBarManager.swift` and `MenuBarTeamWiringEdgeTests.swift` changed (test file +512/-0). No test was deleted or weakened. No skip, xfail or suppression was added. `scripts/` and the skip-list are unchanged. The walkthrough's `## Acceptance` has evidence for each criterion and each r0 Must-fix line.

## Must fix
(none)

## Tests to add
(none)

## Hunter
- No findings this round (HUNTER: []). Gemini cross-review was unavailable.
- r0 major (the gate dropped the new current pair and showed the old reading): fixed. `testCurrentMovedWhileFetchInFlightFetchesNewPairOnceAfterRelease`, `testLiveSampleSwitchFetchesNewPairOnceAfterRelease` and `testTrackedReadingReachesMenuBarOnlyWhileItsAccountIsShown` pass in my rerun.

## Improve later
- Toggle off and on during a fetch (`ponytail`, carried over): a stale `end()` can clear a newer holder, and its re-run check can start one extra pass. Fix: `begin()` returns a generation token, and `end(token)` and the re-run check act only for a matching token.
- These are covered by reading only (carried over): the `.tracked` defer, the multi-mode loop defer, the `isShown` call site and the toggle reset. Pull each into a small pure helper so a test can drive it.
- `showsFetchedReading` compares the profile id only. If the current pair moves from (B, org-b) to (B, org-a) during B's fetch, the org-b reading is still shown and saved to B until the re-run's fetch replaces it. That window is about one fetch, which is better than before FU-2, when the two fetches raced. To close it, compare against the full current pair.
- The statusline write now also needs `isShown`. When the active account B is fetched and the current moves away mid-fetch, B's correct reading misses the CLI statusline cache, because live samples do not fire `onSample`. It then waits for the next probe round. `profile.id == activeProfile.id` alone would be enough for the statusline (r0 asked for the `isShown` gate here).
- A re-run repeats the whole pass. In multi mode or with Codex shown, the dropped pass has already run status and console billing (and the Codex fetch). So each move during a fetch costs one extra round of these requests, none of which hit the usage endpoint. The usage-endpoint request count matches pre-FU-2. A re-run that only does the live fetch would avoid the extra round.
- Same-pair skip after a shown-profile switch: the user activates an anthropic profile while the background poll of the current pair is in flight. The `.tracked` pass is then dropped (same pair), and `handleProfileSwitch` shows that account's older saved reading until the next timer pass. Fix: apply the saved reading when the fetched account is the shown one at release.
