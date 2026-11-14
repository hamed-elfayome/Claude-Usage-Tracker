### MT-6 — Wire the coordinator into the menu bar loop, token refresh and notifications

Size: M
Risk: high
Importance: high
After: MT-5

**Goal:** Make the running app use the coordinator: the existing 30 s loop stays the active-pair poller
but asks the coordinator before fetching and hands every anthropic sample to it; per-pair history and
events replace the old reset checks for anthropic profiles; `invalid_grant` reaches the coordinator;
events become macOS notifications; a dead login shows "Log in again". Codex profiles keep today's path.
Spec: `docs/specs/multi-team-tracking.md` §6, §7, §8.

**Files**
- `Claude Usage/MenuBar/MenuBarManager.swift` (1924 lines; touch only `setup()` :121, `cleanup()` :261,
  `cleanupProfile` :316, `observeProfileChanges` :326, `refreshAllSelectedProfiles` :1007-1160,
  `refreshUsage` :1201-1418)
- `Claude Usage/Shared/Services/Providers/Anthropic/AnthropicUsageProvider.swift` (:49-60)
- `Claude Usage/Shared/Services/NotificationManager.swift` (add an extension at the end)
- NEW `Claude UsageTests/OrgEventNotificationTests.swift`
- Read only: `MultiTeamCoordinator.swift`, `OrgTrackingModels.swift`.

**Steps**
1. `setup()`: `MultiTeamCoordinator.shared.notifier = NotificationManager.shared`;
   `onActiveOrgChanged = { [weak self] _ in self?.refreshUsage() }`; `start()`. `cleanup()`: `stop()`.
2. `refreshAllSelectedProfiles`: before the loop call `setLoopProfiles(Set(selectedProfiles.map(\.id)))`.
   For a profile with `provider == .anthropic`: `guard let ticket = coordinator.beginActivePoll(for: profile)`
   else log and `continue` (cached value stays on screen). After a successful fetch, in the existing
   `MainActor.run`: call `coordinator.ingestActive(ticket, result: .success(newUsage), isCachedReading:)`
   and skip `checkAndRecordSessionReset`, `checkAndRecordWeeklyReset`, `recordSessionPeriodic`,
   `recordWeeklyPeriodic` and the `resetJustRecorded` bookkeeping for that profile; keep
   `saveClaudeUsage`, active-profile `self.usage`, and the statusline cache exactly as today. In `catch`,
   call `ingestActive(ticket, result: .failure(error), isCachedReading: false)`.
   Non-anthropic profiles: unchanged code path.
3. `refreshUsage` (single mode): `setLoopProfiles([profile.id])`; the same ticket / ingest / skip pattern
   for the anthropic case around `fetchUsageForActiveProfile`.
4. After each refresh pass, if the active profile's `orgTracking?.authState` is `.needsLogin`, set
   `hasCredentialError = true` and `lastRefreshError` to an `AppError(code: .apiUnauthorized,
   message: "multiteam.login_again".localized, …)` so the existing banner shows; do not reset it to
   false in the same pass. Otherwise keep today's handling.
5. `cleanupProfile` and the profiles-changed observer: call `MultiTeamCoordinator.shared.syncJobs()`.
6. `AnthropicUsageProvider.fetchUsage(for:)`: pass `onRefreshRejected:` to `ensureFreshCredentials`
   that hops to the main actor and calls `MultiTeamCoordinator.shared.reportRefreshRejected(profileId: profile.id)`.
   No other change to the priority chain.
7. `NotificationManager`: `extension NotificationManager: OrgEventNotifying` with
   `notify(_ event:, profile:)` → skip unless `profile.notificationSettings.enabled` and `event.notifies`;
   build content with a pure `static func orgEventContent(_ event: OrgEvent, profileName: String) -> (identifier: String, title: String, body: String)`
   (identifier `org-event-<event.id>`, title = event title, body = "<profileName>: <event body>") and post
   it the same way `sendAutoSwitchNotification` (:308) does.
8. Tests, then Validate. Then launch-free check: build succeeds and the full suite is green.

**Acceptance criteria**
1. Anthropic profile in multi mode → `beginActivePoll` called before fetch; `ingestActive` called after; no call to `checkAndRecordSessionReset`/`checkAndRecordWeeklyReset`/periodic recorders for it (verified by code reading in the walkthrough).
2. Codex profile → old reset checks and periodic recording still run (unchanged lines).
3. `beginActivePoll` returns nil → no network fetch for that profile in that pass.
4. `orgEventContent` for `adminMove(A→B)` and profile "Work" → identifier `org-event-<uuid>`, title "Moved by admin: A → B", body starting "Work: ".
5. `notify` with `notificationSettings.enabled == false` or `event.notifies == false` → nothing posted (test through an injectable post closure or by checking the early return path in a unit test).
6. `ensureFreshCredentials` in `AnthropicUsageProvider` receives a non-nil `onRefreshRejected`.
7. Active profile `needsLogin` → `hasCredentialError == true` after the pass, banner text "Log in again".
8. Full suite passes, including all pre-existing tests.

**Tests:** `OrgEventNotificationTests` for lines 4–5 and every `OrgEvent.Kind` producing a non-empty
title. Edge cases: event with an org id missing from `orgNames`; profile name with emoji/unicode.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`
