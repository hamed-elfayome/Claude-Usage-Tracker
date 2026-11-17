### MT-7 — Wire the tracker into the menu bar loop, popover, token refresh and notifications

Size: M
Risk: high
Importance: high
After: MT-6, MT-8

**Goal:** Make the running app follow the current pair when Team tracking is on: the existing 30 s loop polls
only the current pair and hands every sample to the tracker, the menu bar and popover show the current account
without activating it (no Claude Code credential writes), per-pair history replaces the old reset checks for
anthropic profiles, `invalid_grant` reaches the tracker, team events become notifications, and the Teams section
appears in the popover. With tracking off every code path is exactly today's. Codex profiles never change.
Spec `docs/specs/multi-team-tracking.md` §4 (switch effects), §7, §10, §11.

**Files**
- `Claude Usage/MenuBar/MenuBarManager.swift` (1924 lines; touch only `setup()` :121, `cleanup()` :261, the initial
  usage reads :169 and :360-375, single-mode display :950-960, `refreshAllSelectedProfiles` :1007-1160,
  `refreshUsage` :1201-1418)
- `Claude Usage/MenuBar/PopoverContentView.swift` (viewed-profile fallbacks :130-145 and :206; insert after the insights block :262-266)
- `Claude Usage/Shared/Services/Providers/Anthropic/AnthropicUsageProvider.swift` (the `ensureFreshCredentials` call :54)
- `Claude Usage/Shared/Services/NotificationManager.swift` (add an extension at the end; posting like `sendAutoSwitchNotification` :308)
- NEW `Claude UsageTests/TeamEventNotificationTests.swift`
- Read only: `MultiTeam/TeamTracker.swift`, `TeamRows.swift`, `MenuBar/TeamsSectionView.swift`.

**Steps**
1. `MenuBarManager`:
   - `var menuBarProfile: Profile?` = when `TeamTracker.shared.isRunning`, the profile of `global.current` (if it
     still exists) else `profileManager.activeProfile`; when not running, `profileManager.activeProfile`.
   - `setup()`: `TeamTracker.shared.notifier = NotificationManager.shared`; `onCurrentChanged = { [weak self] _ in
     self?.refreshUsage() }` (also refresh the menu bar display); `onSample = { [weak self] id, usage in … }` writes
     the statusline cache exactly like :1287-1290 but only when `id == activeProfile?.id`; `start()`. Observe
     `UserDefaults.didChangeNotification` and start/stop the tracker when `TeamTrackingSettings.isEnabled()` flips,
     then refresh. `cleanup()`: `stop()`.
2. `refreshUsage` (single mode): `subject = menuBarProfile`. If tracker running and `subject.provider == .anthropic`:
   `guard let target = TeamTracker.shared.liveTarget(), target.profile.id == subject.id` else log, keep cached, return.
   Fetch with `fetchUsageForActiveProfile` when `subject.id == activeProfile?.id`, else
   `ProviderRegistry.service(for:).fetchUsage(for: subject)`. Inside this function replace reads of
   `profileManager.activeProfile` used for the fetched profile, `self.usage` and `saveClaudeUsage` with `subject`;
   keep the statusline block guarded to the active profile; keep auto-switch logic untouched. After success
   `ingestLive(profileId:orgId: target.orgId, result: .success, isCachedReading:)` and skip
   `checkAndRecordSessionReset`, `checkAndRecordWeeklyReset`, the periodic recorders and the `resetJustRecorded`
   bookkeeping; in `catch` `ingestLive(… .failure(error) …)`. Tracker off → today's code unchanged.
3. `refreshAllSelectedProfiles` (multi mode), tracker running: anthropic selected profiles that are not the current
   account → no fetch (render their `claudeUsage`); the current account is fetched even when not selected (not
   rendered); same liveTarget / ingest / skip-history pattern. Non-anthropic and tracker off → unchanged.
4. Single-mode display reads (:169, :360-375, :958) use `menuBarProfile` instead of `activeProfile`.
5. After each pass: if the shown account's `orgTracking?.authState` is `.needsLogin`, set `hasCredentialError = true`
   and `lastRefreshError = AppError(code: .apiUnauthorized, message: "multiteam.login_again".localized, …)`; do not
   clear it in the same pass.
6. `PopoverContentView`: the viewed-profile fallbacks use `manager.menuBarProfile` instead of
   `profileManager.activeProfile` (a click still overrides). After the insights block: when the tracker runs and
   `TeamRows.build(...)` returns ≥ 2 rows → `PopoverDivider()` + `TeamsSectionView(rows:events:now:onMakeCurrent:
   { TeamTracker.shared.makeCurrent($0) }, onDelete: { _ = TeamTracker.shared.deleteOldPair($0) })`. Observe
   `TeamTracker.shared` so rows refresh.
7. `AnthropicUsageProvider.fetchUsage(for:)`: pass `onRefreshRejected:` to `ensureFreshCredentials` that hops to the
   main actor and calls `TeamTracker.shared.reportRefreshRejected(profileId: profile.id)` (the tracker ignores it
   when not running). No other change to the chain.
8. `NotificationManager`: `extension NotificationManager: TeamEventNotifying`; `post(_:profiles:)` returns early unless
   `event.notifies` and at least one involved profile (event's account(s)) has `notificationSettings.enabled`;
   content from pure `static func teamEventContent(_ e: TeamEvent) -> (identifier: String, title: String, body: String)`
   (identifier `team-event-<id>`, title/body from the event); post like `sendAutoSwitchNotification`.
9. Tests, then Validate.

**Acceptance criteria**
1. Tracker off → `git diff` shows every changed branch guarded by `isRunning`/provider checks; existing tests green (walkthrough lists the guards).
2. Tracker on, single mode, current account ≠ active profile → the fetch uses `fetchUsage(for:)` for the current account; `activateProfile` is never called; the active profile's Claude Code credentials are not touched (code reading).
3. `liveTarget()` nil → no network fetch for that account in that pass; cached value stays.
4. Anthropic sample with tracker on → `ingestLive` called; `checkAndRecordSessionReset/WeeklyReset` and periodic recorders not called for it (code reading); Codex profile → old path unchanged.
5. Multi mode with 3 selected anthropic profiles → only the current account is fetched per pass.
6. `teamEventContent` for `adminMove(A→B)` → identifier `team-event-<uuid>`, title "Moved by admin: A → B".
7. `post` with `notifies == false`, or with every involved profile's notifications disabled → nothing posted (test through the early-return helper).
8. `ensureFreshCredentials` in `AnthropicUsageProvider` receives a non-nil `onRefreshRejected`.
9. Shown account `needsLogin` → `hasCredentialError == true`, banner text "Log in again".
10. Popover shows the Teams section only when the tracker runs and ≥ 2 rows exist (code reading).
11. Full suite passes.

**Tests:** `TeamEventNotificationTests` for lines 6–7 and a non-empty title for every `TeamEvent.Kind`. Edge cases:
group event where only one involved profile has notifications on (posted); event naming a deleted profile.

**Validate:** `scripts/validate-clt.sh` (runs `xcodebuild test` automatically when full Xcode is present) `git diff --check`

**Coverage limit:** without Xcode the harness does not build the widget extension, the asset catalog or other resources, and compiles DynamicNotchKit/Sparkle against stubs; one full `xcodebuild` build+test run is required at release time (see `multi-team.md`).
