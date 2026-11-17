### MT-0 — Xcode-free validation harness (`scripts/validate-clt.sh`)

Size: M
Risk: normal
Importance: high

**Goal:** One repo-level command that validates the app and runs the whole XCTest suite on a Mac with only
Command Line Tools (no Xcode.app, no XCTest.framework, no SwiftUI/Previews macro plugins, no DynamicNotchKit or
Sparkle packages). When full Xcode is present it runs the real `xcodebuild test` instead. Every MT packet's
Validate depends on this; nothing else in the app changes.

**Proven by the architect (14 Nov 2026, CLT Swift 6.4, SDK macOS 26):** the prototype in
`.lean/plans/MT-0-ref/` built the app as a library and ran all 407 test methods in about 3.5 min:
`405 ok, 0 failed, 2 skipped` (the 2 skips are `ProfileKeychainMigrationTests` calling `XCTSkipUnless` on the
Keychain). No test file and no app file was changed. Start from those files; harden them as below.

**Facts the design rests on (do not rediscover):**
- App target settings (`project.pbxproj`, app Debug config): macOS 13.0, `SWIFT_VERSION = 5.0`, `DEBUG`,
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`,
  `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`. Without the isolation flags the app does not compile.
  Exact swiftc flags: `.lean/plans/MT-0-ref/app-flags.txt` (replace `arm64` with `$(uname -m)`). Test target:
  macOS 13.0, Swift 5, `DEBUG`, no default isolation, separate module (keep it separate: same isolation as Xcode).
- App module sources = `Claude Usage/**/*.swift` + `WidgetShared/WidgetSnapshot.swift` (app target member via
  pbxproj build file). Module name `Claude_Usage`. Imports needing stubs: `DynamicNotchKit` (NotchHUDController)
  and `Sparkle` (UpdateManager). Stub = only the symbols used; see `MT-0-ref/*Stub.swift`.
- In this SDK `@State` is a macro (`SwiftUIMacros.StateMacro`) and `#Preview` needs `PreviewsMacros`; CLT ships
  neither plugin. Fix in a preprocessed copy: `@State` -> `@CLTState` (`typealias CLTState = SwiftUI.State`,
  the property-wrapper type) and blank every top-level `#Preview { … }` block line by line.
- The real XCTest re-exports Foundation and offers `measure` and `addTeardownBlock`; tests use them.
- Tests must run in XCTest order: classes and methods sorted by name. Source order made 3 tests fail
  (shared state in `NotchHookServerTests`, `SharedDataStoreTests`). `NSLocalizedString` needs the `*.lproj`
  folders next to the runner binary (Bundle.main of a bare executable is its directory).

**Files** (all new except CONTRIBUTING.md)
- `scripts/validate-clt.sh` (bash, `set -euo pipefail`, executable)
- `scripts/clt/XCTestShim.swift` (compiled with `-module-name XCTest`), `scripts/clt/DynamicNotchKitStub.swift`
  (`-module-name DynamicNotchKit`), `scripts/clt/SparkleStub.swift` (`-module-name Sparkle`)
- `scripts/clt/preprocess.py`, `scripts/clt/gen_runner.py` (run with `python3 -I`)
- `scripts/clt/skip-list.txt`, `scripts/clt/selftest/SelfTestCases.swift`
- `CONTRIBUTING.md`: add a 6-line "Testing without Xcode" section (command, what it skips, release rule).
- Do NOT touch `project.pbxproj`, any file in `Claude UsageTests/`, `Claude Usage/`, or `.lean/tasks/MT-5/`.

**Steps**
1. CLI: `scripts/validate-clt.sh [--root DIR] [--self-test]`. `--root` defaults to
   `git rev-parse --show-toplevel` of the cwd; helper files are found relative to the script itself, so the
   script can validate another worktree. Output dir `$ROOT/build/clt/` (gitignored by `build/`), wiped per run.
2. Xcode path: `XB=${CLT_XCODEBUILD:-xcodebuild}`. If `CLT_FORCE` is unset and `"$XB" -version` exits 0, run
   `"$XB" test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build
   -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` in ROOT,
   then the final `git diff --check`, and exit with the first failure. Print `mode: xcodebuild` or `mode: clt`.
3. Drift guard (CLT path): grep the pbxproj; exit 2 with `settings drift: <setting>, update validate-clt.sh` if
   any of these is missing: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;`, `SWIFT_APPROACHABLE_CONCURRENCY = YES;`,
   `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;`, `SWIFT_VERSION = 5.0;`, or if any
   `MACOSX_DEPLOYMENT_TARGET` other than 13.0 (app, tests) or 14.0 (widget) appears.
4. Stubs and shim: build each as `-emit-library -static -parse-as-library -emit-module` into
   `build/clt/{lib,mods}` with `-target $(uname -m)-apple-macos13.0 -swift-version 5`. Shim =
   `MT-0-ref/XCTestShim.swift` plus the watchdog hook (step 8) and a header comment listing every supported API.
5. Preprocess (`preprocess.py`, from MT-0-ref): write each app source to `build/clt/src/NNN_<basename>`; first
   line `#sourceLocation(file: "<absolute original path>", line: 1)` so diagnostics name the real file and line
   (verified to work); keep line count; blank `#Preview` blocks; `@State\b` -> `@CLTState`; add `CLTSupport.swift`
   with the typealias. Touch nothing else.
6. App library = step (a), the whole-module type-check: one `swiftc -emit-library -static -parse-as-library
   -enable-testing -Onone <app flags> -module-name Claude_Usage -emit-module -I mods` over ALL preprocessed
   sources, with `-Xfrontend -entry-point-function-name -Xfrontend claude_usage_app_main`. Decision: keep the
   `@main` file in and rename its entry symbol instead of excluding it, so every app source is checked and the
   runner owns `_main`. Nothing is excluded from the app module. Errors -> print, exit 1.
7. Runner (`gen_runner.py`, from MT-0-ref): discover `class X: XCTestCase` (optionally `final`, `@MainActor`
   on the previous line) and `func test…()` with `async`/`throws`; sort by (class, method). Per test: new
   instance; `setUp() async throws`, `setUpWithError`, `setUp`; body; teardown blocks (reverse), `tearDown`,
   `tearDownWithError`, `tearDown() async throws`; teardown also runs after a failed or skipped body, and a
   throwing setUp makes the test FAIL. Print `ok   C.m`, `FAIL C.m` (each failure's `file:line message`
   indented above it) or `SKIP C.m (reason)`; then `Executed N tests: a ok, f failed, s skipped`; exit 1 if f > 0.
   Discovery cross-check: count lines matching `^\s+(@MainActor\s+)?func test\w*\(` in the test files; if it
   differs from the discovered count, exit 2 listing the missed lines (no silent omissions).
8. Watchdog: a background thread aborts the process (exit 3) with `TIMEOUT C.m` when one test runs longer than
   `CLT_TEST_TIMEOUT` seconds (default 120). Wrap the whole runner in `perl -e 'alarm 900; exec @ARGV'`.
9. Skip list `scripts/clt/skip-list.txt`: lines `Class.method  # reason` or `Class  # reason`; `#` lines are
   comments; a reason is required (exit 2 otherwise). Listed tests print `SKIP C.m (listed: reason)` and do not
   run. An entry that matches no discovered test -> exit 2 `stale skip entry`. Ship it with a header explaining
   the format and a comment (not an entry) recording that the Keychain tests skip themselves via
   `XCTSkipUnless` and why; it starts with no active entries because none are needed.
10. Compile tests: `swiftc -Onone -target … -swift-version 5 -D DEBUG -I mods -L lib -lClaude_Usage -lXCTest
    -lDynamicNotchKit -lSparkle -module-name Claude_UsageTests -o build/clt/bin/runner main.swift <original test
    files>` (test files unchanged: `import XCTest` hits the shim, `@testable import` hits the library). Copy
    `$ROOT/Claude Usage/Resources/*.lproj` into `build/clt/bin/`. Run. Last: `git -C "$ROOT" diff --check`.
11. `--self-test`: build only the shim and a runner from `scripts/clt/selftest/SelfTestCases.swift` (no app
    library, gen_runner flag `--no-app`) with a temporary skip list, `CLT_TEST_TIMEOUT=2`. Cases: one passing
    test that records setUp/teardown-block/tearDown order, one failing `XCTAssertEqual`, one test throwing a
    plain error, one `XCTSkipUnless(false)`, one listed skip, and `testZZHang` (sleeps 10 s, sorted last).
    The self-test passes (exit 0) only if the runner printed exactly those statuses, the order was right, the
    failure line names SelfTestCases.swift, `TIMEOUT` appeared and the runner exit code was 3.
12. Print elapsed seconds per phase. Document in `CONTRIBUTING.md`.

**Acceptance criteria**
1. Current branch, CLT only: `scripts/validate-clt.sh` -> `mode: clt`, exit 0, `0 failed`, ≥ 407 tests, only
   SKIPs are the two `ProfileKeychainMigrationTests` with their reason; MT-5's tests are among the `ok` lines.
2. Change one expected value in a test (e.g. in `DateExtensionsTests`), run -> exit 1,
   `FAIL DateExtensionsTests.<m>` and the original test path:line; revert.
3. Add `let _: Int = "x"` to any app file, run -> exit 1, diagnostic names `Claude Usage/…/<file>.swift:<line>`;
   revert.
4. `scripts/validate-clt.sh --self-test` -> exit 0 in under 60 s.
5. Skip-list entry without reason, or naming a missing test -> exit 2 with the message from step 9.
6. `CLT_XCODEBUILD=<fake script that exits 0 and logs its args>` -> `mode: xcodebuild`, fake called with
   `-version` then `test -project "Claude Usage.xcodeproj" …`; `CLT_FORCE=1` with the same fake -> `mode: clt`.
7. `--root <other worktree>` validates that tree's sources and tests (the printed root and counts show it).
8. Full run < 8 min on this Mac; after a run `git status` shows nothing new outside `build/`.
9. The packet's diff touches only `scripts/` and `CONTRIBUTING.md` (no pbxproj, no app or test sources).

**Tests:** the self-test (criterion 4) is the harness's own test; criteria 2, 3, 5, 6 are manual runs the
builder records in walkthrough.md with the exact output lines. Edge cases: `@MainActor` on the line above a
test class, `async throws` tests, setUp throwing (FAIL, teardown still runs), paths with spaces
("Claude Usage", "Claude UsageTests"), two runs in a row (second run must not reuse stale build output).

**Validate:** `scripts/validate-clt.sh` `scripts/validate-clt.sh --self-test` `git diff --check`

**Coverage limit (state it in CONTRIBUTING.md and the script header):** without Xcode the widget extension,
the asset catalog, Info.plist processing, code signing and the real DynamicNotchKit/Sparkle APIs are not built
or checked, and `#Preview` bodies are not compiled. One full `xcodebuild` build+test run is required before any
release.
