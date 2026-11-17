## Verdict
PASS. One shared main-actor `LivePollGate` on all three tracker live-fetch sites. Every path that takes the gate is released by a `defer`. The tracker-off, legacy and codex paths are untouched.

## Must fix
(none)

## Notes
- Release invariant checked against `multiFetchPlan` (MenuBarManager.swift ~228-239). `liveOrgIds` holds only the current account. That account is always `profiles[0]`, and the `usageSkip` filter excludes it. So the loop `defer` (~1275) is always reached when the gate was taken. Nothing between `begin()` (~1243) and the loop can return early, and the status fetch is caught. The gate cannot get stuck. If `multiFetchPlan` is ever changed so the current account can land in `usageSkip`, or so that it is no longer first, this breaks silently. Keep that invariant if the plan changes.
- Single mode `.tracked` (~1516): no early return between `begin()` and the Task, and `skipsUsage == false` guarantees the `if !skipsUsage` defer (~1568) runs. `.legacy` returns before any `begin()`.
- Background site: the `inout` gate access ends before the Task's `release` closure can run, so there is no exclusivity conflict. The Task inherits MainActor because the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (pbxproj 546/608).
- Accepted shortcut: resetting on toggle-off lets a stale `end()` clear a newer holder, which allows at most one duplicate. It is documented as `ponytail`. The upgrade is a generation token. The reset is not needed for liveness, because the defers always release.
- Inherent to the spec: when `onCurrentChanged` fires during an in-flight fetch of the old pair, the new pair is skipped until the next 30 s tick. A per-pair gate would fix that if it ever matters.
- Only the background site goes through the `startGatedLivePoll` test seam. The two inline sites and the reset are verified by reading only, which the packet allows for code that cannot be driven without a status bar.
