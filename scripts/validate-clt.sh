#!/usr/bin/env bash
# Validate the app and run the whole XCTest suite.
#   scripts/validate-clt.sh [--root DIR] [--self-test]
# With full Xcode: runs `xcodebuild test`. With only Command Line Tools: builds the app as a
# library (stubs for DynamicNotchKit and Sparkle, a small XCTest shim) and runs every test.
# Env: CLT_XCODEBUILD (xcodebuild path), CLT_FORCE (use the CLT path), CLT_TEST_TIMEOUT (s, default 120).
#
# Coverage limit: without Xcode the widget extension, the asset catalog, Info.plist processing,
# code signing and the real DynamicNotchKit/Sparkle APIs are not built or checked, and #Preview
# bodies are not compiled. Run one full xcodebuild build+test before any release.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLT="$HERE/clt"
ROOT=""
SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:?--root needs a directory}"; shift 2 ;;
    --self-test) SELFTEST=1; shift ;;
    *) echo "usage: validate-clt.sh [--root DIR] [--self-test]" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel)"
ROOT="$(cd "$ROOT" && pwd)"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos13.0"
OUT="$ROOT/build/clt"

phase_start=$SECONDS
phase() { echo "[phase] $1 (${2}s)"; }
lap() { local n=$((SECONDS - phase_start)); phase "$1" "$n"; phase_start=$SECONDS; }

if [ "$SELFTEST" = 0 ]; then
  echo "root: $ROOT"
  XB="${CLT_XCODEBUILD:-xcodebuild}"
  if [ -z "${CLT_FORCE:-}" ] && "$XB" -version >/dev/null 2>&1; then
    echo "mode: xcodebuild"
    cd "$ROOT"
    "$XB" test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug \
      -derivedDataPath build -destination "platform=macOS" \
      CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
    git diff --check
    exit 0
  fi
  echo "mode: clt"

  PBX="$ROOT/Claude Usage.xcodeproj/project.pbxproj"
  for s in 'SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;' 'SWIFT_APPROACHABLE_CONCURRENCY = YES;' \
           'SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;' 'SWIFT_VERSION = 5.0;'; do
    grep -qF "$s" "$PBX" || { echo "settings drift: $s, update validate-clt.sh" >&2; exit 2; }
  done
  bad="$(grep -o 'MACOSX_DEPLOYMENT_TARGET = [0-9.]*' "$PBX" | sort -u | grep -v -e ' = 13\.0$' -e ' = 14\.0$' || true)"
  [ -z "$bad" ] || { echo "settings drift: $bad, update validate-clt.sh" >&2; exit 2; }
fi

[ -n "$OUT" ] && rm -rf "$OUT"
mkdir -p "$OUT/lib" "$OUT/mods" "$OUT/src" "$OUT/bin"

# Build one support module (stub or shim) as a static library + module.
build_mod() { # name source
  swiftc -emit-library -static -parse-as-library -emit-module -module-name "$1" \
    -target "$TARGET" -swift-version 5 -emit-module-path "$OUT/mods/$1.swiftmodule" \
    -o "$OUT/lib/lib$1.a" "$2"
}

# Compile the runner and run it under a 900 s alarm; sets RC and LOG.
run_runner() { # runner-binary
  LOG="$OUT/run.log"
  set +e
  perl -e 'alarm 900; exec @ARGV' "$1" 2>&1 | tee "$LOG"
  RC=${PIPESTATUS[0]}
  set -e
}

if [ "$SELFTEST" = 1 ]; then
  echo "self-test"
  build_mod XCTest "$CLT/XCTestShim.swift"
  lap shim
  printf 'SelfOutcomeTests.testListedSkip  # selftest\n' > "$OUT/skip.txt"
  python3 -I "$CLT/gen_runner.py" --no-app --skip-list "$OUT/skip.txt" "$CLT/selftest/SelfTestCases.swift" > "$OUT/main.swift"
  swiftc -Onone -target "$TARGET" -swift-version 5 -D DEBUG -I "$OUT/mods" -L "$OUT/lib" -lXCTest \
    -module-name SelfTests -o "$OUT/bin/runner" "$OUT/main.swift" "$CLT/selftest/SelfTestCases.swift"
  lap build
  export CLT_TEST_TIMEOUT=2
  run_runner "$OUT/bin/runner"
  lap run
  expected='ok   SelfOrderTests.testOrder
FAIL SelfOutcomeTests.testFailEqual
SKIP SelfOutcomeTests.testListedSkip (listed: selftest)
SKIP SelfOutcomeTests.testSkipUnless (selftest reason)
FAIL SelfOutcomeTests.testThrows
ok   SelfPauseTests.testA
ok   SelfPauseTests.testB
FAIL SelfSetUpThrowTests.testSetUpThrows
TIMEOUT SelfZHangTests.testZZHang'
  got="$(grep -E '^(ok|FAIL|SKIP|TIMEOUT) ' "$LOG" || true)"
  fail=0
  [ "$got" = "$expected" ] || { echo "self-test: statuses differ:"; echo "$got"; fail=1; }
  grep -qxF 'ORDER:setUpAsync,setUpWithError,setUp,body,block2,block1,tearDown,tearDownWithError,tearDownAsync' "$LOG" \
    || { echo "self-test: setUp/teardown order wrong"; fail=1; }
  grep -qE '^    .*SelfTestCases\.swift:[0-9]+ ' "$LOG" || { echo "self-test: failure line lacks SelfTestCases.swift"; fail=1; }
  grep -qxF 'TEARDOWN-RAN' "$LOG" || { echo "self-test: teardown did not run after throwing setUp"; fail=1; }
  [ "$RC" = 3 ] || { echo "self-test: runner exit $RC, expected 3"; fail=1; }
  [ "$fail" = 0 ] && echo "self-test: PASS"
  exit "$fail"
fi

# --- CLT path ---
build_mod XCTest "$CLT/XCTestShim.swift"
build_mod DynamicNotchKit "$CLT/DynamicNotchKitStub.swift"
build_mod Sparkle "$CLT/SparkleStub.swift"
lap "stubs+shim"

# Discover tests and check the skip list first: cheap, and fails fast.
TESTS=()
while IFS= read -r f; do TESTS+=("$f"); done < <(find "$ROOT/Claude UsageTests" -name '*.swift' | LC_ALL=C sort)
python3 -I "$CLT/gen_runner.py" --skip-list "$CLT/skip-list.txt" "${TESTS[@]}" > "$OUT/main.swift" || { rc=$?; exit "$rc"; }

APP=()
while IFS= read -r f; do APP+=("$f"); done < <(find "$ROOT/Claude Usage" -name '*.swift' | LC_ALL=C sort)
APP+=("$ROOT/WidgetShared/WidgetSnapshot.swift")
python3 -I "$CLT/preprocess.py" "$OUT/src" "${APP[@]}"
lap "preprocess (${#APP[@]} files)"

# Same flags as the Xcode app target (Debug).
APPFLAGS=(-target "$TARGET" -swift-version 5 -D DEBUG -default-isolation MainActor
  -enable-upcoming-feature MemberImportVisibility -enable-upcoming-feature NonisolatedNonsendingByDefault
  -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature InferSendableFromCaptures
  -enable-upcoming-feature GlobalActorIsolatedTypesUsability -enable-upcoming-feature DisableOutwardActorInference)
SRCS=()
while IFS= read -r f; do SRCS+=("$f"); done < <(find "$OUT/src" -name '*.swift' | LC_ALL=C sort)
# The @main file stays in (every source is checked); only its entry symbol is renamed.
if ! swiftc -emit-library -static -parse-as-library -enable-testing -Onone "${APPFLAGS[@]}" \
    -module-name Claude_Usage -emit-module -emit-module-path "$OUT/mods/Claude_Usage.swiftmodule" -I "$OUT/mods" \
    -Xfrontend -entry-point-function-name -Xfrontend claude_usage_app_main \
    -o "$OUT/lib/libClaude_Usage.a" "${SRCS[@]}"; then
  echo "app build failed" >&2; exit 1
fi
lap "app library"

if ! swiftc -Onone -target "$TARGET" -swift-version 5 -D DEBUG -I "$OUT/mods" -L "$OUT/lib" \
    -lClaude_Usage -lXCTest -lDynamicNotchKit -lSparkle -module-name Claude_UsageTests \
    -o "$OUT/bin/runner" "$OUT/main.swift" "${TESTS[@]}"; then
  echo "test build failed" >&2; exit 1
fi
cp -R "$ROOT/Claude Usage/Resources/"*.lproj "$OUT/bin/"
lap "test build (${#TESTS[@]} files)"

run_runner "$OUT/bin/runner"
lap "run"
git -C "$ROOT" diff --check
exit "$RC"
