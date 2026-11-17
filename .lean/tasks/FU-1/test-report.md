## Tester result
all green

## Suites run
- `bash scripts/validate-clt.sh` (mode: clt) → `Executed 619 tests: 617 ok, 0 failed, 2 skipped`, exit 0. The 2 skips are the existing keychain skips.
- `git diff --check` → clean, exit 0.
- Mutation run 1 (TeamTracker.swift reverted to HEAD, runner guard weakened to `!timeout.isNaN`) → `Executed 619 tests: 606 ok, 11 failed, 2 skipped`. 4 of the new tester tests failed, plus `testNegativeInfiniteTimeoutReturnsAllResults` and the builder's 6.
- Mutation run 2 (runner guard `timeout.isFinite, timeout >= 0`; OAuth cutoff changed to `max(lastSampleAt ?? .distantPast, now - round)`) → `Executed 619 tests: 615 ok, 2 failed, 2 skipped`. The failures were `testNegativeFiniteTimeoutClampsToZeroAndExpires` and `testOAuthOnlyWithPriorSampleUsesLastSampleNotRoundWindow`.
- The source files were restored byte for byte after each mutation run (checked with `cmp`), and the final run above is on the restored code.

## New tests
`Claude UsageTests/TeamTrackerTests.swift` (5 tests and 1 helper, `assertPickRefusedAfterActivity`, which checks that the notification count does not change instead of requiring an empty notifier):
- `testMakeCurrentBackoffBoundaryUsesCallTimeClock`: the backoff ends at t0+120 (Retry-After 120). A pick at t0+119 is refused and a pick at t0+120 is accepted, so the guard reads the clock when the call is made.
- `testGroupMoveMixedPeersUnauthorizedAndMoved`: three accounts share org-a. The peer whose list returns 401 gets needsLogin, one loginLost event and is unchecked. The peer whose list confirms gets org-a `.old` and appears in moves (with the trigger). notMoved is empty. Afterwards a manual pick of either dead pair is refused (integration of fix 1 and fix 2).
- `testGroupMovePeerListRateLimitedIsUncheckedAndBlocksManualPickUntilBackoffEnds`: a 429 on the peer's group-move list does not trigger rule L. The peer is unchecked and stays logged in. A pick of it is refused during backoff and accepted at t0+3000.
- `testOAuthOnlyFirstReadingCutoffBoundary`: with no sample yet, a reading exactly at `now - roundInterval` is rejected (no save, no onSample, lastSampleAt nil), and a reading 1 s later is accepted.
- `testOAuthOnlyWithPriorSampleUsesLastSampleNotRoundWindow`: once a sample exists, it is the cutoff. A reading newer than the last sample but older than one round is accepted, and a reading equal to the last sample is rejected. This guards against the check becoming `max(...)`.

`Claude UsageTests/BoundedTaskRunnerTests.swift` (2 tests):
- `testNegativeInfiniteTimeoutReturnsAllResults`: `-.infinity` means no timer, so all results come back. Under the old `max(0, t)` it became a zero timer.
- `testNegativeFiniteTimeoutClampsToZeroAndExpires`: a timeout of -5 is clamped to 0, the timer still fires at once, the slow items are nil, and the call returns in under 1 s.

## Bugs
None found.
