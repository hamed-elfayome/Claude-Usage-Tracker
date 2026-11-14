### MT-8 — Teams UI: Teams section view, history org picker, tracking toggle, Google sign-in hint

Size: M
Risk: normal
Importance: normal
After: MT-3

**Goal:** Build the user-facing pieces as self-contained views fed by MT-3's pure `TeamRows` / `PairView`:
the popover "Teams" section (current + saved rows, projected marks, Make current, delete old team with a
confirm dialog, recent events), the history view's org picker, the Team tracking toggle (spec §11) and the
Google sign-in hint (§8, R14). The popover insertion and the tracker callbacks are wired in MT-7, so this
packet runs alongside MT-2/MT-4/MT-5/MT-6. Spec `docs/specs/multi-team-tracking.md` §5, §8, §11.

**Files**
- NEW `Claude Usage/MenuBar/TeamsSectionView.swift`
- `Claude Usage/Views/Settings/Profile/UsageHistoryView.swift` (`loadHistory` :176-183, export :185+ and any reset call)
- `Claude Usage/Views/Settings/App/ManageProfilesView.swift` (633 lines; add one toggle near the existing `SettingToggle`s :55-170)
- `Claude Usage/Views/Settings/Credentials/PersonalUsageView.swift` (783 lines; only the sign-in block :258-275)
- `Claude Usage/Resources/*.lproj/Localizable.strings` (all 15 folders; new `multiteam.ui.*` keys only)
- NEW `Claude UsageTests/TeamsSectionViewTests.swift`
- Read only: `MultiTeam/TeamRows.swift`, `PairView.swift`, `TeamTrackingModels.swift`, `TeamTrackingStore.swift`,
  `MenuBar/PopoverContentView.swift` (style of `ContextualInsights` and `UsageRow` only).

Do not edit `PopoverContentView.swift`, `MenuBarManager.swift`, `NotificationManager.swift` or any `MultiTeam/*.swift` file.

**Steps**
1. `TeamsSectionView(rows: [TeamRow], events: [TeamEvent], now: Date, onMakeCurrent: (PairRef) -> Void, onDelete: (PairRef) -> Void)`:
   - Header "Teams" with a chevron; expanded state in `@AppStorage("popover.teamsExpanded")`, default true.
   - Row: "<profile> · <team>"; a "Now" badge when `isCurrent`; "5h n% left" (omit when nil) and "Week n% left";
     a small "projected" caption after a projected window; "n min ago" when `lastSampleAt` is older than 15 min.
     `.needsLogin` → "Log in again" (`multiteam.login_again`) instead of numbers; `.notSignedIn` → "Not signed in".
     `.old`/`.unreachable` → dimmed, "Old team · deleted in N days" (`.old`) or "Old team" (`.unreachable`) and a
     Delete button.
   - Context menu and a trailing menu button on `.ok` non-current rows: "Make current" → `onMakeCurrent(row.pair)`.
   - Delete → `.confirmationDialog` "Delete old team <team> for <profile>? Its history is removed." with
     Delete (destructive) / Cancel; only Delete calls `onDelete`.
   - Below rows: up to 5 events (title + `RelativeDateTimeFormatter` relative to `now`).
   - Fonts/colours like `ContextualInsights`/`UsageRow`; fits the 280 pt popover width.
2. `UsageHistoryView`: when the profile has `orgTracking` with > 1 pair (any status, each has a `historyKey`), show
   a `Picker` (team names; `.old` labelled "(old)"), default = the profile's followed org (`organizationId`) pair,
   else the first. Load, export and reset through the `forKey:` API with the selected `historyKey`. With ≤ 1 pair
   or no `orgTracking`: exactly today's UUID calls.
3. `ManageProfilesView`: a `SettingToggle` "Team tracking (follow the account in use)" with a one-line description
   ("Detects which account and team you are using from rising usage; other teams are checked every 5 minutes."),
   bound to `@AppStorage(TeamTrackingSettings.enabledKey)`.
4. `PersonalUsageView`: under the "Sign in to Claude.ai" button, a secondary caption (key
   `multiteam.ui.google_hint`): "Google sign-in blocked? Sign in at claude.ai in your browser and paste the
   session key below, or use the Claude Code login. In the Google window, pick the right account." No logic change.
5. Every new string as `multiteam.ui.*` in all 15 `Localizable.strings` (English value everywhere).
6. Tests, then Validate.

**Acceptance criteria**
1. `TeamsSectionView` with 3 rows (current, saved projected, old) and 2 events hosts in an `NSHostingView` (width 280) and lays out without crashing.
2. Same with 0 events and a `.needsLogin` row → no crash.
3. `onMakeCurrent` is not offered for the current row nor for `.old`/`.needsLogin` rows (expose a pure `static func canMakeCurrent(_ row: TeamRow) -> Bool` and test it).
4. Delete is offered only for `.old`/`.unreachable` (`static func canDelete(_:) -> Bool`, tested).
5. Pure `static func historyChoices(for profile: Profile) -> [(key: String, label: String)]`: 2 pairs → 2 choices, old one labelled "(old)"; 1 pair → empty (picker hidden); no `orgTracking` → empty.
6. Default history choice = followed org pair (test through a pure helper).
7. The toggle writes `multiTeam.enabled` (code reading in the walkthrough: `@AppStorage(TeamTrackingSettings.enabledKey)`).
8. The Google hint key exists in all 15 `Localizable.strings` (test: load each `.lproj` bundle path's strings file and check the key, or a `grep -c` noted in the walkthrough).
9. No file outside the Files list changed (`git diff --stat` in the walkthrough).
10. Full suite passes.

**Tests:** `TeamsSectionViewTests` for lines 1–6 with `TeamRow` values built by hand (fixed `now`). Edge cases: very
long profile and team names (layout still within width; check no crash), a row with `view.headroom == nil`.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`
