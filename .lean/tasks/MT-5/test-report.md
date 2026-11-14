## Tester result
All green: 17 of 17 pass on the XCTest-shim harness (0 failing); full XCTest suite not run (no Xcode), 0 new tests added.

## Suites run
- `zsh .lean/tasks/MT-5/validate/run.sh` → `Executed 17 tests, 0 failures` (exit 0). This is the shim harness, not XCTest.
- `git diff --check` → exit 0, no output. The tracked diff is empty, so I also ran `git diff --no-index --check /dev/null <file>` on the four new files → 0 whitespace hits each.
- `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` → not run: `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`.
- Probe, not a suite: `BoundedTaskRunner.run([1, 2], …, timeout: .infinity)` → `Fatal error: Double value cannot be converted to UInt64 because it is either infinite or NaN`, exit 133 (see Bugs 1).

## New tests
None. The only verdict "Tests to add" line is "Run the full XCTest suite once on a machine with Xcode (criterion 14)". That is a run request, not a test case, and it cannot be done on this machine. The behaviours the earlier verdict lines named are already covered by existing tests:
- `Claude UsageTests/BoundedTaskRunnerTests.swift:43` testTimedOutItemStaysNil (timed-out item stays nil, call returns < 1 s).
- `Claude UsageTests/TeamPollSchedulerTests.swift:29` testNoOrgListNeverDue (listFinished success and 429 never schedule a list for an account without an org list).
- `Claude UsageTests/TeamPollSchedulerTests.swift:38` testForceListDebounceBoundary (59.9 s → false, 60 s → true).

Still owed: the full app XCTest run (`xcodebuild test`, criterion 14) on a machine with full Xcode.

## Bugs
Carried from round 1; still present in the code; the verdict marks them improve-later, not blocking. No new bugs found this round.
1. `Claude Usage/Shared/MultiTeam/BoundedTaskRunner.swift:29`: `UInt64(max(0, timeout) * 1_000_000_000)` traps for an infinite or NaN timeout.
   - Input: `BoundedTaskRunner.run([1, 2], key: { _ in UUID() }, maxConcurrent: 4, maxPerKey: 1, timeout: .infinity) { $0 }`
   - Expected: no timer is started; the call returns `[(1, 1), (2, 2)]`.
   - Actual: `Fatal error: Double value cannot be converted to UInt64 because it is either infinite or NaN`, exit 133 (re-run this round).
   - Reproduce: `swiftc -o p "Claude Usage/Shared/MultiTeam/BoundedTaskRunner.swift" main.swift && ./p`, where main.swift holds the call above with top-level `await`. Probe dir: `/private/tmp/claude-501/-Users-kuke-Coding-Claude-Usage-Tracker--claude-worktrees-full-development-bb60d3/9a1625a4-fa5c-4a5d-a354-dd35ab54f4f0/scratchpad/mt5/probe_inf_r2`. No test added, since a trapping test kills the whole test process.
2. `Claude Usage/Shared/MultiTeam/BoundedTaskRunner.swift`, `run()` (the `withTaskGroup` block waits for every child): design limit, not re-run this round.
   - Input: item 2 body is `Thread.sleep(forTimeInterval: 2)` (blocking, not cancellable), timeout 0.1; item 1 returns at once.
   - Expected (spec §7 item 13, call returns in < 1 s): returns in under 1 s.
   - Actual (round 1 probe): `r = [Optional(1), nil]`, values correct, but elapsed 2.007 s, because the group waits for the blocking child.
   - The packet's own test uses a cancellable body, so it passes. Documented in the walkthrough; the verdict asks to narrow the spec wording.
