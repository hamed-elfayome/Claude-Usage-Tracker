# Multi-team tracking — specification (v2, follow the account in use)

Status: for build (Elephant spec v2, 14 Nov 2026). Replaces draft v1.
Requirements: `docs/specs/multi-team-requirements.md` — R2, R4, R5, R6, R8, R10–R18; the "Owner revision"
overrides R1, R3, R7, R9. Build plan: `.lean/plans/multi-team.md` (packets MT-1 … MT-9).

## 1. Problem and model

The owner has several Claude accounts (5 Google logins) on a company Team plan and uses the **Claude desktop
app**. Each (account, org, seat) has its own 5-hour and weekly counters. The app keeps one `organizationId`
per profile, so team switches, admin moves and seat changes look like resets.

v2 model — **follow the account in use**:
- An **account** is an anthropic `Profile`. A **pair** is (account, org). Codex profiles are untouched.
- Exactly one pair is **current**: polled live every 30 s by the existing menu bar loop. Every other pair is
  **saved**: last reading kept, probed with one request every 5 min.
- The current pair is **detected from usage**: the pair whose 5-hour usage rose most since the previous probe
  round becomes current. The desktop app's storage is never read (encrypted; owner forbids it).
- The app never switches accounts: no account switcher, no write to Claude Code credentials.
- The whole feature sits behind one setting, **Team tracking** (`multiTeam.enabled`, default off). Off = the
  app behaves exactly as today (other users of this open-source app see no change).

What v1 had and v2 drops (requirement gone): live tracking of every pair at 30 s (R1, R7), owner-switch
detection from the Claude Code credential org (R3, the "W" rule), live Keychain / `.claude.json` org reads,
the per-pair job scheduler actor, a separate "most room left" view (R9 is now the sort order of the Teams list).

## 2. Verified current behaviour (file:line, read 14 Nov 2026, branch at `f51d871`)

| Area | Fact | Where |
|---|---|---|
| Profile | One `organizationId`, `apiOrganizationId`, raw `oauthAccountJSON`, `cliCredentialsJSON`, one `claudeUsage`; custom `CodingKeys`, `init(from:)` decodes usage with `try?` | `Shared/Models/Profile.swift:21-24, 56, 59, 149-207` |
| Storage | Secrets to Keychain, rest JSON in `UserDefaults.standard` key `profiles` | `Shared/Storage/ProfileStore.swift:28-60` |
| Profile switch | `activateProfile` re-syncs the old profile and **writes the new profile's CLI credentials to the Claude Code keychain** — it is an account switcher | `Shared/Services/ProfileManager.swift:198-260` |
| Org list | `fetchAllOrganizations(sessionKey:)` = `GET /api/organizations`, session cookie only | `Shared/Services/ClaudeAPIService.swift:300` |
| Org fields | `AccountInfo` decodes only `uuid`, `name`, `capabilities`; `preferredOrganization` keeps current if listed, else first `chat`, else first | `ClaudeAPIService+Types.swift:28-46` |
| Session usage | `fetchUsageData(sessionKey:organizationId:)` = 4 requests (usage, overage, credit grant, spend) | `ClaudeAPIService.swift:513-542` |
| OAuth usage | `fetchUsageData(oauthAccessToken:)`, no org parameter (token's org); non-200 → `.apiUnauthorized` (401/403) or `.apiGenericError` (incl. 429) | `ClaudeAPIService.swift:545-570` |
| Status mapping | `performRequest` :725; 401/403 → `.apiUnauthorized` unless Cloudflare; 429 → `.apiRateLimited` (no Retry-After kept) :839; 404 → `.apiGenericError` although `.apiNotFound` exists | `ClaudeAPIService.swift:807-866`; `ErrorHandling/AppError.swift:166` |
| Parsing | `parseUsageResponse` :937; missing `five_hour` → 0 % with default reset time | `ClaudeAPIService.swift:937-1066` |
| Usage model | `sessionResetTime: Date`, `weeklyResetTime: Date` non-optional; `hasSessionLimit`, `hasWeeklyLimit`; `lastUpdated: Date` | `Shared/Models/ClaudeUsage.swift:8-18, 28-29, 70` |
| Session projection exists | `effectiveSessionPercentage` = 0 when no 5-hour limit or `sessionResetTime < Date()` (14 call sites) — weekly has none | `ClaudeUsage.swift:21-23` |
| Fetch chain | Session key + org, then CLI OAuth via `ensureFreshCredentials` (:54, **no `onRefreshRejected` passed**), then system keychain (active profile only), else cached `claudeUsage` | `Providers/Anthropic/AnthropicUsageProvider.swift:37-95` |
| Refresh rejected | `ensureFreshCredentials(…, onRefreshRejected:)` fires on `invalid_grant` | `ClaudeCodeSyncService.swift:1052-1056, 1184-1185` |
| Credential org | Credentials JSON root or `claudeAiOauth` → `organizationUuid`; `.claude.json` `oauthAccount.organizationUuid/organizationName` | `ClaudeCodeSyncService.swift:408-428` |
| Loop | Timer = active profile `refreshInterval` (30 s) :738; multi mode `refreshAllSelectedProfiles` :1007-1160 fetches each selected profile via `fetchUsage(for:)` :1163-1165; single mode `refreshUsage` :1201-1418 uses `fetchUsageForActiveProfile` :1245 | `MenuBar/MenuBarManager.swift` |
| Display | Single mode renders `activeProfile?.claudeUsage` :958; multi mode `updateMultiProfileButtons(profiles:)` :974, :1000 renders each profile's `claudeUsage` | `MenuBarManager.swift` |
| Statusline | Cache written only in the fetch paths :1094-1097 (multi), :1287-1290 (single) | `MenuBarManager.swift` |
| Reset detection | `resets_at` moved > 5 min (`ResetDetection.tolerance`) | `Models/UsageHistory.swift:326-335`; `MenuBarManager.swift:1512-1600` |
| History | One file per profile `usageHistory_<UUID>.json`; cache keyed by UUID | `Services/UsageHistoryService.swift` (411 lines) |
| Popover | Viewed profile = clicked profile `?? profileManager.activeProfile` :135, :144, :206; insights block :262-266 | `MenuBar/PopoverContentView.swift` |
| In-app sign-in | `ConsoleAuthSheet` loads `https://claude.ai/login` | `Views/Settings/Credentials/PersonalUsageView.swift:258-289`; paste field :318 |
| Web view | `WKWebView`, `websiteDataStore = .default()`, JS popups allowed; clears claude/anthropic cookies, **keeps Google cookies "so SSO popup works"**; Google popup window + `window.close` handling | `ConsoleAuthWebView.swift:26-48, 150-195` |
| Claude Code login | Per-profile launcher exports `CLAUDE_CONFIG_DIR` and runs `claude` (its `/login` uses the system browser) | `Shared/Services/TerminalLauncherService.swift:19, 126` |
| Notifications | Post pattern `sendAutoSwitchNotification` | `Shared/Services/NotificationManager.swift:308` |
| Project | File-system synchronized groups: new `.swift` files join targets; no `project.pbxproj` edits | `Claude Usage.xcodeproj/project.pbxproj:77-88` |

Field confirmation: org uuid of a Claude Code login — **yes** (`organizationUuid`, may be missing in newer
schemas). Seat/tier fields in the org list (`rate_limit_tier`, `billing_type`, `raven_type`) — **not seen in
the repo**; decoded as optional. `claudeAiOauth.subscriptionType` — yes (plan, not Standard/Premium).

## 3. Data model (`Claude Usage/Shared/MultiTeam/TeamTrackingModels.swift`)

```swift
enum UsageWindow: String, Codable { case session, weekly }
struct SeatFingerprint: Codable, Equatable {
    enum Source: String, Codable { case orgList, credentials }
    let source: Source; let value: String              // "|"-joined present values
}
enum PairStatus: String, Codable {
    case member        // in the org list (session key) or the credential org (OAuth-only)
    case old           // confirmed gone from the list: read-only, never probed, auto-deleted after 15 days
    case unreachable   // OAuth-only: a previous credential org; read-only, never probed, never auto-deleted
}
struct RoundReading: Codable, Equatable { let percent: Double; let resetTime: Date; let at: Date }
struct PendingChange: Codable, Equatable {
    enum Kind: Codable, Equatable { case earlyReset(UsageWindow), seatInferred }
    let kind: Kind; let baseline: ClaudeUsage; let candidate: ClaudeUsage; let detectedAt: Date
}
struct TrackedOrg: Codable, Equatable, Identifiable {
    var id: String { orgId }
    var orgId: String                 // TrackedOrg.unknownOrgId until known
    var name: String
    var status: PairStatus
    let historyKey: String            // assigned once, never reused
    var seat: SeatFingerprint?
    var lastUsage: ClaudeUsage?       // last real reading (never a projection)
    var lastSampleAt: Date?
    var firstSeenAt: Date
    var lastSeenInListAt: Date?
    var missingFromListCount: Int
    var lastMembershipFailureAt: Date?
    var pending: PendingChange?
    var baselineStartedAt: Date
    var roundReading: RoundReading?   // detection baseline (§4)
    static let unknownOrgId = "unknown-org"
}
enum AuthState: Codable, Equatable { case ok; case needsLogin(reason: String, since: Date) }
struct OrgTrackingState: Codable, Equatable {        // per account, stored on Profile
    var orgs: [TrackedOrg]
    var lastOrgListAt: Date?
    var authState: AuthState
    var legacyHistoryKeyAssigned: Bool
    var credentialOrgId: String?      // OAuth-only accounts: last seen token org
    var credentialFingerprint: String? // SHA256 prefix of session key + refresh token; never logged
    var consecutiveOAuthUnauthorized: Int
}
struct PairRef: Codable, Hashable { let profileId: UUID; let orgId: String }
struct TeamEvent: Codable, Equatable, Identifiable {
    enum Kind: Codable, Equatable {
        case nowOn(PairRef, from: PairRef?, manual: Bool)
        case adminMove(profileId: UUID, from: String, to: String)
        case groupMove(from: String, to: String?, moves: [UUID: String?], notMoved: [UUID], unchecked: [UUID])
        case teamRemoved(profileId: UUID, org: String)
        case teamChanged(profileId: UUID, from: String, to: String)   // OAuth-only account
        case teamAdded(profileId: UUID, org: String)
        case teamRejoined(profileId: UUID, org: String)
        case seatChange(PairRef, from: String?, to: String?, inferred: Bool)
        case earlyReset(PairRef, window: UsageWindow, fromPercent: Double, toPercent: Double)
        case loginLost(profileId: UUID, reason: String)
        case loginRestored(profileId: UUID)
        case oldTeamDeleted(profileId: UUID, org: String, manual: Bool)
    }
    let id: UUID; let date: Date; let kind: Kind
    let names: [String: String]       // orgId and profile uuidString -> display name at event time
    var title: String; var body: String; var notifies: Bool          // computed
}
struct TeamTrackingGlobalState: Codable, Equatable {  // UserDefaults key "multiTeam.globalState"
    var current: PairRef?
    var manualPickAt: Date?
    var lastRoundAt: Date?
    var lastSwitchNotificationAt: Date?
    var events: [TeamEvent]           // newest first, capped at 50
}
```
`notifies == false` for `nowOn(manual: true)`, `teamAdded`, `teamRejoined`, `loginRestored`, `oldTeamDeleted`.
Titles (English, keys `multiteam.event.<case>.title|body`): "Now on %@ (%@)" (account, team); "Moved by
admin: %@ → %@"; "%d accounts moved: %@ → %@" / "%d accounts removed from %@"; "Removed from team %@";
"Team changed: %@ → %@"; "Added to team %@"; "Back in team %@"; "Seat changed in %@" / inferred "Limit size
changed in %@"; "Early reset: %@ %@ limit"; "Log in again: %@"; "Login restored: %@"; "Old team %@ deleted".
Unknown name → first 8 characters of the id.

`Profile` gains `var orgTracking: OrgTrackingState?` (not a secret; decoded with
`(try? c.decodeIfPresent(...)) ?? nil`, so a corrupt blob never fails the profile). Global state is a
separate JSON blob (`TeamTrackingGlobalStore`, injected `UserDefaults`, corrupt → empty).

**Invariants**
1. A rule compares a sample only with the previous **real** sample of the **same pair** and the same baseline;
   switches and moves can therefore never look like resets (R6).
2. For session-key accounts `profile.organizationId` = the account's **followed org**: the org of its most
   recent current pair, or the target of its last move (R4). Changing it is how the live fetch follows.
3. `profile.claudeUsage` = `lastUsage` of the followed pair (live for the current account, probe otherwise);
   widget, statusline and the menu bar keep reading `claudeUsage`.
4. `historyKey` is assigned once and never reused; deleting an old pair deletes only its file and keys.
5. Projections are computed at read time and never stored (§5).

**History keying.** `UsageHistoryService` is keyed by `String`. The UUID API delegates with
`profileId.uuidString` (file `usageHistory_<UUID>.json` and `lastSessionRecordTime_<UUID>` unchanged). New
pairs use `"<profileUUID>_<orgId>"`. New `deleteHistory(forKey:)` removes the file, cache entry and both
record-time keys.

## 4. Current detection (R15, R16)

Every 300 s the tracker runs a **probe round**: one usage request per eligible saved pair, then one pure
evaluation `CurrentPairDetector.evaluate(_:)` over all pairs.

- **Eligible pair:** status `member`, account `authState == .ok`, account has a credential (session key →
  any member org; OAuth-only → its credential org only), account not backing off, org not `unknownOrgId`.
  The current pair is not probed; its reading is its newest live sample if taken after the previous round.
- **Metric:** `percent = hasSessionLimit ? sessionPercentage : weeklyPercentage`, `reset` = matching reset time.
- **Rise** of a pair with previous `roundReading` p and new reading n:
  - no p, or `n.at − p.at > 450 s` (1.5 rounds: stale after a failure, sleep or start) → **re-baseline only**, no rise;
  - same window (`|n.reset − p.reset| ≤ 300 s`, `ResetDetection.tolerance`) → `rise = n.percent − p.percent`;
  - different window (rolled over, or early reset) → `rise = n.percent` (all usage is new since p);
  - `rise < 1.0` point → 0 (rounding noise; utilization is reported in whole percents).
- **Decision:** let R* be the largest rise ≥ 1.0. Top = pairs with `rise ≥ R* − 0.05`.
  - No rise anywhere → current unchanged (owner idle; "no usage anywhere").
  - Current is in Top → unchanged ("ties keep the existing current").
  - Exactly one pair in Top → it becomes current; old current becomes saved with its last reading.
  - Several non-current pairs in Top → unchanged; if current is nil, the first in (profile order, org order).
- **Manual "Make current"** (R16): sets current at once (event `nowOn(manual: true)`, no notification),
  stores `manualPickAt`; the **next round only re-baselines** every pair (no switch), so the pick holds until
  usage rises on another pair after the click. Then normal rules.
- **New readings:** every pair with a reading in the round gets `roundReading = (percent, reset, now)`;
  others keep their old baseline (and go stale after 450 s).
- **Start:** if `current` is nil or points to a deleted profile/pair, it is set to the active profile's
  followed pair (no event). First round after start only baselines.
- **Switch effects:** event `nowOn(new, from: old, manual: false)`; `organizationId` of the new account =
  new org (session key); `claudeUsage` of that account = the pair's `lastUsage`; the loop is asked to refresh
  now. Notification only if `now − lastSwitchNotificationAt ≥ 15 min` (flap guard); the event is logged anyway.

Edge cases:
| Case | Behaviour |
|---|---|
| No usage anywhere | Current unchanged; saved pairs project to 0 after their reset (§5) |
| Two accounts rising | Largest rise wins each round; equal → current kept. Parallel use flips current; notifications ≤ 1 / 15 min |
| Probe fails (network, 5xx, 429, cached reading) | Pair has no reading this round: no rise, baseline kept; next good reading > 450 s later only re-baselines |
| Current's live poll failing | Current has no reading → cannot defend; another riser takes over |
| Account signed out (`needsLogin`) or no credential | Its pairs are ineligible; if current, it stays current (shown "Log in again" / "Not signed in") until another pair rises |
| Current pair's org confirmed gone | Account follows the move target (R4): current = (account, B), no `nowOn` event (the move event covers it); no target → current = nil, display falls back to the active profile |
| Current account deleted | current = nil, then the start rule |
| Window rolled between rounds | `rise = n.percent` |
| Weekly-only plan | Metric uses weekly percent (1 weekly point is a lot of use; detection is coarser) |

## 5. Saved-window projection (R17)

Pure `PairView.make(usage:sampledAt:now:)` used by every saved-pair display:
- session: if `hasSessionLimit` and `sessionResetTime ≤ now` and `sampledAt < sessionResetTime` → 0 %,
  `sessionProjected = true`, reset time shown as "unknown until next check". This matches the existing
  `effectiveSessionPercentage` (§2), which the main popover rows already use.
- weekly: same with `weeklyResetTime`; per-model weeklies (`opus/sonnet/design/fable`) go to 0 with it (sonnet,
  design, fable use their own reset time when present).
- headroom = min(100 − session, 100 − weekly) (weekly only when no 5-hour window), clamped 0…100.
- The next real reading replaces the projection (nothing is stored). Projected values never feed rules,
  history or detection.

## 6. Event state machine

Per account, pure `AccountRules.apply(_ obs: AccountObservation, to: OrgTrackingState, profileId:, profileName:, followedOrgId:) -> AccountResult`:
```
AccountObservation { now, hasSessionKey, credentialFingerprint, credentialOrgId, credentialSeat,
  orgList: [OrgListEntry]?   // nil = none this time or failed
  orgListAuthFailed, peerConfirmedRemovals: Set<String>, samples: [orgId: ClaudeUsage],
  usageMembershipFailures: Set<String>, oauthUnauthorized, refreshRejected }
OrgListEntry { orgId, name, seat: SeatFingerprint?, canChat }
AccountResult { state, events, resetSnapshots: [(orgId, UsageWindow, previous: ClaudeUsage)],
  confirmedRemovals: [(orgId, movedTo: String?)], followedOrgId: String?,   // non-nil only when it must change
  deletedHistoryKeys: [String], acceptedSamples: [orgId: ClaudeUsage] }
```
Order: U (unknown-org rename) → L → M → T → S → R → X. Per pair precedence **L > M > T > S > R**: a pair with an
identity event (M, T, S) in this run skips R, clears `pending`, restarts its baseline.

**Detected switch** — §4 (cross-account, not per account).

**U — unknown org.** A `unknownOrgId` pair is renamed in place (same `historyKey`, no event) to the credential
org or, with a list, the only chat org / the followed org; if that org is already tracked, the unknown pair is dropped.

**L — login loss (R8).**
- L1 `refreshRejected` (Claude Code `invalid_grant`) → `needsLogin("Claude Code login was revoked")`.
- L2 `orgListAuthFailed` (non-Cloudflare 401/403 on the list) → `needsLogin("claude.ai session expired")`.
- L3 OAuth-only: `oauthUnauthorized` on 2 consecutive polls → `needsLogin("Log in again")`. One 401 is not
  enough (transient 401s exist).
- Event `loginLost` (notifies). While `needsLogin`: no probes or lists for the account; the live loop skips it;
  UI shows "Log in again" instead of numbers. Leaves on a changed `credentialFingerprint` or any successful
  sample/list → `.ok`, `loginRestored` (silent).
- A usage 401/403/404 on one org is checked against the list first (M); only a dead credential is login loss.

**M — membership (R2, R4, R12).** Session-key accounts, only with a successful non-empty list. Non-chat orgs ignored.
- New org → `member`, `teamAdded` (silent). `old` org listed again → `member`, `teamRejoined` (silent), history intact.
- Listed → `missingFromListCount = 0`, `lastSeenInListAt = now`. Missing → count +1 when `now − lastOrgListAt ≥ 60 s`.
- **Confirmed gone** when missing and: count ≥ 2, **or** its usage call had a membership failure (non-CF
  401/403/404) in the last 10 min, **or** the org is in `peerConfirmedRemovals` (R13).
- Confirmed gone A → `old`; target B = newest `member` with `firstSeenAt ≥ A.lastSeenInListAt − 24 h`
  (not A). B → `adminMove(A → B)`, else `teamRemoved(A)`. If A was followed → `followedOrgId = B` (or the
  first member). `confirmedRemovals += (A, B)` for R13.
- Failed, empty or Cloudflare list → no membership change.

**T — OAuth-only team change.** No session key; credential org C₀ → C₁ (both known): C₁ added/revived as
`member`, C₀ → `unreachable`, `teamChanged(C₀ → C₁)` (switch and move cannot be told apart), followed = C₁.

**S — seat change (R5).** S1: same org, same fingerprint source, both non-nil, values differ →
`seatChange(inferred: false)`. Source change → silent re-baseline. S2 (no fingerprint): consecutive real
samples, both reset times unchanged (≤ 5 min); windows qualify when present in both and previous ≥ 5 %;
candidate when ≥ 2 windows qualify (session, weekly, per-model), every ratio new/prev outside [0.67, 1.5] in
the same direction, max ratio ÷ min ratio ≤ 1.3, weekly change ≥ 3 points, no window ≤ 1 %. Stored as
`pending(.seatInferred)`; confirmed when the next sample stays within ±25 % (or ±2 points) of the candidate →
`seatChange(inferred: true)`; else discarded. A seat change rescales every window by the same limit ratio; use
moves the 5-hour value far faster than the weekly one; a reset zeroes instead of scaling.

**R — early reset (R6).** Per window W present in both samples, same pair, same baseline:
- natural = `now ≥ prev.resetTime(W) − 5 min`. Natural + reset moved > 5 min → reset snapshot, no event.
- candidate = not natural, `prev ≥ 10 %`, `new ≤ prev × 0.5`, `prev − new ≥ 10` points → `pending(.earlyReset(W))`.
- confirmed when the next sample still has `new ≤ baseline × 0.5` → `earlyReset` (notifies) + reset snapshot.
  Bounced back → discarded. Pending older than 30 min → discarded.
- not natural, reset moved, no drop → baseline updated, no snapshot, no event (fixes today's false "reset").
- Why: utilization only rises inside a window; rounding moves 1–2 points, so 10 points plus halving keeps
  noise out; a missing window parses as 0 % and is excluded by the presence check; a false alarm needs two
  consecutive bad responses. Cost: one sample late (30 s current, 5 min saved).

**X — old-team expiry (R12).** `old` pairs with `now − (lastSeenInListAt ?? firstSeenAt) ≥ 15 days` are removed;
`deletedHistoryKeys += historyKey`; `oldTeamDeleted(manual: false)` (silent). `member` and `unreachable` pairs
are never auto-deleted. Manual delete (tracker, after a confirm dialog) is allowed for `old` and `unreachable`
pairs only and emits `oldTeamDeleted(manual: true)`.

**Grouped move (R13)** — tracker + pure `GroupMoveAggregator`:
1. Account P's result has `confirmedRemovals` (A, B?). Peers = other accounts with `authState .ok`, a session
   key and a `member` pair A.
2. No peers → P's own `adminMove`/`teamRemoved` stands.
3. Peers → P's individual event is withheld; every peer gets a forced list now (bypasses the 60 s debounce,
   respects backoff, cap 4 concurrent, 60 s overall timeout) and is classified with `peerConfirmedRemovals = {A}`.
4. Peer outcome: A confirmed gone → moved (to its own target); A still listed → not moved; backoff,
   `needsLogin`, list failure or timeout → unchecked. Their individual move events are also withheld.
5. One `groupMove(from: A, to: T, moves: [P: B, …], notMoved, unchecked)` event, one notification. T (title
   target) = most common target among `moves` (ties: P's). Body names accounts with another target, not moved, not checked.
6. A peer confirming later on its own emits its own `adminMove`.

**Collapsing (R11).** Rules compare the last known state with the current one: A→B→C between lists shows as
A→C; a seat change plus an early reset shows as the seat change; a move plus a seat change as the move.

## 7. Scheduler and request budget (R2, R18)

Pure `TeamPollScheduler` (value type, injected clock/random) + `BoundedTaskRunner` (TaskGroup, max 4 in
flight, max 1 per account). The tracker ticks every 15 s and never overlaps ticks.

| Job | Interval | Requests |
|---|---|---|
| Current pair | 30 s, existing loop | session key 4 (usage, overage, credit, spend); OAuth 1 (+1 fallback) |
| Probe round, each saved eligible pair | 300 s, first at start + 15 s | 1 (`fetchUsageOnly`; OAuth-only via `AnthropicUsageProvider.fetchUsage(for:)`) |
| Org list per session-key account | 900 s, first at start + random[0, 10 s) | 1 |
| Forced list (usage 401/403/404, non-CF) | ≤ 1 per 60 s per account | 1 |
| Group-move peer lists | once per confirmed removal | ≤ N − 1 |
| `old`, `unreachable`, `needsLogin` | never | 0 |

**429 backoff, per account, shared by loop, probes and lists:** k = consecutive 429s; delay =
min(60 s × 2^(k−1), 900 s) × (0.8 + 0.4·random); a `Retry-After` (integer seconds) wins when larger, capped at
3600 s. The loop skips the live fetch while backing off (cached value stays). First success resets k. A
Messages-API 429 carrying usage headers is data, not a 429 (as today). 5xx/network: normal interval, no
backoff, never login loss. Cloudflare challenges (`.apiServiceUnavailable`) are ignored by every rule.

**Budget** — N = 5 accounts, ≤ 2 orgs each → ≤ 10 pairs:
- live: 4 req / 30 s = **8.0/min** (today's single-mode rate);
- probes: ≤ 9 req / 300 s = **1.8/min** total, ≤ 0.4/min per account;
- lists: 5 / 900 s = **0.33/min** total, 0.067/min per account;
- steady total ≈ **10.1/min** from one IP (today: 8/min single mode, 40/min multi mode with 5 profiles);
- busiest account (current, 2 orgs): 8 + 0.2 + 0.067 = 8.27/min (+3 % over today);
- worst burst: one round = 9 requests, ≤ 4 in flight, 1 per account; forced lists ≤ 1/min/account.

## 8. Google sign-in (R14)

Code check: the in-app sign-in is an embedded `WKWebView` at `claude.ai/login` with explicit Google SSO
support (popup window, `window.close`, Google cookies kept) — §2. Whether Google accepts this embedded web
view cannot be proven by reading code (Google blocks many embedded user agents with "This browser or app may
not be secure"). Decision:
- **Owner check (manual, the agent never handles credentials):** Settings → Personal usage → "Sign in to
  Claude.ai" → Continue with Google, once per account. Result goes in `docs/profiles.md`.
- Because Google cookies are kept, the Google popup may reuse the last Google account: pick the right one.
- **Fallback that always works: pasted session key** — sign in at claude.ai with Google in Safari/Chrome,
  copy the `sessionKey` cookie, paste it in the field (PersonalUsageView :318). It gives the org list, so
  moves, group moves and all orgs work. Recommended for the 5 accounts.
- Second fallback: **Claude Code login** (terminal launcher, system browser, Google works). It gives only the
  token's org (OAuth-only: no org list, `teamChanged` instead of move detection).
- UI: a static hint under the sign-in button: "Google sign-in blocked? Sign in at claude.ai in your browser
  and paste the session key below, or use the Claude Code login." No failure auto-detection (no reliable signal).
- The desktop app's own login is never touched or read.

## 9. Migration (R10)

Pure `TeamTrackingMigration.migrate(_ profile:, now:) -> Profile`, run in `ProfileManager.loadProfiles()`
for every profile (idempotent; only when `orgTracking == nil` and provider is anthropic). First org id =
`organizationId` ?? `organizationUuid` from `oauthAccountJSON` ?? `unknownOrgId`; name = `organizationName`
when ids match, else "Team"; `status member`, `historyKey = profile.id.uuidString` (legacy file attaches with
no move), `lastUsage = claudeUsage`, `legacyHistoryKeyAssigned = true`. Global state starts empty; the tracker
start rule sets `current`. Downgrade: older builds ignore and drop `orgTracking`; the next upgrade migrates
again; history files untouched. Turning Team tracking off stops the tracker; data stays; on again resumes.

## 10. Components and contracts

| Component | File | Packet |
|---|---|---|
| Models, global store, migration | `MultiTeam/TeamTrackingModels.swift`, `TeamTrackingStore.swift`, `TeamTrackingMigration.swift` | MT-1 |
| Per-account rules, credential parser | `MultiTeam/AccountRules.swift`, `CredentialOrgParser.swift` | MT-2 |
| Detection, projection, group event, rows | `MultiTeam/CurrentPairDetector.swift`, `PairView.swift`, `GroupMoveAggregator.swift`, `TeamRows.swift` | MT-3 |
| API signals | `ClaudeAPIService(+Types).swift`, `MultiTeam/AppError+MultiTeam.swift` | MT-4 |
| Scheduler, bounded runner | `MultiTeam/TeamPollScheduler.swift`, `BoundedTaskRunner.swift` | MT-5 |
| Tracker + adapters | `MultiTeam/TeamTracker.swift`, `TeamTrackerAdapters.swift` | MT-6 |
| App wiring | `MenuBarManager`, `AnthropicUsageProvider`, `NotificationManager`, `PopoverContentView` | MT-7 |
| UI | `MenuBar/TeamsSectionView.swift`, `UsageHistoryView`, `ManageProfilesView`, `PersonalUsageView` | MT-8 |

Tracker contract (`@MainActor final class TeamTracker: ObservableObject`, `static let shared`):
```swift
var isRunning: Bool { get }                        // enabled and started
func start(); func stop()
func liveTarget() -> (profile: Profile, orgId: String)?   // nil: off, no current, backing off or needsLogin
func ingestLive(profileId: UUID, orgId: String, result: Result<ClaudeUsage, Error>, isCachedReading: Bool)
func makeCurrent(_ pair: PairRef)
func deleteOldPair(_ pair: PairRef) -> Bool        // false unless old/unreachable
func reportRefreshRejected(profileId: UUID)
var onCurrentChanged: ((PairRef?) -> Void)?        // loop refreshes now
var onSample: ((UUID, ClaudeUsage) -> Void)?       // probe sample of a followed pair (statusline)
@Published private(set) var global: TeamTrackingGlobalState
```
Dependencies by protocol (fetcher, credential reader, profile store, history, notifier, clock) so every path is
testable with fakes. The tracker records history per pair key; for anthropic profiles with tracking running the
loop no longer calls `checkAndRecordSessionReset/WeeklyReset` or the periodic recorders.

## 11. UI

- **Settings → Profiles:** toggle "Team tracking (follow the account in use)" bound to `multiTeam.enabled`.
- **Menu bar (tracking on):** single mode shows the **current pair's** account (`menuBarProfile` =
  current account ?? active profile); live fetch of that account: `fetchUsageForActiveProfile` when it is the
  active profile, else `fetchUsage(for:)`. Multi mode: of the selected anthropic profiles only the current
  account is fetched live (it is fetched even when not selected); the others render their `claudeUsage`,
  kept fresh by probes. `needsLogin` on the shown account → existing credential-error state, "Log in again".
- **Popover:** default viewed profile = `menuBarProfile` (a click still overrides). "Teams" section after the
  insights: current row first ("Now" badge), then saved rows by headroom desc, then weekly left desc, then
  name; then `needsLogin`/not signed in; then `old`/`unreachable` rows (dimmed, "Old team · deleted in N
  days", Delete button with confirm dialog). Row: "account · team", "5h n% left", "Week n% left", "projected"
  mark on projected windows, age when older than 15 min. Row menu: "Make current". Under the list: last 5
  events (title, relative time). Section shown when tracking runs and ≥ 2 pairs exist.
- **History view:** org picker when the profile has > 1 pair with a history key (old ones labelled "(old)");
  loads by `historyKey`; one pair → today's UUID path.
- **Notifications:** one per posted event, identifier `team-event-<id>`, respecting the profile's
  `notificationSettings.enabled` (group event: any involved account enabled).
- **Sign-in hint** (§8) under the in-app sign-in button.

## 12. Failure modes

| Failure | Behaviour |
|---|---|
| Org list fails / empty / Cloudflare | No membership change; retry next interval |
| Usage 401/403/404 (non-CF) | Forced list; M decides; never login loss by itself |
| 429 anywhere | Account backoff (§7); probes, lists and live fetch skip the account |
| Token expired / provider returns cached reading | No sample (`lastUpdated` not newer than `lastSampleAt`); not login loss |
| `invalid_grant` | `needsLogin` at once |
| Corrupt `orgTracking` / global blob | Decodes as nil/empty → migration / start rule rebuild; history intact |
| Profile deleted | Its pairs vanish with it; `current` repaired by the start rule; history files left (as today) |
| Group peer list times out | Peer listed as unchecked |
| App asleep for hours | First round re-baselines; due windows are natural resets; lists re-check membership |
| Tick still running when the next is due | Skipped |
| Tracking switched off mid-round | Round results discarded; nothing persisted after `stop()` |

## 13. Test plan

Fixtures are Swift string literals (`Claude UsageTests/Fixtures/TeamFixtures.swift`, MT-1): org lists `orgsAB`,
`orgsB`, `orgsABC`, `orgsAStandard`/`orgsAPremium` (`rate_limit_tier` differs), `orgsAPIOnly`; usage body
builder `usageJSON(session:weekly:sessionReset:weeklyReset:)` and `usageNoFiveHour`, decoded with the real
`parseUsageResponse`; credentials `credentialsOrgA/B/NoOrg`; `oauthAccountOrgA`; `legacyProfileJSON`;
`http429RetryAfter120`, `http401`, `http403Cloudflare`, `http404`. They follow the parser, not production
recordings (§15).

| Suite | Packet | Cases |
|---|---|---|
| `TeamTrackingModelsTests`, `TeamTrackingMigrationTests`, `UsageHistoryKeyTests` | MT-1 | round trip of every event kind; legacy and corrupt decode; event cap; titles; migration sources; idempotent; codex untouched; same legacy file; pair file; per-key throttle; delete |
| `AccountRulesTests`, `CredentialOrgParserTests` | MT-2 | move (2 lists, 1 list + 404, peer evidence); removal; rejoin; add; failed list; OAuth team change; seat S1/S2 confirm/discard; early reset confirm/bounce/stale; natural; shifted time; missing window; identity suppresses reset; L1/L2/L3 + restore; expiry 15 d; collapse; unknown rename |
| `CurrentPairDetectorTests`, `PairViewTests`, `GroupMoveAggregatorTests`, `TeamRowsTests` | MT-3 | single riser switch; largest wins; tie keeps current; no usage; stale baseline; window roll; manual pick re-baseline; projection; headroom order; group titles |
| `ClaudeAPIServiceMultiTeamTests` | MT-4 | tier fields; 404/429/401/CF mapping; Retry-After; OAuth 429 |
| `TeamPollSchedulerTests`, `BoundedTaskRunnerTests` | MT-5 | intervals; start spread; backoff 60…900 + jitter; Retry-After; reset; forced debounce; cap 4 / 1 per account |
| `TeamTrackerTests` | MT-6 | scenarios with fakes: detected switch, manual pick, admin move, group move of 5 (1 not moved, 1 unchecked), seat change, early reset, 429, login loss + restore, migration, old-team expiry and manual delete, invariants 2–3 |
| `TeamEventNotificationTests` | MT-7 | content, gating, cooldown |
| `TeamsSectionViewTests` | MT-8 | hosting smoke test, picker gating |

Every packet validates with the full suite:
`xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -configuration Debug -derivedDataPath build -destination "platform=macOS" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`.

## 14. Trade-offs and rejected alternatives

| Choice | Why | Rejected |
|---|---|---|
| Detect current from rising usage | Works for the desktop app without reading it | Read the desktop app's storage (encrypted; owner forbids) |
| One live pair + 5-min probes | R15/R18; 10 req/min vs 40 | Live-poll every pair (v1 R1/R7) |
| Separate `menuBarProfile` for display | Follows without side effects | Switch the active profile (`activateProfile` writes Claude Code credentials = account switcher) |
| Live poll stays in the existing loop | No change to the auth chain (#268, #290, #355), statusline, threshold alerts | Tracker owns live polling: duplicates the loop's side effects |
| Opt-in toggle, default off | Zero change for other users | Always on |
| Global event log | Group events span accounts | Per-account logs (v1) |
| Pure scheduler struct + runner | Deterministic tests | Actor with its own run loop (v1 MT-4) |
| Usage-only probe for session keys | 1 request, not 4 | Full fetch per probe |
| OAuth probe via the provider | Keeps the existing refresh rules (#290) | Own token handling |
| Two-sample confirmation (reset, seat) | Rare false alarms | Single sample |
| Optional tier fields + scaling fallback | Works with or without a tier field | Require a tier field |
| Static Google hint | No reliable failure signal | Detect Google's block page |
| Manual pick re-baselines one round | Matches "until usage rises on another account" | Pin until unpinned |
| Room-left = sort order of the Teams list | R9 optional, thin | Separate ranking view |

## 15. Known limits

- A switch is noticed only after the first message on the new account: up to 5 min late; up to 10 min after a
  probe failure, wake from sleep or a manual pick (re-baseline round).
- Using two accounts at once (desktop on A, Claude Code on B) flips current to the larger riser each round.
- Any use of an account (another device, a teammate on a shared login) counts as use.
- R11: changes within one interval collapse to the final state.
- Endpoints are undocumented and may change; all new fields are optional and parsing degrades to "no event".
- No production recording of an org list with tier fields exists; **the owner should capture one redacted
  `/api/organizations` response per seat type** (Settings → Debug network log) as a fixture. If a tier field
  appears, S1 replaces S2 automatically.
- A seat change that also zeroes counters, or on a single-window plan, shows as an early reset.
- Early resets on saved pairs are reported 5–10 min late.
- OAuth-only accounts see one org; switch vs move is `teamChanged`; probes depend on the provider's token refresh.
- When the Claude Code (active) profile is not current, its statusline cache updates at probe rate (5 min).
- Session projection in the main popover rows comes from the existing `effectiveSessionPercentage`; weekly
  projection is shown only in the Teams list.
- Google sign-in in the embedded web view is unverified by code; fallbacks in §8.
