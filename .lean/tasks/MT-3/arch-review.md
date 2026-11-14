## Verdict
PASS. Both round-1 must-fix items are done. The group-move title now counts movers only, which meets AC12/AC13, and the rest of the design is unchanged and sound.

## Must fix
(none)

## Notes
- TeamTrackingModels.swift:123 `count = moves.count`: the one-line approved change outside the Files list. TeamTrackingModelsTests:119 ("1 accounts moved") is still consistent with it.
- GroupMoveAggregatorTests now asserts "2 accounts moved: A → B" (AC12) and "2 accounts removed from A" (AC13, trigger plus one peer mover). The wrong-count comment is removed.
- Round-0 notes still apply: callers must pass `latestAt` = the time the sample was taken. On manual-pick rounds `rises` is empty and `readings` is filled. TeamRows status precedence and the nil-headroom sentinel match §11.
