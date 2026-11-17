# Multi-team tracking — build plan (v2, follow the account in use)

Spec: `docs/specs/multi-team-tracking.md` v2 (read §1–§4 and the sections your packet names before coding).
Requirements: `docs/specs/multi-team-requirements.md` (the "Owner revision" overrides R1, R3, R7, R9).
Branch: `feat/multi-team-tracking`. Packets: `.lean/plans/MT-<n>.md` (one file each; the packet file is the contract).

v2 replaces v1 entirely: v1's live tracking of every pair, Claude Code owner-switch detection, scheduler actor and
"most room left" view are gone. All packet files were rewritten; MT-9 is new.

| Packet | Title | Size | Risk | Importance | After |
|---|---|---|---|---|---|
| MT-0 | Xcode-free validation harness `scripts/validate-clt.sh` | M | normal | high | — |
| MT-1 | Data model, stores, migration, pair-keyed history, shared fixtures | M | high | high | MT-0 |
| MT-2 | Per-account event rules + credential-org parser (pure) | M | normal | high | MT-1 |
| MT-3 | Current detection, projection, group-move event, Teams rows (pure) | M | normal | high | MT-1 |
| MT-4 | API signals: tier fields, 404/429 + Retry-After, usage-only fetch | S | normal | normal | MT-0 |
| MT-5 | Poll scheduler + bounded task runner (**merged**) | M | high | normal | — |
| MT-6 | TeamTracker coordinator + adapters | L | high | high | MT-2, MT-3, MT-4, MT-5 |
| MT-7 | Wire tracker into loop, popover, provider, notifications | M | high | high | MT-6, MT-8 |
| MT-8 | Teams UI, history picker, toggle, Google sign-in hint | M | normal | normal | MT-3 |
| MT-9 | User docs and changelog | S | normal | low | MT-7 |

Critical path: MT-0 → MT-1 → MT-2 → MT-6 → MT-7 → MT-9. No packet edits `project.pbxproj` (file-system synchronized
groups). Every packet's Validate is the full test suite plus `git diff --check`:
`scripts/validate-clt.sh` `git diff --check`

Why (14 Nov 2026): this Mac has only Command Line Tools, so `xcodebuild test` cannot run and no gate could pass.
MT-0 adds `scripts/validate-clt.sh`: when full Xcode is present it runs the real
`xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" …` (previous Validate); otherwise it
compiles the whole app module with swiftc (stub DynamicNotchKit/Sparkle modules, `@State`/`#Preview` macro
workaround) and runs every XCTestCase test against a small XCTest shim module.
**Coverage limit:** without Xcode the widget extension, the asset catalog and other resources, Info.plist
processing, code signing and the real DynamicNotchKit/Sparkle APIs are NOT built or checked, and `#Preview`
bodies are not compiled. One full `xcodebuild` build+test run on a Mac with Xcode is required before the
release that ships this feature.
MT-1 and MT-4 (built, fixed, awaiting retest) wait for MT-0; their worktree packet copies run the harness as
`bash /Users/kuke/Coding/Claude-Usage-Tracker/scripts/validate-clt.sh --root .`, which needs MT-0 merged into
`feat/multi-team-tracking` at the main checkout (or merge feat into their branches first).

File ownership while lanes overlap (no two parallel packets edit the same file):
- MT-0: `scripts/validate-clt.sh`, `scripts/clt/**`, `CONTRIBUTING.md` (no app or test sources).
- MT-1: `Profile.swift`, `ProfileManager.swift`, `UsageHistoryService.swift`, `Localizable.strings` (first), `MultiTeam/TeamTracking*.swift`, `Fixtures/TeamFixtures.swift`.
- MT-4: `ClaudeAPIService.swift`, `ClaudeAPIService+Types.swift`, `MultiTeam/AppError+MultiTeam.swift`.
- MT-5: `MultiTeam/TeamPollScheduler.swift`, `MultiTeam/BoundedTaskRunner.swift`.
- MT-2: `MultiTeam/AccountRules.swift`, `MultiTeam/CredentialOrgParser.swift`.
- MT-3: `MultiTeam/CurrentPairDetector.swift`, `PairView.swift`, `GroupMoveAggregator.swift`, `TeamRows.swift`.
- MT-8: `MenuBar/TeamsSectionView.swift`, `UsageHistoryView.swift`, `ManageProfilesView.swift`, `PersonalUsageView.swift`, `Localizable.strings` (second; MT-1 is merged by then).
- MT-6: `MultiTeam/TeamTracker.swift`, `MultiTeam/TeamTrackerAdapters.swift`.
- MT-7 (sequential, last code packet): `MenuBarManager.swift`, `PopoverContentView.swift`, `AnthropicUsageProvider.swift`, `NotificationManager.swift`.
- Each packet adds only its own new test files.

## Lanes

| Lane | Tasks | Runs alongside | Saves (min) |
|---|---|---|---|
| A (critical path) | MT-0 → MT-1 → MT-2 → MT-6 → MT-7 → MT-9 | — | 0 |
| B | MT-3 → MT-8 (after MT-1) | MT-2, then MT-6 | ~75 |
| C | MT-4 (after MT-0; retest only) | MT-1 retest | ~20 |
| D | MT-5 | — (merged) | — |

MT-5 is merged and left out of the TASKS line; MT-6's dependency on it is already met.

TASKS: [{"id":"MT-0","size":"M","risk":"normal","importance":"high","after":[]},{"id":"MT-1","size":"M","risk":"high","importance":"high","after":["MT-0"]},{"id":"MT-2","size":"M","risk":"normal","importance":"high","after":["MT-1"]},{"id":"MT-3","size":"M","risk":"normal","importance":"high","after":["MT-1"]},{"id":"MT-4","size":"S","risk":"normal","importance":"normal","after":["MT-0"]},{"id":"MT-6","size":"L","risk":"high","importance":"high","after":["MT-2","MT-3","MT-4"]},{"id":"MT-7","size":"M","risk":"high","importance":"high","after":["MT-6","MT-8"]},{"id":"MT-8","size":"M","risk":"normal","importance":"normal","after":["MT-3"]},{"id":"MT-9","size":"S","risk":"normal","importance":"low","after":["MT-7"]}]
