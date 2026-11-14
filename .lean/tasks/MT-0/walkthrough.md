## Summary
`scripts/validate-clt.sh` validates the app on a CLT-only Mac: builds the app as a library with stubs and an XCTest shim, runs all tests; with Xcode it runs `xcodebuild test`.
Helpers live in `scripts/clt/`. `--self-test` checks the harness itself in ~7 s.
## Changes
- scripts/validate-clt.sh: driver (mode switch, drift guard, phases, timeouts, self-test).
- scripts/clt/XCTestShim.swift: XCTest stand-in plus watchdog (exit 3, `TIMEOUT C.m`) and API-list header.
- scripts/clt/DynamicNotchKitStub.swift, SparkleStub.swift: symbols the app uses.
- scripts/clt/preprocess.py: `#sourceLocation`, `@State`->`@CLTState`, blank `#Preview`, CLTSupport.swift.
- scripts/clt/gen_runner.py: discovery, sorted order, skip list, discovery cross-check, runner generation.
- scripts/clt/skip-list.txt, selftest/SelfTestCases.swift: skip list (no entries) and self-test cases.
- CONTRIBUTING.md: "Testing without Xcode" section.
## Acceptance
1. Met: `mode: clt`, three consecutive runs after the fix each ended `Executed 407 tests: 405 ok, 0 failed, 2 skipped`, rc=0; only skips are the 2 ProfileKeychainMigrationTests. Before the fix the gate run had 1 failed, 404 ok: `NotchHookServerTests.testLegacyTokenlessPathGets404AndIsDropped` (connection refused on 127.0.0.1:19847), fixed by the main-actor pause in the runner (see Lessons).
2. Met: edited DateExtensionsTests.swift:14 -> `FAIL DateExtensionsTests.testNextMondayFromSunday`, `.../Claude UsageTests/DateExtensionsTests.swift:14 equal`, rc=1; reverted.
3. Met: `Claude Usage/Shared/Utilities/Constants.swift:222:21: error: cannot convert value of type 'String' to specified type 'Int'`, rc=1; reverted.
4. Met: `--self-test` prints `self-test: PASS`, ~7 s.
5. Met: `skip-list: reason required: ...` and `stale skip entry: ...`, both rc=2 (before the slow app build).
6. Met: fake logged `-version` then `test -project Claude Usage.xcodeproj -scheme ... CODE_SIGNING_ALLOWED=NO`, `mode: xcodebuild`; `CLT_FORCE=1` goes on to the clt path (`mode: clt`).
7. Met: `scripts/validate-clt.sh --root <copy in mktemp dir + git init>` printed `root: /var/folders/ll/tbvv04fx4058bzlq4zdsxdr40000gn/T/tmp.SGDPynAPnN` and `Executed 407 tests: 405 ok, 0 failed, 2 skipped`.
8. Met: idle full runs took 164.9 s, 155.4 s, 143.0 s (limit 480 s); `--self-test` ~4 s. `git status` shows nothing new outside build/ (only the new scripts).
9. Met: diff touches only scripts/ and CONTRIBUTING.md (plus this packet dir).
## Flow
validate-clt.sh -> (xcodebuild test) or drift guard -> build stubs+shim -> gen_runner.py (skip list, cross-check; fails fast) -> preprocess.py -> swiftc app library (entry symbol renamed) -> swiftc runner (main.swift + original tests) -> perl alarm 900 -> runner (per-test setUp/teardown, watchdog) -> `git diff --check`.
## Tests
Self-test: `scripts/validate-clt.sh --self-test` -> `self-test: PASS` (main-actor pause regression SelfPauseTests, statuses, setUp/teardown order, failure path names SelfTestCases.swift, teardown after throwing setUp, TIMEOUT, exit 3). Manual criteria 2, 3, 5, 6 recorded above. Full run: `Executed 407 tests: 405 ok, 0 failed, 2 skipped`.
## Edge cases
Handled: `@MainActor` before a class, async throws tests, throwing setUp (FAIL, teardown runs, self-test), paths with spaces, stale output (OUT wiped per run), undiscovered test methods (exit 2). Not handled: XCTestExpectation/wait (not used by tests; compile error tells you to extend the shim).
## Shortcuts
- `ponytail:` XCTestShim watchdog state is unlocked (single watcher thread); add a lock if it races.
## Lessons
- `NotchHook.stop()` sets `serverStatus = .stopped` in an unawaited `Task { @MainActor }`; the runner never suspended the main actor between tests, so the next `NotchHookServerTests.setUp` saw the stale `.running` and the POST hit an unbound port (`testLegacyTokenlessPathGets404AndIsDropped`). The runner now sleeps 100 ms after each test; `SelfPauseTests` in the self-test guards this (testB FAILs without the pause).
- The app library compile takes 2 to 8 minutes depending on machine load.

