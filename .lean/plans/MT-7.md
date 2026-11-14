### MT-7 — Popover "Teams — most room left" list, recent events, history org picker

Size: M
Risk: normal
Importance: normal
After: MT-1

**Goal:** Show every (account, org) pair in one list sorted by headroom (R9), the last team events,
"Log in again" rows (R8), and let the history view pick the org. UI reads only `Profile.orgTracking`
(MT-1 data), so it runs in parallel with MT-2…MT-6. Spec: `docs/specs/multi-team-tracking.md` §8.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/RoomLeftRanking.swift`
- NEW `Claude Usage/MenuBar/TeamsSectionView.swift`
- `Claude Usage/MenuBar/PopoverContentView.swift` (1876 lines; only `PopoverContentView.body`, insert after the `ContextualInsights` block at :262-266)
- `Claude Usage/Views/Settings/Profile/UsageHistoryView.swift` (`loadHistory` :176-183 and the reset/export calls :186+)
- `Claude Usage/Resources/*.lproj/Localizable.strings` (every language folder; MT-1 already added event keys — add only UI keys)
- NEW `Claude UsageTests/RoomLeftRankingTests.swift`

Do not touch `MenuBarManager.swift`, `NotificationManager.swift` or `AnthropicUsageProvider.swift` (MT-6 owns them).

**Steps**
1. `RoomLeftRanking` (pure, `now` injected):
   ```swift
   struct RoomLeftRow: Identifiable, Equatable { let id: String; let profileId: UUID; let profileName: String
     let orgId: String; let orgName: String; let isActive: Bool; let sessionLeft: Double?; let weeklyLeft: Double?
     let headroom: Double?; let lastSampleAt: Date?; let state: State
     enum State: Equatable { case ok, stale, needsLogin } }
   static func rows(profiles: [Profile], now: Date) -> [RoomLeftRow]
   static func recentEvents(profiles: [Profile], limit: Int = 5) -> [(profileName: String, event: OrgEvent)]
   ```
   - Only anthropic profiles with `orgTracking`; skip `.removed` pairs; skip pairs with no `lastUsage`
     unless the account is `needsLogin`.
   - `sessionLeft` = 100 − session % when `hasSessionLimit`, 100 when its reset time ≤ now, nil without a 5-hour window.
     `weeklyLeft` likewise from weekly (100 when its reset ≤ now). Clamp to 0…100.
   - `headroom` = min(sessionLeft, weeklyLeft), or weeklyLeft when sessionLeft is nil.
   - `state`: account `needsLogin` → `.needsLogin` (numbers nil); `lastSampleAt` older than 30 min → `.stale`; else `.ok`.
   - Order: `.ok` rows by headroom desc, then weeklyLeft desc, then "profile · org" name asc; then `.stale`
     (same order); then `.needsLogin` by name.
   - `recentEvents`: merge all profiles' `recentEvents`, newest first, limit.
2. `TeamsSectionView(profiles: [Profile])`: header "Teams — most room left"; rows: "<profile> · <org>",
   "5h <n>% left" (omit when nil), "Week <n>% left", a dot for `isActive`, "<n> min ago" for `.stale`,
   "Log in again" text (key `multiteam.login_again` from MT-1) in place of numbers for `.needsLogin`.
   Below: up to 5 events (title + relative time with `RelativeDateTimeFormatter`). Match the popover's
   existing fonts/colors (`UsageRow`, `ContextualInsights` style); width fits the 280 pt popover.
3. `PopoverContentView.body`: after the insights block, show `PopoverDivider()` + `TeamsSectionView(profiles: profileManager.profiles)`
   when ranking returns ≥ 2 rows or any `.needsLogin` row. Collapsible with a chevron, expanded by default,
   state in `@AppStorage("popover.teamsExpanded")`.
4. `UsageHistoryView`: when the active profile has `orgTracking` with more than one pair having a
   `historyKey` (including `.removed`, labelled "(removed)"), show a `Picker` of orgs; default the
   active pair. Load and reset/export through the `forKey:` API with the selected pair's `historyKey`.
   With one pair or no `orgTracking`, behave exactly as today (UUID API).
5. Localize every new string with keys `multiteam.ui.*` in all `.lproj` files (English value everywhere except `en` may be the same).
6. Tests, then Validate.

**Acceptance criteria**
1. Pairs (5h 20 % used, week 50 % used) and (5h 70 % used, week 10 % used) → order: first (headroom 50) before second (headroom 30).
2. Equal headroom → higher weeklyLeft first; still equal → name ascending.
3. Weekly-only plan (no 5-hour window), week 40 % used → `sessionLeft == nil`, headroom 60.
4. Session reset time in the past → sessionLeft 100.
5. Pair sampled 31 min ago → `.stale`, listed after all `.ok` rows.
6. Account `needsLogin` → its rows `.needsLogin`, numbers nil, listed last.
7. `.removed` pair → not listed; codex profile → not listed; profile without `orgTracking` → not listed.
8. `recentEvents` over two profiles → newest first, at most 5.
9. Popover with 1 pair and no `needsLogin` → no Teams section (code path check in walkthrough).
10. `UsageHistoryView` with one pair → still calls the UUID API (unchanged behaviour).
11. A SwiftUI smoke test hosts `TeamsSectionView` in an `NSHostingView` with 3 rows and 2 events and lays it out without crashing.
12. Full suite passes.

**Tests:** `RoomLeftRankingTests` for lines 1–8 and 11 (build `Profile` values in code with `orgTracking`
set; fixed `now`). Edge cases: usage over 100 % (clamped to 0 left), empty profiles array, a pair with
`lastUsage == nil` and account `.ok` (skipped).

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`
