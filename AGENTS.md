<!-- lean-system:begin -->
## Shared project memory (`lean`), for every AI agent

Claude (any subscription), Gemini, Codex and any other agent share work on this
repo through `.lean/` and the `lean` command. If you are a BUILDER or TESTER
junior started by a dispatcher, skip this section.
- Session start: `lean brief` (goals, who holds which task, lessons, history).
- Before changing code for a task: `lean claim <TASK>`, then work in the
  worktree it prints (branch `lean/<TASK>`). Never touch a task another agent holds.
- Stopping early: `lean handoff <TASK> --next "exact next step"`. Continuing
  someone's task: `lean resume <TASK>`.
- Done and checked: `lean merge <TASK> --msg "<TASK>: summary"` (or `lean pass`,
  and let `lean integrate` combine it).
- New gotcha: `lean lesson "…" --task <TASK>`. Follow `.lean/lessons.md`.
<!-- lean-system:end -->
