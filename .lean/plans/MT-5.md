### MT-5 — Multi-team coordinator with injected adapters

Size: M
Risk: high
Importance: high
After: MT-2, MT-3, MT-4

**Goal:** One `@MainActor` coordinator that owns, for every anthropic profile: org-list refresh,
idle-pair polling through the scheduler, credential-org reading, classification, persistence of
`orgTracking`, the `claudeUsage`/`organizationId` invariants, per-pair history and event
notifications. It also exposes the small contract the menu bar loop will call in MT-6. No edits to
MenuBarManager here. Spec: `docs/specs/multi-team-tracking.md` §4, §6, §7, §9.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/MultiTeamCoordinator.swift`
- NEW `Claude Usage/Shared/MultiTeam/MultiTeamAdapters.swift`
- `Claude UsageTests/Fixtures/MultiTeamFixtures.swift` (extend only)
- NEW `Claude UsageTests/MultiTeamCoordinatorTests.swift`
- Read only: `OrgEventClassifier.swift`, `CredentialOrgParser.swift`, `MultiOrgPollScheduler.swift`,
  `AppError+MultiTeam.swift`, `ClaudeCodeSyncService.swift` (:679-725 `readOAuthAccount`/`systemHoldsAccount`,
  :880-930 token helpers, :957 `readKeychainCredentials(serviceName:)`), `AnthropicUsageProvider.swift`.

**Steps**
1. Protocols (in the coordinator file):
   ```swift
   protocol OrgUsageFetching { func fetchOrganizations(sessionKey: String) async throws -> [ClaudeAPIService.AccountInfo]
     func fetchUsageOnly(sessionKey: String, organizationId: String) async throws -> ClaudeUsage
     func fetchUsage(oauthAccessToken: String) async throws -> ClaudeUsage }
   protocol CredentialOrgReading { func credentialOrg(for profile: Profile) -> (orgId: String?, seat: SeatFingerprint?)
     func usableAccessToken(for profile: Profile) -> String?        // never refreshes
     func credentialFingerprint(for profile: Profile) -> String? }  // changes when session key or refresh token changes
   @MainActor protocol OrgTrackingStore { var trackedProfiles: [Profile] { get }
     func updateOrgTracking(_ s: OrgTrackingState, for id: UUID); func updateOrganizationId(_ id: String?, for profileId: UUID)
     func saveClaudeUsage(_ u: ClaudeUsage, for id: UUID) }
   protocol PairHistoryRecording { recordSessionPeriodic/recordWeeklyPeriodic/recordSessionReset/recordWeeklyReset (forKey: variants from MT-1) }
   @MainActor protocol OrgEventNotifying { func notify(_ event: OrgEvent, profile: Profile) }
   struct ActivePollTicket { let profileId: UUID; let orgId: String; let credentialOrgAtStart: String?; let startedAt: Date }
   ```
2. Adapters in `MultiTeamAdapters.swift`: `ClaudeAPIOrgFetcher` (wraps `ClaudeAPIService`:
   `fetchAllOrganizations(sessionKey:)`, `fetchUsageOnly`, `fetchUsageData(oauthAccessToken:)`);
   `SystemCredentialOrgReader` (spec §4 order 1–4 via `CredentialOrgParser` + `ClaudeCodeSyncService`;
   60 s cache per profile; `usableAccessToken` = token from the pinned keychain entry or
   `cliCredentialsJSON` only when not expired, never `ensureFreshCredentials`; fingerprint = SHA256 prefix
   of session key + refresh token, never logged); `extension ProfileManager: OrgTrackingStore`
   (`trackedProfiles` = anthropic profiles); `extension UsageHistoryService: PairHistoryRecording`;
   `NoopOrgEventNotifier`.
3. `MultiTeamCoordinator` (`@MainActor final class`, `ObservableObject`), `init(store:fetcher:credentials:scheduler:history:notifier:clock:)`;
   `static let shared` wires the real adapters with `NoopOrgEventNotifier`; `var notifier` is settable (MT-6 swaps it).
4. Public contract:
   - `start()` → `syncJobs()` then one `Task` running `scheduler.run(execute:)`; `stop()` cancels it.
   - `syncJobs()` registers per profile: org-list job when it has a session key (900 s); usage jobs
     (300 s) for every `.idle` pair reachable by session key, and for the `.active` pair when the profile
     is not in `loopProfileIds` and is reachable (session key, or credential org with a usable token);
     900 s for pairs with `consecutiveUsageAuthFailures ≥ 3`; unregisters everything else, deleted profiles,
     and accounts in `needsLogin`.
   - `setLoopProfiles(_ ids: Set<UUID>)` stores `loopProfileIds` and calls `syncJobs()` when it changed.
   - `beginActivePoll(for:) -> ActivePollTicket?` — nil when the account is backing off, or `needsLogin`
     and the credential fingerprint has not changed. Org = session key + `organizationId` ? that org :
     credential org ?? `TrackedOrg.unknownOrgId`.
   - `ingestActive(_:result:isCachedReading:)`, `reportRefreshRejected(profileId:)`, `isBackingOff(_:)`,
     `var onActiveOrgChanged: ((UUID) -> Void)?`.
5. One private `process(profileId:observation:)` used by every path: classify → `updateOrgTracking` →
   if session key and `activeOrgId != organizationId` → `updateOrganizationId` → history: for each
   `resetSnapshot` record the reset (`resetTime` = previous window reset time) and skip that window's
   periodic record; periodic records for every accepted sample → events with `notifies` → `notifier.notify`
   → if `activeOrgId` changed: `saveClaudeUsage(newActive.lastUsage)` when present and call
   `onActiveOrgChanged` → `syncJobs()` if any status changed.
6. Job execution: org list → `fetchOrganizations`, map `AccountInfo` → `OrgListEntry` (seat via
   `CredentialOrgParser.seat(rateLimitTier:ravenType:billingType:)`, `canChat = capabilities.contains("chat")`).
   Usage → `fetchUsageOnly` or OAuth. Before classifying, read the credential org; if it differs from
   `state.lastCredentialOrgId` and the profile has a session key, fetch the list inline first. A usage
   error with `isMembershipFailure` → add to `usageMembershipFailures`, then fetch the list inline when
   `scheduler.forceSoon(orgList job)` returns true. Cloudflare → no observation. Outcome mapping:
   `isRateLimited` → `.rateLimited(retryAfterSeconds)`, success → `.success`, else `.failed`.
   Scheduler-path samples of the active pair also `saveClaudeUsage` (invariant 1).
7. `ingestActive`: cached reading → nothing. Re-read the credential org; if it differs from
   `ticket.credentialOrgAtStart` → drop the sample but still process the credential change. Success →
   observation with `samples[ticket.orgId]` (do not `saveClaudeUsage`; the loop does). Failure →
   rate-limit → `scheduler.record`; membership failure → as step 6; `.apiUnauthorized` on an
   OAuth-only profile → `oauthUnauthorized = true`.
8. Tests with fakes (fake fetcher returning fixtures from `MultiTeamFixtures`, fake credentials,
   in-memory store, recording history and notifier, scheduler with test clock). Then Validate.

**Acceptance criteria**
1. Scenario switch: credentials A→B with list [A,B] → store state active B, `organizationId == "B"`, one notification "Now using team B".
2. Scenario move: usage of A returns 404, inline list [B] → `adminMove(A→B)`, A `.removed`, A not scheduled any more.
3. Scenario seat change: list with `rate_limit_tier` std→premium → one `seatChange` notification.
4. Scenario early reset: two active samples 60 % → 5 % → 6 % with reset 3 h away → one `earlyReset` notification and one session reset in history under A's key.
5. Scenario 429: idle poll returns `.apiRateLimited` with Retry-After 120 → `isBackingOff == true`; `beginActivePoll` returns nil for that profile.
6. Scenario login loss: `reportRefreshRejected` → state `needsLogin`, its jobs unregistered, `beginActivePoll` nil; after the fake fingerprint changes, `beginActivePoll` returns a ticket and a success restores `.ok`.
7. Migration scenario: a legacy profile (migrated by MT-1) with history key = profile UUID records periodic history under that key.
8. Ticket dropped: credential org changes between `beginActivePoll` and `ingestActive` → sample not stored in any pair.
9. Idle pair sample never changes `profile.claudeUsage`; active pair sample from the scheduler does.
10. `orgAdded` / `loginRestored` events → no notification.
11. Full suite passes.

**Tests:** one test per acceptance line 1–10. Edge cases: profile deleted while a job is in flight (no
crash, no store write for it); Cloudflare 403 → no event and no list fetch; credential org unreadable →
active org stays the stored pick; two profiles sharing an org id are independent.

**Validate:** `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` `git diff --check`
