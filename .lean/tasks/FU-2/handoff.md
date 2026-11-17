# Handoff FU-2
By claude@Kevins-MacBook-Air at 2026-11-17T16:28:19 · branch lean/FU-2 · status before: active

## Next step
Paused by user mid fix r1 (opus-max). Review r0 FAIL grade C: the bool gate drops refreshUsage() for a NEW current pair while the old pair's fetch is in flight, so the old reading lands under the new menuBarProfile (verdict.md, Must fix, MenuBarManager.swift ~1565-1640). Worktree wt/FU-2 has uncommitted partial fix edits in MenuBarManager.swift and MenuBarTeamWiringEdgeTests.swift. Resume: lean-swarm with plan .lean/plans/multi-team-followups.md, gemini:false, task {id:FU-2,size:S,risk:high,resume:fix,round:1,kind:fix}. FU-1, FU-3 merged grade A.

## Done so far
Added `LivePollGate`, which lets only one Team-tracking live fetch of the current pair run at a time, across the three tracker live-fetch sites in `MenuBarManager`.
When a pass finds the gate busy, it skips the usage fetch and keeps the cached value, the same way the existing `.skip` does.
A `defer` in the async body releases the gate after success, failure or cancellation. When tracking is turned off, the gate is reset.

## Last review
FAIL. The hunter's major finding holds when I read the code. While a fetch of the old pair is in flight, the gate drops the refresh for the new current pair. The old fetch then writes its reading into the single-mode `self.usage`, so the menu bar shows the previous account's usage under the new current account until the next timer pass.

## Junior sessions (machine Kevins-MacBook-Air; reusable only there)
- none

## Resume
`lean resume FU-2` from any agent or account, then `lean work FU-2`:
a new junior reads this file, walkthrough.md and verdict.md first.
