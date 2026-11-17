# Handoff MT-7
By claude@Kevins-MacBook-Air at 2026-11-17T11:45:45 · branch lean/MT-7 · status before: active

## Next step
Paused by user. Built (opus-medium); arch PASS; round-1 fix done; round-1 review FAIL (see .lean/tasks/MT-7/verdict.md: Team tracking on + Codex active profile in single mode leaves the current anthropic pair unpolled, breaks R15/spec §7/AC2). Round-2 fix may have started and been stopped: check the diff. Resume: lean-swarm plan .lean/plans/multi-team-packets.md, gemini:false, tasks [{id:MT-7,size:M,risk:high,importance:high,resume:fix,round:2,kind:fix}, {id:MT-9,size:S,importance:low,after:[MT-7]}]. MT-6 merged at 4ffa469.

## Done so far
Round 1 fixes the three Must-fix findings in verdict.md.
1. A Codex active profile stays shown and on today's path while Team tracking runs.
2. The single-mode popover now views `menuBarProfile` and never shows the active profile's console data under another account.
3. Console billing (and the single-mode status fetch) runs as before for profiles whose claude.ai usage the tracker skips.

## Last review
FAIL. The hunter's major finding reproduces. With Team tracking on and a Codex active profile in single mode, nothing polls the current anthropic pair, so it gets no live samples and loses to any small riser. This breaks R15, spec §7 ("Current pair: 30 s, existing loop"), the packet Goal, and AC2 for this case.

## Junior sessions (machine Kevins-MacBook-Air; reusable only there)
- none

## Resume
`lean resume MT-7` from any agent or account, then `lean work MT-7`:
a new junior reads this file, walkthrough.md and verdict.md first.
