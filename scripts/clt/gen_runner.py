"""Generate the XCTest-free runner main.swift on stdout.

Usage: python3 -I gen_runner.py [--no-app] --skip-list FILE TESTFILE...
Exit 2 on a bad skip list, a stale skip entry or a test method discovery missed.
"""
import re, sys, json

args = sys.argv[1:]
no_app = False
skip_file = None
files = []
while args:
    a = args.pop(0)
    if a == '--no-app':
        no_app = True
    elif a == '--skip-list':
        skip_file = args.pop(0)
    else:
        files.append(a)

def die(msg):
    sys.stderr.write(msg + '\n')
    sys.exit(2)

CLS = re.compile(r'^\s*(?:@\w+\s+)*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b')
OTHER = re.compile(r'^(?:@\w+\s+)*(?:final\s+)?(?:class|struct|enum|extension|actor)\s')
FUNC = re.compile(r'^\s+(?:@MainActor\s+)?func\s+(test\w*)\(\)\s*(async)?\s*(throws)?')
ANY = re.compile(r'^\s+(@MainActor\s+)?func test\w*\(')

tests = []
raw = []
for f in files:
    cls = None
    for n, ln in enumerate(open(f, encoding='utf-8'), 1):
        m = CLS.match(ln)
        if m:
            cls = m.group(1)
            continue
        if OTHER.match(ln):
            cls = None
        if ANY.match(ln):
            raw.append("%s:%d: %s" % (f, n, ln.strip()))
        m = FUNC.match(ln)
        if m and cls:
            tests.append((cls, m.group(1), bool(m.group(2)), bool(m.group(3)), "%s:%d: %s" % (f, n, ln.strip())))
if len(raw) != len(tests):
    found = {t[4] for t in tests}
    die("discovery missed %d test method(s):\n%s" % (len(raw) - len(tests), "\n".join(r for r in raw if r not in found)))
tests.sort(key=lambda t: (t[0], t[1]))

skips = {}
if skip_file:
    for ln in open(skip_file, encoding='utf-8'):
        s = ln.strip()
        if not s or s.startswith('#'):
            continue
        name, sep, reason = s.partition('#')
        name, reason = name.strip(), reason.strip()
        if not reason:
            die("skip-list: reason required: " + s)
        skips[name] = reason
names = {"%s.%s" % (c, m) for c, m, _, _, _ in tests} | {c for c, _, _, _, _ in tests}
for k in skips:
    if k not in names:
        die("stale skip entry: " + k)

o = ['import Foundation', 'import XCTest']
if not no_app:
    o.append('@testable import Claude_Usage')
o += [
'var ok = 0, failed = 0, skipped = 0',
'@MainActor func run<T: XCTestCase>(_ name: String, _ make: () -> T, _ body: (T) async throws -> Void) async {',
'  _xctBegin(name); let before = xctFailures; var skip: String? = nil; let t = make()',
'  do { try await t.setUp(); try _xctSyncSetUp(t); try await body(t) }',
'  catch let s as XCTSkip { skip = s.message.isEmpty ? "skipped" : s.message }',
'  catch { xctFailures += 1; print("    threw \\(error)") }',
'  do { try _xctSyncTearDown(t); try await t.tearDown() } catch { xctFailures += 1; print("    tearDown threw \\(error)") }',
'  _xctEnd()',
'  try? await Task.sleep(nanoseconds: 100_000_000)',
'  if xctFailures > before { failed += 1; print("FAIL \\(name)") }',
'  else if let s = skip { skipped += 1; print("SKIP \\(name) (\\(s))") }',
'  else { ok += 1; print("ok   \\(name)") }',
'}',
'_xctStartWatchdog(Double(ProcessInfo.processInfo.environment["CLT_TEST_TIMEOUT"] ?? "") ?? 120)',
]
for c, m, a, t, _ in tests:
    full = "%s.%s" % (c, m)
    reason = skips.get(full) or skips.get(c)
    if reason:
        o.append('skipped += 1; print(%s)' % json.dumps("SKIP %s (listed: %s)" % (full, reason), ensure_ascii=False))
        continue
    call = ("try " if t else "") + ("await " if a else "") + "$0.%s()" % m
    o.append('await run("%s", { %s() }) { %s }' % (full, c, call))
o.append('print("Executed \\(ok + failed + skipped) tests: \\(ok) ok, \\(failed) failed, \\(skipped) skipped"); exit(failed == 0 ? 0 : 1)')
print('\n'.join(o))
