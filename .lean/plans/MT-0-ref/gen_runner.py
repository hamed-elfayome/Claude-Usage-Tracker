import re,sys
files=sys.argv[1:]; tests=[]
for f in files:
    cls=None
    for ln in open(f,encoding='utf-8'):
        m=re.match(r'(?:@MainActor\s+)?(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b',ln)
        if m: cls=m.group(1); continue
        if re.match(r'(?:final\s+)?(?:class|struct|enum|extension|actor)\s',ln) : cls=None
        m=re.match(r'\s+(?:@MainActor\s+)?func\s+(test\w*)\(\)\s*(async)?\s*(throws)?',ln)
        if m and cls: tests.append((cls,m.group(1),bool(m.group(2)),bool(m.group(3))))
o=['import Foundation','import XCTest','@testable import Claude_Usage','var ok=0, failed=0, skipped=0',
'func run(_ name: String, _ body: () async throws -> Void) async { let b=xctFailures; var skip=false; do { try await body() } catch let e as XCTSkip { skip=true; _ = e } catch { xctFailures += 1; print("    FAIL threw \\(error)") }',
'  if skip { skipped+=1; print("SKIP \\(name)") } else if xctFailures==b { ok+=1; print("ok   \\(name)") } else { failed+=1; print("FAIL \\(name)") } }']
for c,m,a,t in sorted(tests):
    call=("try " if t else "")+("await " if a else "")+f"t.{m}()"
    o.append(f'await run("{c}.{m}") {{ let t={c}(); try await t.setUp(); try _xctSyncSetUp(t); var err: Error? = nil; do {{ {call} }} catch {{ err = error }}; try _xctSyncTearDown(t); try await t.tearDown(); if let err {{ throw err }} }}')
o.append('print("Executed \\(ok+failed+skipped) tests: \\(ok) ok, \\(failed) failed, \\(skipped) skipped"); exit(failed==0 ? 0 : 1)')
print('\n'.join(o))
