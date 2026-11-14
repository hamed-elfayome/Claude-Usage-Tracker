### MT-6 — TeamTracker: probe rounds, org lists, detection, group moves, persistence, history, events

Size: L
Risk: high
Importance: high
After: MT-2, MT-3, MT-4, MT-5

**Goal:** One `@MainActor` tracker that runs the whole follow model for anthropic profiles: org lists, probe
rounds, per-account rules (MT-2), current detection and group events (MT-3), scheduling and backoff (MT-5),
persistence of `orgTracking` and global state, per-pair history, invariants 2–3, notifications through a
protocol, and the contract the menu bar loop uses (MT-7). No edits to MenuBarManager or any view here.
Spec `docs/specs/multi-team-tracking.md` §3–§7, §10, §12 — read them first.

**Files**
- NEW `Claude Usage/Shared/MultiTeam/TeamTracker.swift`
- NEW `Claude Usage/Shared/MultiTeam/TeamTrackerAdapters.swift`
- NEW `Claude UsageTests/TeamTrackerTests.swift` (fakes inside or in NEW `Claude UsageTests/Fixtures/TeamTrackerFakes.swift`)
- Read only: all `Claude Usage/Shared/MultiTeam/*.swift`, `Claude UsageTests/Fixtures/TeamFixtures.swift`,
  `Shared/Services/ProfileManager.swift` (`updateOrgTracking`, `updateOrganizationId`, `saveClaudeUsage`),
  `Shared/Services/UsageHistoryService.swift` (`forKey:` API), `Providers/Anthropic/AnthropicUsageProvider.swift:37-95`.

**Steps**
1. Protocols (in `TeamTracker.swift`):
   ```swift
   protocol TeamUsageFetching { func fetchOrganizations(sessionKey: String) async throws -> [ClaudeAPIService.AccountInfo]
     func fetchUsageOnly(sessionKey: String, organizationId: String) async throws -> ClaudeUsage
     func fetchUsageViaProvider(_ profile: Profile) async throws -> ClaudeUsage }        // OAuth-only probes
   protocol TeamCredentialReading { func sessionKey(for p: Profile) -> String?; func hasCredential(_ p: Profile) -> Bool
     func credentialOrg(for p: Profile) -> (orgId: String?, seat: SeatFingerprint?); func fingerprint(for p: Profile) -> String? }
   @MainActor protocol TeamProfileStore { var trackedProfiles: [Profile] { get }; var activeProfileId: UUID? { get }
     func updateOrgTracking(_ s: OrgTrackingState, for id: UUID); func updateOrganizationId(_ o: String?, for id: UUID)
     func saveClaudeUsage(_ u: ClaudeUsage, for id: UUID) }
   protocol PairHistoryRecording { /* the forKey: record*Periodic, record*Reset and deleteHistory(forKey:) of MT-1, same parameters */ }
   @MainActor protocol TeamEventNotifying { func post(_ event: TeamEvent, profiles: [Profile]) }
   ```
2. Adapters (`TeamTrackerAdapters.swift`): `ClaudeAPITeamFetcher` (wraps `ClaudeAPIService.fetchAllOrganizations(sessionKey:)`,
   `fetchUsageOnly`, and `ProviderRegistry.service(for: .anthropic).fetchUsage(for:)`); `StoredCredentialReader`
   (session key = `profile.claudeSessionKey`; credential org/seat via `CredentialOrgParser` on `cliCredentialsJSON`,
   else `oauthAccountJSON`; fingerprint = first 16 hex chars of SHA256 (CryptoKit) of session key + `claudeAiOauth.refreshToken`;
   never logged); `extension ProfileManager: TeamProfileStore` (anthropic profiles only); `extension UsageHistoryService:
   PairHistoryRecording`; `NoopTeamEventNotifier`. Keychain reads: none.
3. `@MainActor final class TeamTracker: ObservableObject` with
   `init(store:fetcher:credentials:history:notifier:globalStore:policy:clock:random:)`, `static let shared`
   (real adapters, `NoopTeamEventNotifier`, `TeamTrackingGlobalStore()`), `var notifier` settable. Public contract
   exactly spec §10 plus `internal func tick(now: Date) async` for tests.
4. `start()`: no-op unless `TeamTrackingSettings.isEnabled()`; `scheduler.start(now)`; a `Task` loop calling
   `tick(now: clock())` then sleeping `policy.tick`. `stop()` cancels it and bumps a `generation` counter; any
   async result whose generation is stale is dropped before persisting. Ticks never overlap (`isTicking`).
5. `tick(now:)` order: (a) register/unregister accounts in the scheduler (`hasOrgList` = has session key); (b) repair
   `current` by the start rule (§4); (c) due lists via `BoundedTaskRunner` (cap 4, 1 per account) → observation
   with `orgList` (map `AccountInfo` → `OrgListEntry`, seat via `CredentialOrgParser.seat(rateLimitTier:ravenType:billingType:)`,
   `canChat = capabilities.contains("chat")`; non-CF 401/403 → `orgListAuthFailed`; Cloudflare → no observation;
   outcome to `scheduler.listFinished`); (d) if `isRoundDue` → round (step 6); (e) save global state if changed.
6. Round: `roundStarted`; eligible saved pairs (spec §4) probed via runner — session key → `fetchUsageOnly`,
   OAuth-only credential org → `fetchUsageViaProvider` (a result with `lastUpdated ≤ lastSampleAt` is no sample).
   Errors: `isRateLimited` → `scheduler.record(.rateLimited(retryAfterSeconds))`; non-CF `isMembershipFailure` →
   `usageMembershipFailures`, and `.apiUnauthorized` on OAuth-only → `oauthUnauthorized`; others `.failed`.
   Then one `AccountRules.apply` per tracked account (empty samples allowed; X runs), then for accounts with a
   membership failure `forceList` + inline list + apply again. Then `CurrentPairDetector.evaluate` over every
   `member` pair of `.ok` accounts (current's candidate = its `lastUsage` if `lastSampleAt > lastRoundAt`); write
   `roundReading`s, `lastRoundAt`, clear `manualPickAt` when told, apply switch effects (§4).
7. One private `process(profileId:result:)` for every path: `updateOrgTracking`; `followedOrgId` → for session-key
   accounts `updateOrganizationId`, and `saveClaudeUsage(followed pair lastUsage)`; `resetSnapshots` →
   `record*Reset(forKey: historyKey, …)` with the previous window's reset time, skip that window's periodic
   record; periodic records for every accepted sample; probe sample of the followed pair of a non-current account →
   `saveClaudeUsage` + `onSample`; `deletedHistoryKeys` → `deleteHistory`; events → `global.appendEvent`, post when
   `notifies` (`nowOn`: only if ≥ 900 s since `lastSwitchNotificationAt`, then set it); if the current pair became
   `old` → current = move target (or nil), `onCurrentChanged`.
8. Group move (§6): when `confirmedRemovals` has org A and peers exist, withhold this account's move/removed event
   for A, force peer lists (`bypassDebounce: true`) through the runner with `timeout: 60`, apply each with
   `peerConfirmedRemovals = [A]`, withhold their A events, map outcomes to `PeerOutcome`, append and post one
   `GroupMoveAggregator.event(...)`.
9. `liveTarget`, `ingestLive`, `makeCurrent`, `deleteOldPair`, `reportRefreshRejected` per spec §10 and §4/§6.
   `ingestLive` success never calls `saveClaudeUsage` (the loop does); failures map like step 6; a membership
   failure forces the list in a `Task`.
10. Tests with fakes (fetcher returning `TeamFixtures` bodies, credential reader, in-memory store, recording history
    and notifier, `UserDefaults(suiteName:)` global store, controllable clock, fixed random), then Validate.

**Acceptance criteria**
1. Detected switch: current (P1, A) idle; (P2, B) probe 10 % → 14 % over two rounds → current (P2, B), P2 `organizationId == "B"`, one "Now on" notification; a second switch 5 min later → event logged, no notification.
2. Manual pick: `makeCurrent((P3, C))` → current immediately, no notification; the next round with P1 rising does not switch; the round after does.
3. Admin move: probe of (P1, A) returns 404, inline list [B] → `adminMove(A→B)`, A `.old` and never probed again, P1 `organizationId == "B"`, current follows to (P1, B) when A was current.
4. Group move: P1…P5 share A; P1's list confirms A gone → peers listed at once; P2–P4 moved to B, P5 still lists A → exactly one notification "4 accounts moved: A → B", P5 in `notMoved`; no individual `adminMove` events.
5. Group move with a peer backing off → that peer in `unchecked`.
6. Seat change: list `orgsAStandard` then `orgsAPremium` → one `seatChange` notification.
7. Early reset: live samples 60 → 5 → 6 (reset 3 h away) via `ingestLive` → one `earlyReset` notification and one session reset in history under the pair's key.
8. 429: probe `.apiRateLimited` with Retry-After 120 → account skipped by the next round and lists; `liveTarget()` nil when the current account is backing off.
9. Login loss: `reportRefreshRejected(P1)` → `needsLogin`, no probes/lists for P1, `liveTarget()` nil if current; fingerprint changes + successful probe → `.ok`, no notification.
10. Migration: a legacy profile records periodic history under `profile.id.uuidString`.
11. Old team: `old` pair last seen 16 days ago → deleted at the next round, `deleteHistory` called with its key; `deleteOldPair` on a `member` pair → false.
12. Invariant 3: a probe sample of a saved non-followed org never changes `claudeUsage`; of the followed org of a non-current account it does; `ingestLive` never does.
13. `stop()` during a round → nothing persisted from that round.
14. Tracking disabled → `start()` does nothing, `liveTarget()` nil.
15. Full suite passes.

**Tests:** one test per line 1–14. Edge cases: profile deleted while a probe is in flight (no store write);
Cloudflare 403 on a probe → no event, no list; two profiles with the same org id stay independent; no anthropic
profiles → tick is a no-op.

**Validate:** `scripts/validate-clt.sh` (runs `xcodebuild test` automatically when full Xcode is present) `git diff --check`

**Coverage limit:** without Xcode the harness does not build the widget extension, the asset catalog or other resources, and compiles DynamicNotchKit/Sparkle against stubs; one full `xcodebuild` build+test run is required at release time (see `multi-team.md`).
