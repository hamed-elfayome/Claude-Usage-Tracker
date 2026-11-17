## Verdict
PASS: all four fixes sit in the right functions, reuse the existing paths (`apply`, the `liveTarget` conditions, `listObservation`), and can meet every acceptance criterion.

## Must fix
(none)

## Notes
- `makeCurrent` (TeamTracker.swift:173-179): the guard now matches `liveTarget()` field for field (authState `.ok`, org `.member`, not backing off). `now` is read once and used for both the backoff check and `manualPickAt`. A refused pick writes no state.
- `runGroupMove` (TeamTracker.swift:620-634): the 401 branch calls `apply(..., withholding: [], allowGroup: false)` with no `peerConfirmedRemovals`. That gives the same rule-L state change as `runDueLists` -> `applyAndRun`. The only difference is `allowGroup`, and it does not matter here because a 401 observation has no org list and so no confirmed removals to group. The peer is counted `.unchecked`. The Cloudflare and rate-limit paths still return nil from `listObservation` and stay `.unchecked` with no apply, as before. `apply` is `@discardableResult`, so the bare call is fine.
- `runRound` OAuth check (TeamTracker.swift:382-384): the cutoff uses the round's `now`. In production `ClaudeUsage.lastUpdated` for a fresh fetch is stamped after `now`, so fresh readings pass. A cached reading less than one round old is still accepted as a first sample. The packet chose that window, so it is not a defect.
- BoundedTaskRunner: an `isFinite` check plus a clamp removes the trap. `.infinity` and `.nan` now behave like nil, and nothing else changes.
- Fixture change (TeamTrackerFakes.swift `setOAuth(..., lastUpdated: = .distantFuture)`) falls outside the packet's file list, but it is test-only and justified. Test clocks run ahead of the wall clock, and `ClaudeUsage` stamps `Date()`. The default overrides any `lastUpdated` set on the usage passed in. Only the three callers in TeamTrackerTests use it, so no existing assertion depends on the old stamp.
- No public signature changed, and no other function was touched.
