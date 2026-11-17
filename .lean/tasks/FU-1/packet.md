<!-- source: .lean/plans/multi-team-followups.md lines 1-56 -->
### FU-1 — TeamTracker failure-mode hardening

Size: M
Risk: high
Importance: high

Repo `/Users/kuke/Coding/Claude-Usage-Tracker`, branch `feat/multi-team-tracking`. Spec: `docs/specs/multi-team-tracking.md`.

**Goal:** close four tracker failure modes found in the architecture review: a peer's 401 list dropped
during a group move, `makeCurrent` accepting a pair that can never be live, an OAuth-only cached reading
accepted as a first sample, and a non-finite runner timeout that traps.

**Files:**
- `Claude Usage/Shared/MultiTeam/TeamTracker.swift` (over 300 lines: change only `makeCurrent`, `runGroupMove`, and the OAuth sample check inside `runRound`)
- `Claude Usage/Shared/MultiTeam/BoundedTaskRunner.swift` (the `if let timeout` timer block)
- `Claude UsageTests/TeamTrackerTests.swift` (add tests; reuse `Fixtures/TeamTrackerFakes.swift` and `Fixtures/TeamFixtures.swift`)
- `Claude UsageTests/BoundedTaskRunnerTests.swift` (add tests)

**Steps:**
1. `makeCurrent(_:)`: extend the guard so the target org has `status == .member` and the profile's
   `orgTracking.authState == .ok`, and the account is not backing off (`scheduler.isBackingOff(id, now:)`).
   Otherwise return without changes (no event, no `manualPickAt`). Same conditions `liveTarget()` uses.
2. `runGroupMove(_:now:gen:)`: in the results loop, before the `!(obs.orgList ?? []).isEmpty` guard, handle
   the auth-failure case: if `listObservation` returned an obs with `orgListAuthFailed == true`, call
   `apply(obs, profileId: id, source: .list, withholding: [], allowGroup: false)` (do NOT set
   `peerConfirmedRemovals`), then set `outcomes[id] = .unchecked` and continue. All other paths stay as they are.
3. `runRound`: the line `if item.sessionKey == nil, let last = item.lastSampleAt, usage.lastUpdated <= last { continue }`
   must also reject cached readings when `lastSampleAt` is nil. Decision: for `item.sessionKey == nil`,
   reject the reading when `usage.lastUpdated <= (item.lastSampleAt ?? now.addingTimeInterval(-policy.round))`,
   where `now` is the round's `now` parameter. Keep the same `continue` (no `scheduler.record`), as today.
4. `BoundedTaskRunner.run`: start the timer only when `timeout` is non-nil AND `isFinite`; clamp it to
   `min(max(0, t), 86_400)` before converting to nanoseconds. A non-finite or NaN timeout means no timer
   (same as nil). Do not change any other behaviour.
5. Do not touch any other function, file or public signature.

**Acceptance criteria:**
1. `makeCurrent` on an `.old` pair -> `global.current` unchanged, `manualPickAt` unchanged, no event.
2. `makeCurrent` on an `.unreachable` pair -> unchanged as in 1.
3. `makeCurrent` on a `.member` pair of an account with `authState == .needsLogin` -> unchanged.
4. `makeCurrent` on a `.member` pair of an account in 429 backoff -> unchanged.
5. `makeCurrent` on a healthy `.member` non-current pair -> current moves (existing behaviour kept; existing tests still pass).
6. Group move where one peer's forced list fails with non-Cloudflare `apiUnauthorized` -> that peer's `orgTracking` shows the rule-L effect of `orgListAuthFailed` (same state as the same failure would cause in `runDueLists`), and the group event counts it as unchecked.
7. Group move where a peer's list fails with a Cloudflare challenge -> peer unchecked, its state unchanged (as today).
8. OAuth-only pair with `lastSampleAt == nil`, provider returns usage with `lastUpdated` older than `now - policy.round` -> no sample: `claudeUsage` not written, `onSample` not fired.
9. Same as 8 but `lastUpdated == now` -> accepted as a sample (as today).
10. `BoundedTaskRunner.run(..., timeout: .infinity)` -> returns all results, no trap.
11. `BoundedTaskRunner.run(..., timeout: .nan)` -> returns all results, no trap.
12. Full CLT suite green; no existing test changed except to add new ones.

**Tests:** one test per AC 1-4, 6-11 in the two test files named above. For AC6 build a tracker with
two accounts sharing org A, make the trigger confirm removal of A, and make the fake fetcher return
`AppError` `apiUnauthorized` for the peer's `fetchOrganizations`. Mutation-check AC6 and AC8: revert the
fix locally, confirm the test fails, restore. Edge: AC6 with the peer also in backoff -> unchecked, no apply.

**Validate:** `bash scripts/validate-clt.sh` `git diff --check`
