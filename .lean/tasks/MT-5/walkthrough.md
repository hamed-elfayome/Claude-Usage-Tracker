## Summary
TeamPollScheduler (pure value-type poll/backoff scheduler) and BoundedTaskRunner (TaskGroup runner, global and per-key limits, timeout).
Round 1: timed-out items now stay nil; listFinished no longer schedules accounts without an org list.
No XCTest run was possible (no Xcode on this machine).
## Changes
- Shared/MultiTeam/TeamPollScheduler.swift: types and scheduler; listFinished sets nextList only if hasOrgList.
- Shared/MultiTeam/BoundedTaskRunner.swift: runner; `expired` flag drops values finishing after timeout.
- Claude UsageTests/TeamPollSchedulerTests.swift: tests, plus listFinished no-org-list and 59.9/60 s debounce boundary.
- Claude UsageTests/BoundedTaskRunnerTests.swift: tests, plus testTimedOutItemStaysNil.
## Acceptance
Not executed under XCTest; evidence is the test named, written but not run.
1. met in test only: testRoundTiming
2. met in test only: testListStartSpreadAndInterval
3. met in test only: testNoOrgListNeverDue (now also covers listFinished success and 429)
4. met in test only: testBackoffSequence
5. met in test only: testJitterBounds
6. met in test only: testRetryAfter
7. met in test only: testBackingOffExcludedAndOthersUnaffected
8. met in test only: testSuccessClearsBackoff
9. met in test only: testForceListDebounce, testForceListDebounceBoundary
10. met in test only: testUnregisterAndUnknown
11. met in test only: testGlobalLimit
12. met in test only: testPerKeyLimit
13. met in test only: testTimeout, testTimedOutItemStaysNil (fix applied, not run)
14. met for MT-5 tests via shim (17 tests, 0 failures); full app XCTest suite not run (no Xcode)
## Flow
MT-6 tracker asks scheduler what is due, runs work via BoundedTaskRunner, feeds outcomes back through listFinished/record.
## Tests
Command: `.lean/tasks/MT-5/validate/run.sh` (XCTest shim, no Xcode needed). Result: `Executed 17 tests, 0 failures`. The xcodebuild line is not runnable here (xcode-select points at CommandLineTools); packet Validate line updated accordingly. Full suite still owed on a machine with Xcode.
## Edge cases
Register twice keeps due time; listFinished/record on unknown account ignored; empty items; forceList false for unknown or no-org-list accounts. Not handled: blocking (non-cancellable) bodies hold the call for their full duration; timeout .infinity may trap.
## Shortcuts
none
## Lessons
Generic functions cannot nest enums (RunnerEvent is file-private). No Xcode on this machine.
