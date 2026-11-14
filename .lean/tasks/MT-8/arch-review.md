## Verdict
PASS: self-contained views over MT-3's TeamRow/PairView, pure static helpers for every decision, history I/O through the existing forKey: API; every acceptance criterion is reachable.

## Must fix
(none)

## Notes
- Data flow is right: TeamsSectionView takes values and callbacks only (no tracker or store access), so MT-7 owns wiring. The confirm dialog gates onDelete. canMakeCurrent/canDelete drive both the UI and the tests, so there is one source of truth.
- History continuity holds: the migration gives the first pair historyKey = profile.id.uuidString, so the forKey: path and the legacy UUID path read the same store for the followed org. With <= 1 pair, activeHistoryKey returns nil and the exact old calls run (step 2).
- Small coupling: historyChoices/defaultHistoryKey live on TeamsSectionView (a popover view) but the Settings history view uses them. The packet asked for this. They could move to a MultiTeam helper later. Not a defect.
- A profile change sets selectedHistoryKey = nil and then calls loadHistory, and the onChange of selectedHistoryKey can trigger a second load. Both loads are synchronous and idempotent, so this is harmless.
- pendingDelete holds a row snapshot. If rows refresh while the dialog is open, onDelete still gets the right PairRef, because it is a stable identity.
- The view sets frame(width: 280) itself, with padding inside it. MT-7 must not add more horizontal padding when it inserts the view.
- The history picker selection is not persisted across launches (walkthrough). This is acceptable for this packet.
