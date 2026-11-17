## Verdict
PASS: all four fixes are correct and kept small, every acceptance criterion has a passing test that would fail without the fix, and the gates are green when rerun (STRICT).

## How it's going
Grade A. Each fix sits in the function the packet names and reuses existing paths (the `liveTarget` conditions, `listObservation`, `apply`).
The tests are specific and check boundaries, and the tester added mutation-guard tests: a `max(...)` cutoff, a negative-infinity timeout, and the call-time clock.

## Done well
- `makeCurrent` uses the same guard as `liveTarget()`. `now` is read once, before the guard, and a refused pick writes nothing.
- The 401 branch in `runGroupMove` calls `apply(..., withholding: [], allowGroup: false)` with no `peerConfirmedRemovals`. The Cloudflare and 429 paths still return nil from `listObservation`, so they stay `.unchecked` as before.
- The OAuth cutoff `lastSampleAt ?? now - roundInterval` matches the packet. Tests cover the boundary (an equal reading is rejected, one 1 s later is accepted) and the case where a prior sample exists.
- BoundedTaskRunner: `isFinite` plus a clamp to 86,400 s. Tests cover `.infinity`, `.nan`, `-.infinity`, 1e300 and -5.
- The test files only add tests (+265/-0 and +44/-0). No skips, xfails or ignores were added.

## Must fix
(none)

## Tests to add
(none)

## Hunter
No findings were reported.

## Arch review
PASS, with no Must fix lines. Every note checks out against the code.

## Evidence (rerun by reviewer, STRICT)
- `bash scripts/validate-clt.sh`: exit 0, "Executed 619 tests: 617 ok, 0 failed, 2 skipped". The 2 skips are the existing keychain skips. All 17 new FU-1 tests are listed as ok.
- `git diff --check`: exit 0.

## Improve later
- `Claude UsageTests/Fixtures/TeamTrackerFakes.swift` was changed but is not in the packet's file list. The change is test-only and justified: the `setOAuth` `lastUpdated` default is needed because test clocks run ahead of the wall clock. Future packets should list the fixtures they expect to change.
- The walkthrough's test count (612) is older than the tester's final count (619). The handover wording is stale and does not block.
- The UI's `canMakeCurrent` (TeamsSectionView) may still offer pairs that `makeCurrent` now refuses. A follow-up could align the UI with the new guard.
