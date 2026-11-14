# Multi-team tracking — specification

Status: draft for build (Elephant spec, 14 Nov 2026). Requirements: `docs/specs/multi-team-requirements.md` (R1–R11).
Build plan: `.lean/plans/multi-team.md` (packets MT-1 … MT-8).

## 1. Problem

One Claude account can belong to several claude.ai organizations ("teams") on a Team plan. Each
(account, org, seat) has its own 5-hour and weekly counters. The app keeps one `organizationId` per
profile, so when the owner switches team, the admin moves the seat, or the admin changes the seat
type, the numbers jump and the app reports or charts it as a reset. We need to track every
(account, org) pair separately, name each change correctly, and show which pair has the most room left.

## 2. Verified current behaviour (file:line, read 14 Nov 2026)

| Area | Fact | Where |
|---|---|---|
| Profile | One `organizationId`, one `apiOrganizationId`; `oauthAccountJSON` raw string; one `claudeUsage` | `Claude Usage/Shared/Models/Profile.swift:21-24, 56, 59` |
| Profile coding | Custom `CodingKeys` + `init(from:)`; usage decoded with `try?` so a bad blob never wipes profiles | `Profile.swift:149-167, 169-205 (claudeUsage :194), encode :207` |
| Storage | Secrets to Keychain first, rest JSON in UserDefaults `profiles` | `Shared/Storage/ProfileStore.swift:35-60` |
| Org list | `GET /api/organizations` with claude.ai **session cookie only** (no OAuth variant) | `Shared/Services/ClaudeAPIService.swift:300-315` |
| Org list fields | `AccountInfo` decodes only `uuid`, `name`, `capabilities` | `ClaudeAPIService+Types.swift:28-32` |
| Org choice | `preferredOrganization`: keep current if listed, else first with `chat`, else first | `ClaudeAPIService+Types.swift:41-46` |
| Stored org | Used with no re-validation | `ClaudeAPIService.swift:480-484` |
| Org cleared | Only when the session key changes | `ClaudeAPIService.swift:258-262` |
| Session-key usage | `fetchUsageData(sessionKey:organizationId:)` = 4 requests (usage, overage, credit grant, spend) | `ClaudeAPIService.swift:513-542` |
| OAuth usage | `api.anthropic.com/api/oauth/usage`, **no org parameter**: the token's org is implied; non-200 → `.apiUnauthorized` (401/403) or `.apiGenericError` (incl. 429) | `ClaudeAPIService.swift:545-570` |
| OAuth fallback | Messages API 1-token call; 429 **with** unified headers is parsed as data | `ClaudeAPIService.swift:594-713`, headers `:1129-1160` (requirements said :627-640; corrected) |
| Status mapping | 401/403 → `.apiUnauthorized` unless Cloudflare (`.apiServiceUnavailable`); 429 → `.apiRateLimited` (no Retry-After kept); **404 → `.apiGenericError`** although `.apiNotFound` (E3004) exists | `ClaudeAPIService.swift:807-866`; `ErrorHandling/AppError.swift:166` |
| Parsing | Missing `five_hour`/`seven_day` → 0 % with default reset time; limits unknown (`sessionLimit = 0`), only utilization % is real | `ClaudeAPIService.swift:937-1066` |
| Fetch chain | Session key + org first, then CLI OAuth via `ensureFreshCredentials`, then system keychain (active profile only), else cached `claudeUsage` | `Providers/Anthropic/AnthropicUsageProvider.swift:37-91` |
| Credential org | Keychain payload root or `claudeAiOauth` → `organizationUuid`; `claudeAiOauth.subscriptionType` | `ClaudeCodeSyncService.swift:408-415`; fixture `Claude UsageTests/ClaudeUsageTests.swift:204-215` |
| Login org | `.claude.json` `oauthAccount` (`accountUuid`, `emailAddress`, `organizationUuid`, `organizationName`) | `ClaudeCodeSyncService.swift:420-428, 679-725` |
| Refresh rejected | `ensureFreshCredentials(…, onRefreshRejected:)` fires on `invalid_grant`; nobody passes it today | `ClaudeCodeSyncService.swift:1052-1056, 1184-1185` |
| Polling | Timer = profile `refreshInterval` (30 s); multi mode loops profiles **sequentially** | `Constants.swift:152`; `MenuBar/MenuBarManager.swift:737-743, 1007-1160 (loop :1039)` |
| Reset detection | Reset = `resets_at` moved > 5 min, per profile, no usage check | `Models/UsageHistory.swift:323-335`; `MenuBarManager.swift:1512-1600` |
| History | One file per profile `usageHistory_<profileUUID>.json`; cache keyed by UUID; singleton with private init | `Services/UsageHistoryService.swift:22, 38, 46, 58-72` |
| Project | Xcode file-system synchronized groups: new `.swift` files join the target automatically | `Claude Usage.xcodeproj/project.pbxproj:77-88` |

### Field confirmation

| Signal | Field | Confirmed? |
|---|---|---|
| Org uuid of the Claude Code login | `oauthAccount.organizationUuid` in `.claude.json`; `organizationUuid` (root or `claudeAiOauth`) in credentials JSON | **Yes** (read in code, test fixture). Newer credential schemas may omit it (comment at `ClaudeCodeSyncService.swift:433-434`). |
| Org list | `uuid`, `name`, `capabilities` | **Yes** |
| Seat / tier in org list | `rate_limit_tier`, `billing_type`, `raven_type` | **No** — not decoded or recorded anywhere in the repo. Decoded as optional; fallback below. |
| Seat / tier in credentials | `claudeAiOauth.subscriptionType` | **Yes**, but it says the plan ("team"), not Standard vs Premium. `claudeAiOauth.rateLimitTier`: **No** (decoded as optional). |
| Org in OAuth usage response | — | **No**. Not used. |
| `api.anthropic.com/api/oauth/profile` | — | **No** recorded response. Rejected for now (§11). |

## 3. Data model

New folder `Claude Usage/Shared/MultiTeam/`. An **account** is a profile (`Profile.id`) with
`provider == .anthropic`. A **pair** is (profile, orgId). Codex profiles are untouched.

```swift
enum UsageWindow: String, Codable { case session, weekly }

struct SeatFingerprint: Codable, Equatable {
    enum Source: String, Codable { case orgList, credentials }
    let source: Source
    let value: String          // "|"-joined present values, e.g. "default_team_premium|team"
}

enum TrackedOrgStatus: String, Codable {
    case active    // the account's current org (credential org, else user pick)
    case idle      // member, tracked at the idle interval
    case removed   // no longer a member: read-only, never polled, history kept
    case readOnly  // still maybe a member but no credential can reach it (OAuth-only account)
}

struct PendingChange: Codable, Equatable {
    enum Kind: Codable, Equatable { case earlyReset(UsageWindow), seatInferred }
    let kind: Kind
    let baseline: ClaudeUsage      // sample before the jump
    let candidate: ClaudeUsage     // first sample after the jump
    let detectedAt: Date
}

struct TrackedOrg: Codable, Equatable, Identifiable {
    var id: String { orgId }
    var orgId: String              // TrackedOrg.unknownOrgId until the real id is known
    var name: String
    var status: TrackedOrgStatus
    let historyKey: String         // never changes once assigned
    var seat: SeatFingerprint?
    var lastUsage: ClaudeUsage?
    var lastSampleAt: Date?
    var firstSeenAt: Date
    var lastSeenInListAt: Date?
    var missingFromListCount: Int  // consecutive successful lists without this org
    var lastMembershipFailureAt: Date?  // last non-Cloudflare 401/403/404 on its usage call
    var consecutiveUsageAuthFailures: Int
    var pending: PendingChange?
    var baselineStartedAt: Date
    static let unknownOrgId = "unknown-org"
}

enum AuthState: Codable, Equatable { case ok; case needsLogin(reason: String, since: Date) }

struct OrgEvent: Codable, Equatable, Identifiable {
    enum Kind: Codable, Equatable {
        case ownerSwitch(from: String?, to: String)
        case adminMove(from: String, to: String)
        case orgChanged(from: String, to: String)   // no org list: switch and move look the same
        case orgRemoved(String)
        case orgAdded(String)
        case orgRejoined(String)
        case seatChange(org: String, from: String?, to: String?, inferred: Bool)
        case earlyReset(org: String, window: UsageWindow, fromPercent: Double, toPercent: Double)
        case loginLost(reason: String)
        case loginRestored
    }
    let id: UUID
    let date: Date
    let kind: Kind
    let orgNames: [String: String]  // orgId -> display name at event time
    var title: String { … }         // e.g. "Now using team B", "Moved by admin: A → B"
    var body: String { … }
    var notifies: Bool { … }        // false for orgAdded, orgRejoined, loginRestored
}

struct OrgTrackingState: Codable, Equatable {
    var orgs: [TrackedOrg]
    var activeOrgId: String?
    var lastCredentialOrgId: String?
    var lastOrgListAt: Date?
    var authState: AuthState
    var legacyHistoryKeyAssigned: Bool
    var recentEvents: [OrgEvent]   // newest first, capped at 50
}
```

`Profile` gains `var orgTracking: OrgTrackingState?` (plist, not a secret; decoded with
`(try? c.decodeIfPresent(...)) ?? nil` like `claudeUsage`, so a bad blob never fails the profile).

**Invariants**
1. `profile.claudeUsage` mirrors `lastUsage` of the active pair; widget, statusline, menu bar and
   auto-switch keep reading `claudeUsage` unchanged.
2. For profiles with a session key, `profile.organizationId == orgTracking.activeOrgId` after every
   classification (the account follows the active org, R4).
3. A sample is compared only with the previous sample **of the same pair** and the same baseline.
   That alone stops switches and moves from looking like resets (R6).
4. `historyKey` is assigned once and never reused for another org.

**History keying.** `UsageHistoryService` becomes keyed by a `String` key. The existing UUID API
delegates with `key = profileId.uuidString`, so the file name `usageHistory_<UUID>.json` and the
`lastSessionRecordTime_<UUID>` defaults keys are unchanged. New pairs use
`"<profileUUID>_<orgId>"` → `usageHistory_<profileUUID>_<orgId>.json`.

**Migration (R10).** Pure `OrgTrackingMigration.migrate(_ profile:, credentialOrgId:) -> Profile`,
run in `ProfileManager.loadProfiles()`, idempotent (only when `orgTracking == nil` and provider is
anthropic). First org id = `organizationId` ?? credential org ?? `unknownOrgId`. That first org gets
`historyKey = profile.id.uuidString` (the legacy file, so existing history attaches to it without
moving a file), `status = .active`, `lastUsage = claudeUsage`, name from `oauthAccountJSON`
`organizationName` when its `organizationUuid` matches, else "Team". `legacyHistoryKeyAssigned = true`.
An `unknownOrgId` pair is renamed in place (same `historyKey`, no event) once the real id is known.
Downgrade: an older build ignores the unknown `orgTracking` key and drops it on its next save; the
next upgrade migrates again; history files are untouched either way.

## 4. Org discovery and active-org detection

**Org list (R2).** Accounts with a claude.ai session key: `GET /api/organizations` every 15 min,
plus a forced refresh (debounced to once per 60 s per account) right after a non-Cloudflare
401/403/404 on any usage call of that account, and right after the credential org changes. A failed
or empty list never counts as evidence of removal. Orgs without the `chat` capability are ignored
(API-only orgs have no usage endpoint, `ClaudeAPIService+Types.swift:37-40`).

Accounts with OAuth credentials only cannot list orgs. Their only pair is the credential org.

**Seat fingerprint.** Org-list source: present non-empty values of `rate_limit_tier`, `raven_type`,
`billing_type`, joined by `|`; `capabilities` excluded (feature flags would cause false seat
changes). Credentials source (credential org only): `claudeAiOauth.rateLimitTier` and
`subscriptionType`. All fields optional. Fingerprints are compared only within the same source; a
source change re-baselines silently. If no field is present the fingerprint is `nil` and the
fallback detector (§5 rule S2) is used.

**Credential org (R3), first hit wins:**
1. The credentials JSON the profile's OAuth token comes from (`customKeychainServiceName` entry,
   else `cliCredentialsJSON`): root `organizationUuid`, else `claudeAiOauth.organizationUuid`.
2. If `ClaudeCodeSyncService.systemHoldsAccount(profile)`: live `.claude.json`
   `oauthAccount.organizationUuid`.
3. `profile.oauthAccountJSON` `organizationUuid` (snapshot from the last sync; can be stale).
4. None → unknown.

Read with a 60 s cache per profile (keychain reads spawn `security`). **Active org** =
credential org if known (and, when an org list exists, listed); else the user's stored
`organizationId`; else `preferredOrganization(list)`. Decision: the Claude Code login wins over a
manual pick, because that is the org the owner is consuming.

**Sample attribution.** Mirrors `AnthropicUsageProvider` priority: session key + `organizationId`
→ that org; else the credential org; else `unknownOrgId`. The org is captured in a ticket *before*
the fetch; if the credential org differs after the fetch, the sample is dropped (it could belong to
either org) and the next poll decides.

## 5. Event state machine

The classifier is a pure function, run per account each time a usage sample, an org list or an auth
signal arrives:

```
OrgEventClassifier.apply(observation, to: state, profileId:, now:) -> ClassificationResult
  ClassificationResult { state, events: [OrgEvent], acceptedSamples: [orgId: ClaudeUsage],
                         naturalResets: [(orgId, UsageWindow, previous: ClaudeUsage)] }
AccountObservation { now, orgList: [OrgListEntry]?, orgListAuthFailed, hasOrgListAccess,
                     credentialOrgId, credentialSeat, samples: [orgId: ClaudeUsage],
                     usageMembershipFailures: Set<orgId>, oauthUnauthorized, refreshRejected }
```

Rules run in this order. Precedence: **L > M > W > S > R**. A pair with an identity event (M, W, S)
in this run skips R, has its `pending` cleared and its baseline restarted (`baselineStartedAt = now`,
the new sample becomes the baseline).

**L — login loss (R8).**
- L1 `refreshRejected` → `needsLogin("Claude Code login was revoked")`, event `loginLost`.
- L2 `orgListAuthFailed` (non-Cloudflare 401/403 on the org list) → `needsLogin("claude.ai session expired")`.
- L3 OAuth-only account: `oauthUnauthorized` with a non-expired token on 2 consecutive polls, and
  the credential org did not change → `needsLogin("Log in again")`.
- While `needsLogin`, no pair of that account is polled with the dead credential; the UI shows
  "Log in again" instead of numbers. Leaves on the first successful sample or list, or when the
  credential changes (new session key / new refresh token) → `loginRestored` (no notification).
- Why: a 401 after an admin move is first checked against the org list (M); only a dead credential
  is login loss. One 401 is not enough (transient E3000 401s exist, `ClaudeAPIService.swift:444`).

**M — membership (R2, R4).** Only with a fresh, successful, non-empty list.
- New org not tracked → add as `idle` (`orgAdded`, silent). A `removed` org that reappears → `idle`,
  `orgRejoined` (silent).
- Org missing from the list is **confirmed removed** when: missing from 2 consecutive successful
  lists ≥ 60 s apart, **or** missing once and its usage call failed with 401/403/404 in the last
  10 min, **or** missing once and the credential org moved away from it in this run.
- Confirmed removed org A: status `removed`. Target B = credential org if live and ≠ A, else the
  live org with the newest `firstSeenAt` ≥ `A.lastSeenInListAt − 24 h`. B found and A was active →
  `adminMove(A → B)`, B becomes active, `organizationId = B`. Otherwise → `orgRemoved(A)`; if A was
  active the new active org is chosen as in §4.

**W — owner switch (R3).** Credential org changed from C₀ to C₁ (both known).
- With an org list: force a list refresh in the same run first. C₀ still listed → `ownerSwitch(C₀ → C₁)`;
  both stay tracked; C₁ active, C₀ idle. C₀ absent → handled by M as `adminMove` (no second event).
  List refresh failed → `ownerSwitch`.
- Without an org list (OAuth only): `orgChanged(C₀ → C₁)` ("Team changed: A → B"); C₀ becomes
  `readOnly` (no credential reaches it), history kept.
- C₁ not tracked yet → added first (no separate `orgAdded`).

**S — seat change (R5).**
- S1 fingerprint: same org, same source, both non-nil, values differ → `seatChange(inferred: false)`.
- S2 fallback, when the org has no fingerprint: compare the new sample with the pair's last sample,
  `resets_at` of both windows unchanged (≤ 5 min). Windows qualify when present in both samples and
  previous value ≥ 5 %. Candidate when ≥ 2 windows qualify (session, weekly; per-model weeklies
  count too), every ratio `new/prev` is outside [0.67, 1.5] in the same direction, the largest
  ratio ÷ smallest ≤ 1.3, the weekly change is ≥ 3 points, and no window dropped to ≤ 1 %. Stored as
  `pending(.seatInferred)`; confirmed when the next sample of the pair stays within ±25 % (or
  ±2 points) of the candidate → `seatChange(inferred: true)` ("Limit size changed — seat change
  likely"). Otherwise discarded.
- Why: a seat change rescales every window by the same limit ratio. Normal use moves the 5-hour
  value far faster than the weekly value, so equal ratios do not happen by use; a reset zeroes
  windows instead of scaling them. Limit: a single-window plan, or a seat change that also zeroes
  counters, cannot be told from an early reset without a tier field — it is then reported as an
  early reset. Documented in §12.

**R — early reset (R6).** Per window W present in both samples, same pair, same baseline:
- natural = `now ≥ prev.resetTime(W) − 5 min` (the window was due). Natural + `resets_at` moved
  > 5 min → `naturalResets` (history snapshot as today), no event.
- Candidate = not natural, `prev% ≥ 10`, `new% ≤ prev% × 0.5`, `prev% − new% ≥ 10` points.
  `resets_at` may be unchanged or moved. Stored as `pending(.earlyReset(W))`.
- Confirmed when the next sample of the pair still has `new% ≤ baseline% × 0.5` → `earlyReset`
  event + notification + reset snapshot in history. Bounced back → discarded (logged as glitch).
  Pending older than 30 min → discarded.
- Not natural, `resets_at` moved, no drop → baseline updated, no snapshot, no event (fixes today's
  spurious "reset" on a shifted time).
- Why these numbers: utilization only rises inside a window (fixed 5-hour and 7-day windows), so a
  real drop has no normal cause besides the due rollover, which is excluded. Rounding and per-model
  recalculation move values by 1–2 points; 10 points absolute plus a halving keeps those out. A
  missing window parses as 0 % (`ClaudeAPIService.swift:947-957`); the presence guard
  (`hasSessionLimit`/`hasWeeklyLimit`) and the confirmation sample turn one bad response into no
  event. A false alarm needs two consecutive bad responses of the same pair. Cost: the event comes
  one poll late (30 s active, 5 min idle).

**Collapsing (R11).** All rules compare only the last known state with the current one. Two changes
inside one interval show as one: A→B→C between polls is reported A→C; a seat change plus an early
reset is reported as the seat change; a move plus a seat change as the move. Org-list changes are
seen at the 15-min list interval unless a usage failure forces an earlier list.

## 6. Polling scheduler (R7)

| Job | Who | Interval | Requests per run |
|---|---|---|---|
| Active pair of profiles the menu bar loop shows | existing `MenuBarManager` loop | 30 s (unchanged) | session key: 4; OAuth: 1 (+1 fallback) |
| Active pair of other anthropic profiles | `MultiOrgPollScheduler` | 300 s | 1 (`fetchUsageOnly` or OAuth usage without refresh) |
| Idle pairs (status `idle`) | scheduler | 300 s | 1 (`fetchUsageOnly`) |
| Org list | scheduler | 900 s, forced ≤ 1/60 s | 1 |
| `removed`, `readOnly`, `needsLogin` | none | — | 0 |

- Concurrency: at most **4** scheduler requests in flight overall and **1** per account (no bursts
  on one session). The menu bar loop stays sequential, so the worst case is 5 in flight.
- Start-up spread: a job's first run is at a random offset in [0, interval) (org lists in [0, 10 s)),
  so N×M pairs do not fire together. The scheduler ticks every 15 s.
- Idle polls of other profiles use the OAuth token only when it is not expired, and never refresh it
  (refreshing would rotate a token another tool owns, #290, `AnthropicUsageProvider.swift:71-79`).
- **429 backoff, per account, shared by the loop and the scheduler:** k = consecutive 429s;
  delay = min(60 s × 2^(k−1), 15 min) × random[0.8, 1.2]; a `Retry-After` header wins when larger
  (capped at 1 h). During backoff the scheduler skips the account and the menu bar loop shows the
  cached value. Reset on the first success. A Messages-API 429 that carries usage headers is data,
  not a 429 (kept as today, `ClaudeAPIService.swift:687-696`).
- 5xx / network errors: retried at the normal interval, no backoff growth, never login loss.
  Cloudflare challenges (`.apiServiceUnavailable`) are ignored by every rule.

**Budget, per account per minute** (claude.ai limits are per account/session):
active 8.0 (session key, unchanged from today) + idle 0.2 × (M−1) + list 0.067.
M = 3 → 8.47/min (+6 % over today). OAuth-only active: 2.0/min. Fleet N = 4, M = 3 in multi
mode: 33.9/min from one IP, versus 32/min today for 4 selected profiles. In single mode the three
other accounts add 3 × (0.2 × 3 + 0.067) = 2.0/min. Worst forced lists: +1/min per failing
account, bounded by the 60 s debounce.

## 7. Component layout and contracts

| Component | File | Role |
|---|---|---|
| Models | `MultiTeam/OrgTrackingModels.swift` | §3 types, `OrgEvent.title/body/notifies` |
| Migration | `MultiTeam/OrgTrackingMigration.swift` | pure migrate, run by `ProfileManager.loadProfiles()` |
| Classifier | `MultiTeam/OrgEventClassifier.swift` | pure §5 |
| Credential parsing | `MultiTeam/CredentialOrgParser.swift` | pure: org id + seat from credentials / oauthAccount JSON strings |
| API | `ClaudeAPIService(+Types).swift` | optional tier fields, 404 → `.apiNotFound`, Retry-After, `fetchUsageOnly`, OAuth 429 mapping |
| Error signals | `MultiTeam/AppError+MultiTeam.swift` | `retryAfterSeconds`, `isMembershipFailure`, `isCloudflareChallenge` |
| Scheduler | `MultiTeam/MultiOrgPollScheduler.swift` | actor: due jobs, caps, backoff, injected clock/random |
| Coordinator | `MultiTeam/MultiTeamCoordinator.swift` | `@MainActor`; owns events, per-pair history and backoff for anthropic profiles |
| Wiring | `MenuBarManager`, `AnthropicUsageProvider`, `NotificationManager` | loop asks the coordinator, hands samples over |
| UI | `MultiTeam/RoomLeftRanking.swift`, `MenuBar/TeamsSectionView.swift`, `PopoverContentView`, `UsageHistoryView` | §8 |

Coordinator contract used by the menu bar loop:
```swift
func beginActivePoll(for profile: Profile) -> ActivePollTicket?   // nil: backing off or needsLogin → skip fetch
func ingestActive(_ ticket: ActivePollTicket, result: Result<ClaudeUsage, Error>, isCachedReading: Bool)
func reportRefreshRejected(profileId: UUID)
var onActiveOrgChanged: ((UUID) -> Void)?   // loop refreshes that profile at once
```
For anthropic profiles the loop no longer calls `checkAndRecordSessionReset/WeeklyReset` or the
periodic recorders: the coordinator records history per pair key. Codex profiles keep the old path.
Dependencies are injected through protocols (`OrgUsageFetching`, `CredentialOrgReading`,
`OrgTrackingStore`, `PairHistoryRecording`, `OrgEventNotifying`) so every rule is testable without
network or Keychain.

## 8. UI

- **Menu bar:** unchanged rendering; it shows the active profile's active pair (invariant 1). If
  that account is `needsLogin`, the existing credential-error state is set (`hasCredentialError`,
  message "Log in again"), so stale numbers are not shown as live.
- **Popover "Teams — most room left" section** (below the insights, shown when ≥ 2 pairs exist or
  any account needs login). One row per pair across all anthropic profiles: `account · team`, 5-hour
  left %, weekly left %, active dot, age when older than 15 min, "Log in again" instead of numbers
  for `needsLogin`, "Removed" rows hidden. Sort (pure `RoomLeftRanking`): usable pairs first, by
  headroom = min(5-hour left, weekly left) descending (weekly only when the plan has no 5-hour
  window), then weekly left descending, then name. Then stale (> 30 min) pairs, then `needsLogin`.
- **Recent team events:** the last 5 events across profiles under the list (title, relative time).
- **Notifications:** one per event with `notifies == true`, respecting the profile's
  `notificationSettings.enabled`; identifier `org-event-<event.id>`.
- **History view:** an org picker when the active profile has > 1 non-removed or removed-with-history
  pair; default = active pair; loads by `historyKey`.

## 9. Failure modes

| Failure | Behaviour |
|---|---|
| Org list fails / empty / Cloudflare | No membership change; retry at next interval |
| Usage 401/403/404 (non-CF) on one org | Forced list; M decides removal; else after 3 in a row the pair backs off to 15 min, no login loss |
| Token expired on a non-active profile | Pair shows last value with its age; not login loss (#290) |
| `invalid_grant` | `needsLogin` at once |
| 429 | Account backoff (§6) |
| Credential org unreadable | Active org = stored pick; switch detection off for that account until readable |
| Corrupt `orgTracking` blob | Decodes as nil → migration rebuilds from `organizationId`; history files intact |
| Sample arrives after an org change mid-fetch | Dropped (ticket check) |
| App asleep for hours | Due windows are natural resets; membership re-checked on the first list |
| Profile deleted | Scheduler jobs unregistered; history files left as today |

## 10. Test plan

Fixtures live in `Claude UsageTests/Fixtures/MultiTeamFixtures.swift` as Swift string literals (no
resource-bundle dependency). Shapes follow the parser and existing fixtures; they are not
production recordings (§12).

| Fixture | Content |
|---|---|
| `orgsAB`, `orgsB`, `orgsABC` | `/api/organizations` lists with `uuid`, `name`, `capabilities:["chat"]` |
| `orgsAStandard`, `orgsAPremium` | same org with `rate_limit_tier` differing |
| `orgsAPIOnly` | org without `chat` |
| `usage(s:w:sReset:wReset:)` | `/organizations/{id}/usage` body builder (`five_hour`, `seven_day`, `seven_day_opus`) |
| `usageNoFiveHour` | `five_hour: null` |
| `credentialsOrgA`, `credentialsOrgB`, `credentialsNoOrg` | credentials JSON (root `organizationUuid`, `claudeAiOauth.subscriptionType`) |
| `oauthAccountOrgA/B` | `.claude.json` `oauthAccount` |
| `http429RetryAfter` | status 429 + `Retry-After: 120` |
| `http401`, `http403Cloudflare`, `http404` | error responses |
| `legacyProfileJSON` | a profile plist entry without `orgTracking` |

| Suite | Cases (each one a test) |
|---|---|
| `OrgTrackingModelsTests` | Codable round trip; `Profile` decodes legacy JSON (nil tracking); corrupt blob → nil, profile intact; event titles |
| `OrgTrackingMigrationTests` | org from `organizationId`; from credential org; unknown; legacy history key; idempotent; non-anthropic untouched; usage carried over |
| `UsageHistoryKeyTests` | UUID API writes the same file as before; pair key file; per-key record times; temp directory |
| `CredentialOrgParserTests` | root vs nested org; missing org; seat from subscriptionType / rateLimitTier; garbage JSON |
| `OrgEventClassifierTests` | switch; switch without list (`orgChanged`); move (2 lists); move (1 list + 404); removal only; rejoin; seat change by fingerprint; source change silent; inferred seat change confirmed / discarded; early reset confirmed / bounced / stale pending; natural reset; shifted time without drop; missing window no event; identity event suppresses reset; login loss L1/L2/L3 and restore; collapse A→B→C; unknown org rename |
| `MultiOrgPollSchedulerTests` | intervals; start-up spread; global cap 4; 1 per account; backoff 60/120/240…900 with jitter bounds; Retry-After wins; reset on success; forced list debounce; unregister |
| `ClaudeAPIServiceMultiTeamTests` | `AccountInfo` with/without tier fields; status mapping 404/429/401/CF; `retryAfterSeconds`; OAuth 429 |
| `MultiTeamCoordinatorTests` | scenario runs with fakes: switch, move, seat change, early reset, 429, login loss, migration; ticket dropped on org change; `claudeUsage` mirror; `organizationId` follows; notifications only for `notifies` |
| `RoomLeftRankingTests` | ordering, weekly-only plans, stale and needsLogin placement, removed hidden |

All existing tests stay green: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS"`.

## 11. Trade-offs and rejected alternatives

| Choice | Why | Rejected |
|---|---|---|
| Keep the menu bar loop as the active-pair poller; coordinator handles the rest | Zero change to the subtle auth chain (#268, #290, #355) and the 390 tests around it | Coordinator owns all polling: cleaner on paper, rewrites both refresh paths at once |
| State inside `Profile` (plist) | One store, saved with the profile, migrates with it | Separate store: second source of truth to keep in sync |
| Org list only via session key | It is the only list endpoint the code knows | `oauth/profile` endpoint: no recorded response, undocumented |
| Two-sample confirmation | Rare false alarms | Single sample: alarms on every glitch |
| Credential org beats manual pick | Matches what the owner consumes (R3) | Keep manual pick: shows the wrong team after a switch |
| Idle pairs usage-only | 1 request instead of 4 | Full fetch for every pair: 4× budget |
| Fixtures as Swift literals | No bundle-resource wiring | JSON resources: synchronized-group resource handling unverified |
| Optional tier fields + scaling fallback | Works whether or not the server sends a tier | Require a tier field: R5 would silently fail |

## 12. Known limits

- **R11:** changes inside one interval collapse to the final state (§5).
- Endpoints are undocumented (`/api/organizations`, `/organizations/{id}/usage`, `/api/oauth/usage`)
  and can change without notice; every new field is optional and parsing degrades to "no event".
- No production recording of an org-list or usage response with tier fields exists in the repo;
  fixtures are modelled on the parser. **The owner should capture one redacted
  `/api/organizations` response per seat type** (Settings → Debug network log) and add it as a
  fixture; if a tier field appears, S1 replaces the S2 fallback automatically.
- OAuth-only accounts see only the login's org; switch vs move cannot be told apart (`orgChanged`),
  and the old org becomes read-only.
- A seat change that also zeroes counters, or happens on a single-window plan, is reported as an
  early reset when no tier field exists.
- Early-reset events come one poll late (confirmation).
- Usage limits are percentages; absolute limits are unknown, so "limit size" is inferred from ratios.
