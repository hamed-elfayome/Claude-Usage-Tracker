# AI Usage Tracker — Design Spec

> Forked from [hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker). Rebranded and extended to track usage across Claude, OpenAI API, and Codex.

## Overview

A native macOS menu bar app that tracks AI usage across multiple providers and accounts. The status bar acts as a quiet alert system — only surfacing services approaching their limits. The dropdown popover shows the full dashboard with per-account, per-model breakdowns.

## Goals

1. Track Claude Max subscription usage per account with Opus-first model breakdown
2. Track Claude API and OpenAI API billing/spend separately
3. Track Codex CLI usage via probe requests and rate-limit headers
4. Smart status bar that only shows what needs attention
5. Rebrand to provider-neutral "AI Usage Tracker"

## Service Types

The app tracks 4 independent service types. Each instance is a "service" with its own credentials, display name, and usage data.

### Claude Max

- **Auth:** Session key, CLI OAuth (`~/.claude/` credentials), or browser sign-in (WKWebView)
- **Data source:** `https://claude.ai/api/organizations/{orgId}/usage`
- **Metrics:** Session %, weekly %, per-model breakdown (Opus, Sonnet)
- **Display:** Opus % is the primary metric shown in status bar and dropdown. Sonnet shown as secondary bar in dropdown. Session/weekly shown as fine print.
- **Multiple accounts supported:** Each org (Private, Creed Media, Creed Media Team, etc.) is a separate service instance.

### Claude API

- **Auth:** Console session key
- **Data source:** `https://console.anthropic.com/api/organizations/{orgId}/current_spend`, `/prepaid/credits`, `/usage_cost`
- **Metrics:** Monthly spend ($), credits remaining, per-model cost breakdown, daily breakdown
- **Display:** Dollar amount in dropdown. Appears in status bar when spend exceeds configurable % of budget.

### OpenAI API

- **Auth:** Admin API key (stored in Keychain)
- **Data source:**
  - `GET /v1/organization/costs` — daily spend buckets (summed for monthly total)
  - `GET /v1/organization/usage/completions` — token counts per model
- **Metrics:** Monthly spend ($), daily spend, per-model token usage
- **Display:** Dollar amount in dropdown. Same budget-% threshold logic as Claude API.

### Codex

- **Auth:** Reads `~/.codex/auth.json` for credentials, or manual API key entry
- **Data source:** Lightweight probe request (`POST /v1/chat/completions` with `max_tokens: 1` to minimize cost) to OpenAI API; usage extracted from response headers:
  - `x-ratelimit-limit-requests` / `x-ratelimit-remaining-requests`
  - `x-ratelimit-limit-tokens` / `x-ratelimit-remaining-tokens`
  - `x-ratelimit-reset-requests` / `x-ratelimit-reset-tokens`
- **Metrics:** Request % remaining, token % remaining
- **Display:** Request % as primary metric (like Opus-first for Claude). Token % as secondary.
- **Limitation:** OpenAI does not expose Codex subscription quota via API. Probe-based tracking reflects API-level rate limits, not exact ChatGPT subscription quota. This is the best available approach until OpenAI ships a dedicated endpoint.

## Architecture

### Core Model: Service

Replaces the existing `Profile` model. Each service is an independent tracked account.

```
struct Service: Codable, Identifiable {
    let id: UUID
    var type: ServiceType          // .claudeMax, .claudeAPI, .openaiAPI, .codex
    var displayName: String        // "Private", "Creed Media", "Codex CLI"
    var isEnabled: Bool
    
    // Credentials (type-specific, stored in Keychain)
    var credentialRef: String      // Keychain reference
    
    // Usage data
    var lastUsage: ServiceUsage?
    var lastUpdated: Date?
    
    // Display settings
    var primaryModel: String?      // "opus" for Claude Max, nil for others
    var notificationThresholds: [Double]  // [0.75, 0.90, 0.95]
    var refreshInterval: TimeInterval?    // Override global, nil = use default
}
```

### Protocol: UsageProvider

All 4 service types implement this. The refresh coordinator is provider-agnostic.

```
protocol UsageProvider {
    var serviceType: ServiceType { get }
    var displayName: String { get }
    func fetchUsage() async throws -> ServiceUsage
    func validateCredentials() async throws -> Bool
}
```

Implementations:
- `ClaudeMaxProvider` — wraps existing `ClaudeAPIService` logic
- `ClaudeAPIProvider` — wraps existing Console API logic
- `OpenAIAPIProvider` — new, calls OpenAI Usage/Costs endpoints
- `CodexProvider` — new, probe request + header parsing

### Unified Usage Model

```
struct ServiceUsage: Codable {
    // Percentage-based metrics (Claude Max, Codex)
    var primaryPercentage: Double?      // Opus % or request %
    var secondaryPercentage: Double?    // Sonnet % or token %
    var overallPercentage: Double?      // Combined/session
    
    // Dollar-based metrics (API billing)
    var currentSpend: Double?
    var spendLimit: Double?             // Budget or credits
    var dailySpend: Double?
    
    // Time
    var resetTime: Date?
    var periodLabel: String?            // "5h window", "Apr 30", etc.
    
    // Model breakdown (optional detail)
    var modelBreakdown: [ModelUsage]?   // e.g. [{model: "opus", percentage: 0.92}, {model: "sonnet", percentage: 0.35}]
    
    // Raw data for history
    var rawData: [String: Double]?
}
```

### Refresh Cycle

- `UsageRefreshCoordinator` holds an array of `UsageProvider` instances
- All services polled in parallel every 30s (configurable per-service)
- Each service refreshes independently — if one fails, others continue
- After each refresh, status bar thresholds re-evaluated
- Wake-from-sleep triggers immediate refresh (preserved from original)
- Retry logic: 3 attempts with exponential backoff (preserved from original)

## UI Design

### Smart Status Bar

The status bar adapts based on service states:

**State 1 — All clear (nothing above threshold):**
```
◉ AI
```
Calm green icon. Everything is fine.

**State 2 — Warning (services between 60-89%):**
```
Private opus 78%  |  Team opus 91%
```
Only services above threshold appear. Yellow for warning range.

**State 3 — Critical (services above 90%):**
```
Team opus 98%  |  Codex 72%
```
Red for critical. Most urgent items shown first.

**Threshold logic:**
- Below 60% → hidden from status bar
- 60-89% → yellow
- 90%+ → red
- Nothing above 60% → calm "◉ AI" icon
- API billing: uses % of budget (configurable spend limit) instead of usage %
- Thresholds configurable in settings
- Max items in status bar configurable to prevent overcrowding (default: 4)

### Dropdown Popover

Always shows all services, organized in 3 sections:

**Claude Max section:**
- Each account listed by display name
- Opus bar: prominent, colored by threshold (green/yellow/red)
- Sonnet bar: secondary, smaller, dimmed
- Fine print: Session % · Weekly %
- Reset time per account

**API Billing section:**
- Claude API: monthly spend, credits remaining, reset date
- OpenAI API: monthly spend, daily spend, reset date

**Codex section:**
- Requests bar: primary, colored by threshold
- Tokens bar: secondary, dimmed
- Rolling window indicator

**Footer:** Settings, History, Quit

### Settings

**Add Service flow:**
1. Pick service type (Claude Max / Claude API / OpenAI API / Codex)
2. Enter credentials (type-specific auth UI)
3. Name it (auto-suggested from org name when possible)
4. Validate connection
5. Save

**Per-service settings:**
- Custom display name
- Primary model selection (Claude Max only, defaults to Opus)
- Show/hide in dropdown
- Individual refresh interval override
- Notification thresholds

**Global settings:**
- Status bar appearance threshold (default 60%)
- Color mode (multi-color / monochrome / single color)
- Icon style for "all clear" state
- Max status bar items
- Launch at login
- Global keyboard shortcut
- Language (9 languages preserved)

### Preserved Features

- Usage history charts (extended to all service types)
- Notifications at configurable thresholds
- Terminal statusline integration
- Network debug view
- Sparkle auto-updates
- Keychain credential storage
- Wake-from-sleep refresh
- Headless mode for Remote Desktop

### Removed/Replaced

- Multi-profile system → replaced by flat service list
- Profile switching → not needed, all services always active
- Auto-switch profile → replaced by smart status bar
- Profile display mode (single/multi) → always show all enabled services

## Migration

Existing Claude Usage Tracker users who update:
- Each existing profile auto-converts to a Claude Max service
- Credentials transferred from profile Keychain entries to service Keychain entries
- Display names preserved (profile name → service display name)
- Settings mapped: icon config → service display settings
- API billing profiles → separate Claude API service instances
- One-time migration on first launch of new version

## File Changes Summary

### New Files

| File | Purpose |
|---|---|
| `Service.swift` | Service model replacing Profile |
| `ServiceUsage.swift` | Unified usage data model |
| `ServiceType.swift` | Enum for 4 service types |
| `UsageProviderProtocol.swift` | Protocol all providers implement |
| `OpenAIAPIProvider.swift` | OpenAI API usage fetching |
| `CodexProvider.swift` | Codex probe + header parsing |
| `ClaudeMaxProvider.swift` | Wraps existing Claude API logic |
| `ClaudeAPIBillingProvider.swift` | Wraps existing Console API logic |
| `ServiceManager.swift` | Manages service list (replaces ProfileManager) |
| `SmartStatusBarRenderer.swift` | Threshold-based status bar logic |
| `AddServiceView.swift` | Settings UI for adding services |
| `ServiceSettingsView.swift` | Per-service settings |
| `OpenAICredentialView.swift` | OpenAI API key entry UI |
| `CodexCredentialView.swift` | Codex auth UI |
| `MigrationService.swift` | Profile → Service migration |

### Modified Files

| File | Changes |
|---|---|
| `ClaudeUsageTrackerApp.swift` | Rename to AIUsageTrackerApp, init ServiceManager |
| `MenuBarManager.swift` | Use ServiceManager + SmartStatusBarRenderer |
| `MenuBarIconRenderer.swift` | Support threshold-based visibility |
| `PopoverContentView.swift` | 3-section layout (Claude Max / API / Codex) |
| `UsageRefreshCoordinator.swift` | Poll array of UsageProviders |
| `DataStore.swift` | Save/load per-service usage |
| `SettingsView.swift` | Service management UI |
| `NotificationManager.swift` | Per-service threshold notifications |
| `UsageHistoryService.swift` | History for all service types |

### Unchanged

- `APIServiceProtocol.swift` (still used internally by Claude providers)
- `StorageProvider.swift`
- Core refresh/notification infrastructure
- Localization framework
- Sparkle update system
- Terminal statusline (extended, not replaced)
