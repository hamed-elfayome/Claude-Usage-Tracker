# AI Usage Tracker — Design Spec (v2)

> Forked from [hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker). Rebranded and extended to track usage across Claude, OpenAI API, and Codex.
>
> **v2 note:** Revised after Codex code review that identified 10 issues with v1's architecture, data models, and migration plan. Key change: evolve Profile rather than replace it.

## Overview

A native macOS menu bar app that tracks AI usage across multiple providers and accounts. The status bar acts as a quiet alert system — only surfacing services approaching their limits. The dropdown popover shows the full dashboard with per-account, per-model breakdowns.

## Goals

1. Track Claude Max subscription usage per account with Opus-first model breakdown
2. Track Claude API and OpenAI API billing/spend separately
3. Track Codex CLI usage via API key probe requests and rate-limit headers
4. Smart status bar that only shows what needs attention
5. Rebrand to provider-neutral "AI Usage Tracker"

## Provider Types

The app tracks 4 provider types. Each is backed by an extended Profile.

### Claude Max

- **Auth:** Session key, CLI OAuth (`~/.claude/` credentials), or browser sign-in (WKWebView) — all 3 methods preserved as-is
- **Data source:** `https://claude.ai/api/organizations/{orgId}/usage`
- **Metrics:** Session %, weekly %, per-model breakdown (Opus, Sonnet)
- **Display:** Opus % is the primary metric shown in status bar and dropdown. Sonnet shown as secondary bar in dropdown. Session/weekly shown as fine print.
- **Multiple accounts supported:** Each org (Private, Creed Media, Creed Media Team) is a separate Profile.
- **Refresh interval:** 30s (preserved from original)

### Claude API

- **Auth:** Console session key — preserved as-is
- **Data source:** `https://console.anthropic.com/api/organizations/{orgId}/current_spend`, `/prepaid/credits`, `/usage_cost`
- **Metrics:** Monthly spend (cents, with currency), credits remaining, per-model cost breakdown, daily breakdown, per-key source breakdown
- **Display:** Dollar amount in dropdown. Appears in status bar when spend exceeds configurable % of a user-set budget (budget lives in Profile settings, NOT fetched from API).
- **Refresh interval:** 5 minutes (cost data doesn't change fast)

### OpenAI API

- **Auth:** OpenAI Admin API key (NOT a regular project key — only admin keys can access org-level usage/cost endpoints). Stored in Profile credentials alongside existing Claude credentials.
- **Data source:**
  - `GET /v1/organization/costs?bucket_width=1d&start_time=...&end_time=...` — daily spend buckets. Must sum buckets client-side for monthly total. Groups by `project_id` and `line_item`, NOT by model. Paginated (follow `next_page` cursor).
  - `GET /v1/organization/usage/completions?bucket_width=1d&start_time=...&end_time=...&group_by[]=model` — token counts per model. Must pass `group_by[]=model` explicitly or model field can be null. Paginated.
- **Metrics:** Monthly spend (cents, with currency), daily spend, per-model token usage
- **Display:** Dollar amount in dropdown. Same user-set budget threshold logic as Claude API.
- **Refresh interval:** 5 minutes (cost data doesn't change fast, endpoints are paginated)

### Codex

- **Auth:** Requires a separate OpenAI API key (NOT the ChatGPT session tokens from `~/.codex/auth.json`). ChatGPT sign-in and API-key sign-in are completely separate auth paths in OpenAI's system. ChatGPT access tokens cannot be used to call `/v1/chat/completions`.
- **Data source:** Lightweight probe request (`POST /v1/chat/completions` with `max_tokens: 1`, cheapest model) using the user's OpenAI API key. Usage extracted from response headers:
  - `x-ratelimit-limit-requests` / `x-ratelimit-remaining-requests`
  - `x-ratelimit-limit-tokens` / `x-ratelimit-remaining-tokens`
  - `x-ratelimit-reset-requests` / `x-ratelimit-reset-tokens`
- **Metrics:** Request % remaining, token % remaining
- **Display:** Request % as primary metric. Token % as secondary.
- **Limitation:** This tracks API key rate limits, NOT ChatGPT subscription Codex quota. OpenAI does not expose Codex subscription quota via any public API. The UI must clearly label this as "OpenAI API rate limits" to avoid confusion. If/when OpenAI ships a Codex quota endpoint, this can be updated.
- **Refresh interval:** 60s (each probe consumes 1 request + minimal tokens from the monitored budget — balance visibility vs overhead)
- **Cost consideration:** Each probe costs ~1 token of input/output. At 60s intervals that's ~1440 probes/day. Negligible cost but it does consume rate limit quota.

## Architecture

### Strategy: Evolve Profile, Don't Replace It

Codex review finding #1 was clear: Profile is not just a data model. It's the account boundary, runtime switch point, usage container, notification container, refresh config, and UI config. `ClaudeAPIService`, `ProfileManager`, `MenuBarManager`, and `UsageRefreshCoordinator` all assume active-profile semantics. Replacing it with a flat service list would be a full app-state rewrite.

**Instead:** Extend Profile with a `providerType` field and optional OpenAI credential/usage containers. This preserves ALL existing behavior while adding new providers.

### Extended Profile Model

```swift
// New enum
enum ProfileProviderType: String, Codable {
    case claudeMax      // Existing behavior
    case claudeAPI      // Existing behavior (API Console)
    case openaiAPI      // New
    case codex          // New
}

// Profile.swift — additions only (all existing fields preserved)
struct Profile: Codable, Identifiable, Equatable {
    // === ALL EXISTING FIELDS PRESERVED AS-IS ===
    let id: UUID
    var name: String

    // Existing Claude credentials (unchanged)
    var claudeSessionKey: String?
    var organizationId: String?
    var apiSessionKey: String?
    var apiOrganizationId: String?
    var apiSessionKeyExpiry: Date?
    var cliCredentialsJSON: String?

    // Existing CLI metadata (unchanged)
    var hasCliAccount: Bool
    var cliAccountSyncedAt: Date?

    // Existing usage data (unchanged)
    var claudeUsage: ClaudeUsage?
    var apiUsage: APIUsage?

    // Existing settings (ALL unchanged)
    var iconConfig: MenuBarIconConfiguration
    var refreshInterval: TimeInterval
    var autoStartSessionEnabled: Bool
    var checkOverageLimitEnabled: Bool
    var notificationSettings: NotificationSettings  // Full struct preserved
    var isSelectedForDisplay: Bool
    var createdAt: Date
    var lastUsedAt: Date

    // === NEW FIELDS ===
    var providerType: ProfileProviderType   // Defaults to .claudeMax for migration
    var primaryModel: String?               // "opus", "sonnet", nil — for Opus-first display

    // OpenAI credentials (only used when providerType is .openaiAPI or .codex)
    var openaiAdminKey: String?             // Admin API key for org-level endpoints
    var openaiApiKey: String?               // Regular API key for probe requests
    var openaiOrganizationId: String?

    // OpenAI usage data
    var openaiUsage: OpenAIUsage?           // New strongly-typed model
    var codexUsage: CodexUsage?             // New strongly-typed model

    // Budget settings (user-configured, not fetched)
    var spendBudgetCents: Int?              // Monthly budget for API billing threshold alerts
    var spendBudgetCurrency: String?
}
```

**Migration safety:** New fields use optionals with `decodeIfPresent` so existing `profiles_v3` UserDefaults data decodes without errors. `providerType` defaults to `.claudeMax` when absent.

### New Strongly-Typed Usage Models

**Codex review findings #5 was right:** a generic `ServiceUsage` loses the rich typing that already exists. Keep `ClaudeUsage` and `APIUsage` as-is. Add new models alongside:

```swift
/// OpenAI API billing data — mirrors APIUsage structure but for OpenAI
struct OpenAIUsage: Codable, Equatable {
    let currentSpendCents: Int              // Summed from daily cost buckets
    let currency: String                    // "usd"
    let resetsAt: Date                      // Billing cycle end
    let dailyCostCents: [String: Double]    // "2026-04-03" -> cents
    let tokensByModel: [String: OpenAIModelTokens]?  // Per-model breakdown
    let lastUpdated: Date

    var usedAmount: Double { Double(currentSpendCents) / 100.0 }

    struct OpenAIModelTokens: Codable, Equatable {
        let inputTokens: Int
        let outputTokens: Int
        let cachedTokens: Int
    }
}

/// Codex rate-limit data from probe response headers
struct CodexUsage: Codable, Equatable {
    let requestLimit: Int                   // x-ratelimit-limit-requests
    let requestsRemaining: Int              // x-ratelimit-remaining-requests
    let tokenLimit: Int                     // x-ratelimit-limit-tokens
    let tokensRemaining: Int                // x-ratelimit-remaining-tokens
    let requestResetTime: Date              // x-ratelimit-reset-requests (parsed)
    let tokenResetTime: Date                // x-ratelimit-reset-tokens (parsed)
    let lastUpdated: Date

    var requestPercentageUsed: Double {
        guard requestLimit > 0 else { return 0 }
        return Double(requestLimit - requestsRemaining) / Double(requestLimit) * 100.0
    }

    var tokenPercentageUsed: Double {
        guard tokenLimit > 0 else { return 0 }
        return Double(tokenLimit - tokensRemaining) / Double(tokenLimit) * 100.0
    }
}
```

### Provider Protocol

```swift
protocol UsageProvider {
    var providerType: ProfileProviderType { get }
    var profileId: UUID { get }             // Stable identity for persistence/history/notifications
    var displayName: String { get }

    /// Fetch fresh usage data. Returns updated Profile fields (caller merges into Profile).
    func fetchUsage(for profile: Profile) async throws -> ProfileUsageUpdate

    /// Validate that credentials work before saving.
    func validateCredentials(for profile: Profile) async throws -> Bool
}

/// Type-safe update container — each provider sets only its relevant fields
struct ProfileUsageUpdate {
    var claudeUsage: ClaudeUsage?
    var apiUsage: APIUsage?
    var openaiUsage: OpenAIUsage?
    var codexUsage: CodexUsage?
}
```

**Implementations:**
- `ClaudeMaxProvider` — wraps existing `ClaudeAPIService` logic unchanged
- `ClaudeAPIBillingProvider` — wraps existing Console API logic unchanged
- `OpenAIAPIProvider` — new, calls OpenAI org Usage/Costs endpoints with Admin key, handles pagination and `group_by`
- `CodexProvider` — new, probe request + header parsing using regular API key

### Refresh Cycle

**Codex finding #9:** 30s for everything is wasteful. Variable rates per provider type:

| Provider | Default Interval | Reason |
|----------|-----------------|--------|
| Claude Max | 30s | Real-time session tracking (preserved from original) |
| Claude API | 5 min | Cost data updates slowly |
| OpenAI API | 5 min | Cost data updates slowly, endpoints are paginated |
| Codex | 60s | Each probe costs 1 request from monitored budget |

- `UsageRefreshCoordinator` tracks per-profile timers (not one global timer)
- Each profile refreshes independently — if one fails, others continue
- After each refresh, status bar thresholds re-evaluated
- Wake-from-sleep triggers immediate refresh for all profiles (preserved)
- Retry logic: 3 attempts with exponential backoff (preserved)
- Per-profile override still available in settings

### Credential Storage

**Codex finding #2:** Current credentials are stored in UserDefaults as part of the `profiles_v3` JSON blob via `ProfileStore.saveProfiles()`, NOT in Keychain. Session keys, API keys, and CLI OAuth tokens are all serialized directly into the encoded Profile.

**For OpenAI credentials:** Follow the same pattern for now (add `openaiAdminKey` and `openaiApiKey` as Profile fields, serialized into `profiles_v3`). This is consistent with existing behavior.

**Future consideration:** Moving secrets to Keychain is a good idea but is a separate initiative that should apply to ALL credentials (Claude + OpenAI) at once. Not in scope for this feature.

## UI Design

### Smart Status Bar

The status bar adapts based on profile states:

**State 1 — All clear (nothing above threshold):**
```
◉ AI
```
Calm green icon. Everything is fine.

**State 2 — Warning (profiles between 60-89%):**
```
Private opus 78%  |  Team opus 91%
```
Only profiles above threshold appear. Yellow for warning range.

**State 3 — Critical (profiles above 90%):**
```
Team opus 98%  |  Codex 72%
```
Red for critical. Most urgent items shown first.

**Threshold logic:**
- Below 60% → hidden from status bar
- 60-89% → yellow
- 90%+ → red
- Nothing above 60% → calm "◉ AI" icon
- API billing profiles: uses % of user-configured spend budget. If no budget set, never appears in status bar (only in dropdown).
- Thresholds configurable in settings
- Max items in status bar: configurable, default 4
- Priority order: highest percentage first, then by provider type (Claude Max > Codex > APIs)

**Which percentage drives the status bar for Claude Max profiles:**
- Uses `primaryModel` setting to determine which model % to show
- Default: Opus % (since user primarily uses Opus)
- If Opus is at 92% but overall is 70%, status bar shows 92%

### Dropdown Popover

Always shows all enabled profiles, organized in 3 sections:

**Claude Max section:**
- Each account listed by profile display name
- Opus bar: prominent, colored by threshold (green/yellow/red)
- Sonnet bar: secondary, smaller, dimmed
- Fine print: Session % · Weekly %
- Reset time per account

**API Billing section:**
- Claude API: monthly spend, credits remaining, reset date, per-key source breakdown (preserved)
- OpenAI API: monthly spend, daily spend, reset date

**Codex section:**
- Requests bar: primary, colored by threshold
- Tokens bar: secondary, dimmed
- Reset time indicators
- Label: "OpenAI API Rate Limits" (NOT "Codex quota" — to be honest about what we're tracking)

**Footer:** Settings, History, Quit

### Settings

**Add Profile flow (extended):**
1. Pick provider type (Claude Max / Claude API / OpenAI API / Codex)
2. Enter credentials (provider-specific auth UI):
   - Claude Max: existing 3 auth methods (session key, browser, CLI)
   - Claude API: existing Console session key flow
   - OpenAI API: Admin API key input with format validation (`sk-admin-...`)
   - Codex: Regular OpenAI API key input (`sk-...`)
3. Name it (auto-suggested from org name when possible)
4. Validate connection (test the credentials against real endpoints)
5. Save

**Per-profile settings (ALL existing settings preserved + new ones):**
- Custom display name
- Primary model selection (Claude Max only, defaults to Opus) — NEW
- Spend budget for alerts (API profiles only) — NEW
- Show/hide in dropdown (maps to existing `isSelectedForDisplay`)
- Refresh interval override (maps to existing `refreshInterval`)
- Notification settings: full `NotificationSettings` struct preserved (enabled flags, per-threshold toggles, sound config, custom thresholds)
- Auto-start session (Claude Max only, preserved)
- Check overage limit (Claude Max only, preserved)

**Global settings (unchanged):**
- Color mode (multi-color / monochrome / single color)
- Status bar appearance threshold (default 60%) — NEW
- Max status bar items (default 4) — NEW
- Launch at login
- Global keyboard shortcut
- Language (9 languages preserved)

### Preserved Features (ALL of these work exactly as before)

- Usage history charts (extended with new provider-specific history)
- Notifications with full `NotificationSettings` (enabled, per-threshold, sound, custom)
- Terminal statusline integration
- Network debug view
- Sparkle auto-updates
- Wake-from-sleep refresh with smart debouncing
- Headless mode for Remote Desktop
- Multi-profile menu bar display
- CLI account sync metadata (`hasCliAccount`, `cliAccountSyncedAt`)
- `createdAt` and `lastUsedAt` tracking
- `autoStartSessionEnabled` and `checkOverageLimitEnabled`
- Profile icon configuration (`MenuBarIconConfiguration`)

## Migration

### Existing Users (Profile → Extended Profile)

**Codex finding #2:** Credentials live in `profiles_v3` UserDefaults blob, not Keychain.

Migration is additive — we only add new optional fields to Profile. Existing data decodes unchanged:

1. **On first launch of new version:** `ProfileStore.loadProfiles()` runs as usual
2. **New fields decode as nil:** `providerType`, `primaryModel`, `openaiAdminKey`, `openaiApiKey`, `openaiUsage`, `codexUsage`, `spendBudgetCents` all decode as `nil` via `decodeIfPresent`
3. **Default provider type:** If `providerType` is nil, treat as `.claudeMax` (existing behavior)
4. **Default primary model:** If `primaryModel` is nil, default to `"opus"`
5. **No credential transfer needed:** Existing credentials stay exactly where they are
6. **No key schema change:** UserDefaults key remains `profiles_v3`
7. **Bump storage version:** Change key to `profiles_v4` on first migration to prevent downgrade data loss. Old `profiles_v3` preserved as backup.

**This is the safest possible migration: existing data is structurally preserved, new fields are additive optionals.**

### Usage History

**Codex finding #7:** History is keyed by `profileId` with Claude-specific snapshot types.

- Existing Claude Max history: **unchanged**. Same profileId, same snapshot types.
- New OpenAI/Codex profiles get new UUIDs → new history keys → no collision.
- History snapshots extended with new types:
  - `openaiCostSnapshot` — daily cost recording for OpenAI
  - `codexRateLimitSnapshot` — periodic rate-limit state capture
- These are stored alongside existing `sessionSnapshot`, `weeklySnapshot`, `apiCostSnapshot` without affecting them.

### Notifications

**Codex finding #8:** Current notification logic dedupes by `profileName` and uses full `NotificationSettings`.

- `NotificationSettings` struct: **preserved exactly** (enabled, threshold75/90/95, soundName, customThresholds)
- `NotificationManager` dedup logic: continues using `profile.name` — works because new OpenAI/Codex profiles have distinct names
- New provider types trigger notifications using the same threshold system:
  - Claude Max: Opus % or session % (based on `primaryModel` setting)
  - Claude API / OpenAI API: spend % of budget (requires `spendBudgetCents` to be set)
  - Codex: request % used

## File Changes Summary

### New Files

| File | Purpose |
|---|---|
| `ProfileProviderType.swift` | Enum: `.claudeMax`, `.claudeAPI`, `.openaiAPI`, `.codex` |
| `OpenAIUsage.swift` | Strongly-typed OpenAI billing data model |
| `CodexUsage.swift` | Strongly-typed rate-limit data model |
| `OpenAIAPIProvider.swift` | Fetches from OpenAI org Usage/Costs endpoints (Admin key, pagination, group_by) |
| `CodexProvider.swift` | Probe request + response header parsing |
| `SmartStatusBarRenderer.swift` | Threshold-based status bar visibility logic |
| `AddProfileProviderView.swift` | Provider type selection in Add Profile flow |
| `OpenAICredentialView.swift` | Admin API key + regular API key entry UI |
| `CodexCredentialView.swift` | OpenAI API key entry for Codex probe |

### Modified Files

| File | Changes |
|---|---|
| `Profile.swift` | Add `providerType`, `primaryModel`, OpenAI credential/usage fields, `spendBudgetCents` |
| `ClaudeUsageTrackerApp.swift` | Rename to `AIUsageTrackerApp`, update bundle identifiers |
| `MenuBarManager.swift` | Smart status bar threshold logic, multi-provider display |
| `MenuBarIconRenderer.swift` | Render OpenAI/Codex metrics alongside Claude |
| `PopoverContentView.swift` | 3-section layout (Claude Max / API Billing / Codex) |
| `UsageRefreshCoordinator.swift` | Per-profile variable refresh intervals based on `providerType` |
| `DataStore.swift` | Save/load `OpenAIUsage` and `CodexUsage` per profile |
| `ProfileStore.swift` | Storage version bump `profiles_v3` → `profiles_v4` with backward-compatible decoding |
| `ProfileManager.swift` | Factory methods for creating OpenAI/Codex profiles |
| `SettingsView.swift` | Provider-aware profile creation and per-profile settings |
| `NotificationManager.swift` | Provider-aware threshold calculations |
| `UsageHistoryService.swift` | New snapshot types for OpenAI cost and Codex rate limits |

### Unchanged

- `ClaudeAPIService.swift` — still used by ClaudeMax and ClaudeAPI providers internally
- `ClaudeAPIService+ConsoleAPI.swift` — Console API logic untouched
- `ClaudeAPIService+Types.swift` — response types untouched
- `APIServiceProtocol.swift` — still used internally by Claude providers
- `StorageProvider.swift` — no changes needed
- `ClaudeUsage.swift` — model preserved exactly
- `APIUsage.swift` — model preserved exactly
- `NotificationSettings.swift` — struct preserved exactly
- `MenuBarIconConfiguration.swift` — preserved
- `ProfileCredentials.swift` — preserved
- Localization framework — preserved (add new strings for OpenAI/Codex UI)
- Sparkle update system — preserved
- Terminal statusline — preserved (extended with new provider info)
- Keychain infrastructure — preserved

## Codex Review Status

v2 of this spec addresses all 10 findings from the Codex review:

| # | Finding | Resolution |
|---|---------|------------|
| 1 | Service is wrong top-level replacement | Evolve Profile instead, preserve all runtime semantics |
| 2 | Migration credentials not in Keychain | Corrected: credentials are in UserDefaults `profiles_v3` blob. Migration is additive optionals only. |
| 3 | Codex probe doesn't track subscription quota | Corrected: requires separate API key, clearly labeled as "API rate limits" not "Codex quota" |
| 4 | UsageProvider underspecified | Added `profileId` for stable identity, `ProfileUsageUpdate` for type-safe updates |
| 5 | ServiceUsage badly typed | Dropped generic model. Keep `ClaudeUsage`/`APIUsage`, add `OpenAIUsage`/`CodexUsage` alongside |
| 6 | OpenAI endpoints need Admin keys | Specified Admin API key requirement, `group_by` params, pagination handling |
| 7 | History migration not specified | Detailed: existing history untouched, new profiles get new UUIDs + new snapshot types |
| 8 | Notification migration underspecified | Full `NotificationSettings` preserved, provider-aware threshold logic added |
| 9 | Refresh plan naive | Variable intervals: 30s Claude Max, 60s Codex, 5min APIs |
| 10 | Service drops critical Profile fields | ALL Profile fields preserved. Extension only, no deletions. |
