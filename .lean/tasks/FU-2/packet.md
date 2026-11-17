<!-- source: .lean/plans/multi-team-followups.md lines 57-101 -->
### FU-2 — Single in-flight gate for the menu bar live poll

Size: S
Risk: high
Importance: normal

Repo `/Users/kuke/Coding/Claude-Usage-Tracker`, branch `feat/multi-team-tracking`.

**Goal:** the 30 s timer and `TeamTracker.onCurrentChanged` can both start a live fetch of the current
pair at once. Duplicate requests raise 429 risk, and a 429 backs off the current account, which makes
`liveTarget()` nil and starves the menu bar. Allow one tracker live fetch in flight at a time.

**Files:**
- `Claude Usage/MenuBar/MenuBarManager.swift` (over 300 lines: add the gate type at file end; change only
  the tracker-running live-fetch branch of `refreshUsage()` (around line 1434), the Task started for
  `backgroundLiveTarget`/`pollLiveTarget`, and the multi-mode current-account fetch)
- `Claude UsageTests/MenuBarTeamWiringEdgeTests.swift` (add tests)

**Steps:**
1. Add `struct LivePollGate { private(set) var inFlight = false; mutating func begin() -> Bool; mutating func end() }`
   in `MenuBarManager.swift` (internal, not private, so tests can use it). `begin()` returns false when
   already in flight, else sets `inFlight = true` and returns true. `end()` clears it.
2. Add `private var livePollGate = LivePollGate()` to `MenuBarManager`.
3. In each tracker live-fetch site named in Files: call `begin()` before the request; if it returns
   false, skip the pass and keep the cached value (same as the existing "target does not match" skip).
   Call `end()` in a `defer` inside the async body that awaits the fetch, so success, failure and
   cancellation all release the gate.
4. Do not gate the tracker-off path (today's code) or the codex/legacy paths that do not call `ingestLive`.
5. When the tracker stops (`teamTrackingSettingChanged`, disabled branch), reset the gate to `LivePollGate()`.

**Acceptance criteria:**
1. `LivePollGate`: `begin()` -> true; second `begin()` -> false; after `end()`, `begin()` -> true.
2. Two live passes started back to back while the first fetch is suspended -> the fake fetcher is called once.
3. A live fetch that throws -> the gate is released; the next pass fetches.
4. Tracker off -> `refreshUsage()` behaves as before (existing tests pass unchanged).
5. Turning the toggle off while a fetch is in flight, then on -> the next pass fetches.
6. Full CLT suite green.

**Tests:** unit tests for AC1; for AC2-3 and AC5 follow the patterns already in
`MenuBarTeamWiringEdgeTests.swift` (real tracker, fake fetcher that suspends on a continuation).
If the `refreshUsage()` site cannot be driven without a status bar, test through the same pure helper
(`pollLiveTarget`) the existing tests use and state in the walkthrough which site is covered by reading only.

**Validate:** `bash scripts/validate-clt.sh` `git diff --check`
