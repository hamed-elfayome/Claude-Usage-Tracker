#!/bin/zsh
# Runs MT-5 tests without Xcode: compiles the two sources and two test files against a tiny XCTest shim.
set -e
D=$(cd "$(dirname "$0")" && pwd); R=$(cd "$D/../../../.." && pwd); T=$(mktemp -d)
for f in TeamPollSchedulerTests BoundedTaskRunnerTests; do
  { echo "import Foundation"; grep -v '^import XCTest\|^@testable' "$R/Claude UsageTests/$f.swift"; } > $T/$f.swift
done
python3 -I - "$T" <<'PY'
import re,sys
t=sys.argv[1]; out="import Foundation\nvar total=0\n"
for c in ["TeamPollSchedulerTests","BoundedTaskRunnerTests"]:
    for m in re.finditer(r"func (test\w+)\(\)( async)?",open(f"{t}/{c}.swift").read()):
        a="await " if m.group(2) else ""
        out+=f'do {{ let b=xctFailures; {a}{c}().{m.group(1)}(); total+=1; print("\\(xctFailures==b ? "ok  " : "FAIL") {c}.{m.group(1)}") }}\n'
out+='print("Executed \\(total) tests, \\(xctFailures) failures"); exit(xctFailures==0 ? 0 : 1)\n'
open(f"{t}/main.swift","w").write(out)
PY
swiftc -o $T/t "$D/XCTestShim.swift" $T/TeamPollSchedulerTests.swift $T/BoundedTaskRunnerTests.swift $T/main.swift "$R/Claude Usage/Shared/MultiTeam/TeamPollScheduler.swift" "$R/Claude Usage/Shared/MultiTeam/BoundedTaskRunner.swift"
$T/t
