# AI Usage Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Claude Usage Tracker macOS menu bar app to support OpenAI API billing and Codex rate-limit tracking, with a smart status bar that surfaces only what needs attention.

**Architecture:** Evolve the existing Profile model with new optional fields for OpenAI credentials and usage data. Add two new provider implementations (OpenAI API, Codex) alongside the existing Claude providers. The status bar becomes threshold-aware, only showing profiles approaching limits.

**Tech Stack:** Swift 5.0+, SwiftUI, macOS 14.0+ (Sonoma), XCTest, Xcode

**Spec:** `docs/superpowers/specs/2026-04-03-ai-usage-tracker-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|---|---|
| `Claude Usage/Shared/Models/ProfileProviderType.swift` | Enum for provider types |
| `Claude Usage/Shared/Models/OpenAIUsage.swift` | OpenAI billing data model |
| `Claude Usage/Shared/Models/CodexUsage.swift` | Codex rate-limit data model |
| `Claude Usage/Shared/Protocols/UsageProviderProtocol.swift` | Protocol for all providers |
| `Claude Usage/Shared/Services/OpenAIAPIProvider.swift` | OpenAI org-level API client |
| `Claude Usage/Shared/Services/CodexProvider.swift` | Probe request + header parsing |
| `Claude Usage/Shared/Services/ClaudeMaxProvider.swift` | Wraps existing ClaudeAPIService |
| `Claude Usage/Shared/Services/ClaudeAPIBillingProvider.swift` | Wraps existing Console API |
| `Claude Usage/Shared/Services/UsageProviderFactory.swift` | Creates provider for a profile |
| `Claude Usage/MenuBar/SmartStatusBarRenderer.swift` | Threshold-based status bar logic |
| `Claude Usage/Views/Credentials/OpenAICredentialView.swift` | Admin API key entry |
| `Claude Usage/Views/Credentials/CodexCredentialView.swift` | Regular API key entry |
| `Claude Usage/Views/Settings/AddProviderView.swift` | Provider type picker for new profiles |
| `Claude UsageTests/OpenAIUsageTests.swift` | OpenAI model tests |
| `Claude UsageTests/CodexUsageTests.swift` | Codex model tests |
| `Claude UsageTests/OpenAIAPIProviderTests.swift` | OpenAI API provider tests |
| `Claude UsageTests/CodexProviderTests.swift` | Codex provider tests |
| `Claude UsageTests/SmartStatusBarRendererTests.swift` | Status bar threshold tests |
| `Claude UsageTests/ProfileMigrationTests.swift` | Backward-compatible decoding tests |

### Modified Files

| File | Changes |
|---|---|
| `Claude Usage/Shared/Models/Profile.swift` | Add `providerType`, `primaryModel`, OpenAI fields |
| `Claude Usage/Shared/Models/MenuBarIconConfig.swift` | Add `.openai` and `.codex` metric types |
| `Claude Usage/Shared/Services/ProfileManager.swift` | Factory methods for new profile types |
| `Claude Usage/Shared/Storage/ProfileStore.swift` | `profiles_v4` key with v3 fallback |
| `Claude Usage/MenuBar/UsageRefreshCoordinator.swift` | Per-profile variable refresh intervals |
| `Claude Usage/MenuBar/MenuBarManager.swift` | Smart status bar + OpenAI/Codex usage storage |
| `Claude Usage/MenuBar/MenuBarIconRenderer.swift` | Render OpenAI/Codex metrics |
| `Claude Usage/MenuBar/PopoverContentView.swift` | 3-section layout |
| `Claude Usage/Shared/Services/UsageHistoryService.swift` | New snapshot types |
| `Claude Usage/Shared/Services/NotificationManager.swift` | Provider-aware thresholds |
| `Claude Usage/Views/SettingsView.swift` | Provider-aware profile creation |
| `Claude Usage/App/ClaudeUsageTrackerApp.swift` | Rename to AIUsageTrackerApp |

---

## Phase 1: Data Models

### Task 1: ProfileProviderType enum

**Files:**
- Create: `Claude Usage/Shared/Models/ProfileProviderType.swift`
- Test: `Claude UsageTests/ProfileMigrationTests.swift`

- [ ] **Step 1: Create the enum file**

```swift
// Claude Usage/Shared/Models/ProfileProviderType.swift

import Foundation

/// Identifies what kind of AI service a Profile tracks
enum ProfileProviderType: String, Codable, CaseIterable {
    case claudeMax      // Claude.ai subscription (session + weekly limits)
    case claudeAPI      // Anthropic Console API billing
    case openaiAPI      // OpenAI org-level API billing
    case codex          // OpenAI API rate limits (via probe)

    var displayName: String {
        switch self {
        case .claudeMax: return "Claude Max"
        case .claudeAPI: return "Claude API"
        case .openaiAPI: return "OpenAI API"
        case .codex: return "Codex"
        }
    }

    var iconSystemName: String {
        switch self {
        case .claudeMax: return "brain.head.profile"
        case .claudeAPI: return "server.rack"
        case .openaiAPI: return "cloud"
        case .codex: return "terminal"
        }
    }

    /// Default refresh interval in seconds
    var defaultRefreshInterval: TimeInterval {
        switch self {
        case .claudeMax: return 30       // Real-time session tracking
        case .claudeAPI: return 300      // 5 min — cost data updates slowly
        case .openaiAPI: return 300      // 5 min — paginated, slow-changing
        case .codex: return 60           // 1 min — each probe costs 1 request
        }
    }

    /// Whether this provider uses percentage-based tracking (vs dollar-based)
    var isPercentageBased: Bool {
        switch self {
        case .claudeMax, .codex: return true
        case .claudeAPI, .openaiAPI: return false
        }
    }
}
```

- [ ] **Step 2: Write test for Codable round-trip**

```swift
// Claude UsageTests/ProfileMigrationTests.swift

import XCTest
@testable import Claude_Usage

final class ProfileMigrationTests: XCTestCase {

    func testProfileProviderTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for providerType in ProfileProviderType.allCases {
            let data = try encoder.encode(providerType)
            let decoded = try decoder.decode(ProfileProviderType.self, from: data)
            XCTAssertEqual(providerType, decoded)
        }
    }

    func testProfileProviderTypeDefaultRefreshIntervals() {
        XCTAssertEqual(ProfileProviderType.claudeMax.defaultRefreshInterval, 30)
        XCTAssertEqual(ProfileProviderType.claudeAPI.defaultRefreshInterval, 300)
        XCTAssertEqual(ProfileProviderType.openaiAPI.defaultRefreshInterval, 300)
        XCTAssertEqual(ProfileProviderType.codex.defaultRefreshInterval, 60)
    }
}
```

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" -only-testing:"Claude UsageTests/ProfileMigrationTests" 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add "Claude Usage/Shared/Models/ProfileProviderType.swift" "Claude UsageTests/ProfileMigrationTests.swift"
git commit -m "feat: add ProfileProviderType enum for multi-provider support"
```

---

### Task 2: OpenAIUsage data model

**Files:**
- Create: `Claude Usage/Shared/Models/OpenAIUsage.swift`
- Test: `Claude UsageTests/OpenAIUsageTests.swift`

- [ ] **Step 1: Create the model**

```swift
// Claude Usage/Shared/Models/OpenAIUsage.swift

import Foundation

/// OpenAI API billing data — fetched from /v1/organization/costs and /v1/organization/usage/completions
struct OpenAIUsage: Codable, Equatable {
    let currentSpendCents: Int              // Summed from daily cost buckets
    let currency: String                    // e.g. "usd"
    let resetsAt: Date                      // Billing cycle end
    let dailyCostCents: [String: Double]    // "2026-04-03" -> cents
    let tokensByModel: [String: OpenAIModelTokens]?
    let lastUpdated: Date

    var usedAmount: Double {
        Double(currentSpendCents) / 100.0
    }

    var formattedUsed: String {
        formatCurrency(usedAmount)
    }

    var sortedDailyCosts: [(date: Date, cents: Double)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return dailyCostCents.compactMap { key, value in
            guard let date = formatter.date(from: key) else { return nil }
            return (date: date, cents: value)
        }.sorted { $0.date < $1.date }
    }

    var sortedModelTokens: [(model: String, tokens: OpenAIModelTokens)] {
        guard let byModel = tokensByModel else { return [] }
        return byModel.sorted { $0.value.totalTokens > $1.value.totalTokens }
            .map { (model: $0.key, tokens: $0.value) }
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount))
            ?? "\(currency) \(String(format: "%.2f", amount))"
    }
}

struct OpenAIModelTokens: Codable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens
    }
}
```

- [ ] **Step 2: Write tests**

```swift
// Claude UsageTests/OpenAIUsageTests.swift

import XCTest
@testable import Claude_Usage

final class OpenAIUsageTests: XCTestCase {

    func testUsedAmountConversion() {
        let usage = OpenAIUsage(
            currentSpendCents: 1250,
            currency: "usd",
            resetsAt: Date().addingTimeInterval(86400 * 27),
            dailyCostCents: ["2026-04-01": 500, "2026-04-02": 750],
            tokensByModel: nil,
            lastUpdated: Date()
        )
        XCTAssertEqual(usage.usedAmount, 12.50, accuracy: 0.001)
    }

    func testSortedDailyCosts() {
        let usage = OpenAIUsage(
            currentSpendCents: 1250,
            currency: "usd",
            resetsAt: Date(),
            dailyCostCents: ["2026-04-03": 300, "2026-04-01": 500, "2026-04-02": 450],
            tokensByModel: nil,
            lastUpdated: Date()
        )
        let sorted = usage.sortedDailyCosts
        XCTAssertEqual(sorted.count, 3)
        XCTAssertEqual(sorted[0].cents, 500)  // Apr 1 first
        XCTAssertEqual(sorted[2].cents, 300)  // Apr 3 last
    }

    func testCodableRoundTrip() throws {
        let usage = OpenAIUsage(
            currentSpendCents: 830,
            currency: "usd",
            resetsAt: Date(),
            dailyCostCents: ["2026-04-03": 120],
            tokensByModel: ["gpt-4o": OpenAIModelTokens(inputTokens: 5000, outputTokens: 2000, cachedTokens: 1000)],
            lastUpdated: Date()
        )
        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(OpenAIUsage.self, from: data)
        XCTAssertEqual(usage, decoded)
    }

    func testModelTokensTotalTokens() {
        let tokens = OpenAIModelTokens(inputTokens: 5000, outputTokens: 2000, cachedTokens: 1000)
        XCTAssertEqual(tokens.totalTokens, 7000)
    }
}
```

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" -only-testing:"Claude UsageTests/OpenAIUsageTests" 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add "Claude Usage/Shared/Models/OpenAIUsage.swift" "Claude UsageTests/OpenAIUsageTests.swift"
git commit -m "feat: add OpenAIUsage data model"
```

---

### Task 3: CodexUsage data model

**Files:**
- Create: `Claude Usage/Shared/Models/CodexUsage.swift`
- Test: `Claude UsageTests/CodexUsageTests.swift`

- [ ] **Step 1: Create the model**

```swift
// Claude Usage/Shared/Models/CodexUsage.swift

import Foundation

/// Codex rate-limit data parsed from OpenAI API response headers
struct CodexUsage: Codable, Equatable {
    let requestLimit: Int               // x-ratelimit-limit-requests
    let requestsRemaining: Int          // x-ratelimit-remaining-requests
    let tokenLimit: Int                 // x-ratelimit-limit-tokens
    let tokensRemaining: Int            // x-ratelimit-remaining-tokens
    let requestResetTime: Date          // x-ratelimit-reset-requests (parsed)
    let tokenResetTime: Date            // x-ratelimit-reset-tokens (parsed)
    let lastUpdated: Date

    var requestPercentageUsed: Double {
        guard requestLimit > 0 else { return 0 }
        return Double(requestLimit - requestsRemaining) / Double(requestLimit) * 100.0
    }

    var tokenPercentageUsed: Double {
        guard tokenLimit > 0 else { return 0 }
        return Double(tokenLimit - tokensRemaining) / Double(tokenLimit) * 100.0
    }

    var requestsUsed: Int {
        requestLimit - requestsRemaining
    }

    var tokensUsed: Int {
        tokenLimit - tokensRemaining
    }

    /// Parse the OpenAI rate-limit reset header value.
    /// Formats: "6m32.345s", "432ms", "1h2m3s", "0s"
    static func parseResetDuration(_ value: String) -> TimeInterval? {
        var total: TimeInterval = 0
        let scanner = Scanner(string: value)
        scanner.charactersToBeSkipped = nil

        while !scanner.isAtEnd {
            guard let number = scanner.scanDouble() else { return nil }
            if scanner.scanString("h") != nil {
                total += number * 3600
            } else if scanner.scanString("ms") != nil {
                total += number / 1000
            } else if scanner.scanString("m") != nil {
                total += number * 60
            } else if scanner.scanString("s") != nil {
                total += number
            } else {
                return nil
            }
        }
        return total
    }

    /// Create from response headers dictionary
    static func fromHeaders(_ headers: [String: String], at date: Date = Date()) -> CodexUsage? {
        guard let limitReq = headers["x-ratelimit-limit-requests"].flatMap(Int.init),
              let remainReq = headers["x-ratelimit-remaining-requests"].flatMap(Int.init),
              let limitTok = headers["x-ratelimit-limit-tokens"].flatMap(Int.init),
              let remainTok = headers["x-ratelimit-remaining-tokens"].flatMap(Int.init),
              let resetReqStr = headers["x-ratelimit-reset-requests"],
              let resetTokStr = headers["x-ratelimit-reset-tokens"],
              let resetReqDuration = parseResetDuration(resetReqStr),
              let resetTokDuration = parseResetDuration(resetTokStr)
        else { return nil }

        return CodexUsage(
            requestLimit: limitReq,
            requestsRemaining: remainReq,
            tokenLimit: limitTok,
            tokensRemaining: remainTok,
            requestResetTime: date.addingTimeInterval(resetReqDuration),
            tokenResetTime: date.addingTimeInterval(resetTokDuration),
            lastUpdated: date
        )
    }
}
```

- [ ] **Step 2: Write tests**

```swift
// Claude UsageTests/CodexUsageTests.swift

import XCTest
@testable import Claude_Usage

final class CodexUsageTests: XCTestCase {

    func testRequestPercentageUsed() {
        let usage = CodexUsage(
            requestLimit: 100, requestsRemaining: 28,
            tokenLimit: 100000, tokensRemaining: 55000,
            requestResetTime: Date(), tokenResetTime: Date(),
            lastUpdated: Date()
        )
        XCTAssertEqual(usage.requestPercentageUsed, 72.0, accuracy: 0.001)
        XCTAssertEqual(usage.tokenPercentageUsed, 45.0, accuracy: 0.001)
    }

    func testZeroLimitReturnsZeroPercentage() {
        let usage = CodexUsage(
            requestLimit: 0, requestsRemaining: 0,
            tokenLimit: 0, tokensRemaining: 0,
            requestResetTime: Date(), tokenResetTime: Date(),
            lastUpdated: Date()
        )
        XCTAssertEqual(usage.requestPercentageUsed, 0)
        XCTAssertEqual(usage.tokenPercentageUsed, 0)
    }

    func testParseResetDurationMinutesSeconds() {
        let duration = CodexUsage.parseResetDuration("6m32.345s")
        XCTAssertNotNil(duration)
        XCTAssertEqual(duration!, 392.345, accuracy: 0.001)
    }

    func testParseResetDurationMilliseconds() {
        let duration = CodexUsage.parseResetDuration("432ms")
        XCTAssertNotNil(duration)
        XCTAssertEqual(duration!, 0.432, accuracy: 0.001)
    }

    func testParseResetDurationHoursMinutesSeconds() {
        let duration = CodexUsage.parseResetDuration("1h2m3s")
        XCTAssertNotNil(duration)
        XCTAssertEqual(duration!, 3723, accuracy: 0.001)
    }

    func testParseResetDurationZero() {
        let duration = CodexUsage.parseResetDuration("0s")
        XCTAssertNotNil(duration)
        XCTAssertEqual(duration!, 0, accuracy: 0.001)
    }

    func testFromHeaders() {
        let now = Date()
        let headers: [String: String] = [
            "x-ratelimit-limit-requests": "100",
            "x-ratelimit-remaining-requests": "72",
            "x-ratelimit-limit-tokens": "50000",
            "x-ratelimit-remaining-tokens": "35000",
            "x-ratelimit-reset-requests": "2m30s",
            "x-ratelimit-reset-tokens": "1m0s"
        ]
        let usage = CodexUsage.fromHeaders(headers, at: now)
        XCTAssertNotNil(usage)
        XCTAssertEqual(usage!.requestLimit, 100)
        XCTAssertEqual(usage!.requestsRemaining, 72)
        XCTAssertEqual(usage!.tokenLimit, 50000)
        XCTAssertEqual(usage!.tokensRemaining, 35000)
        XCTAssertEqual(usage!.requestResetTime.timeIntervalSince(now), 150, accuracy: 0.001)
        XCTAssertEqual(usage!.tokenResetTime.timeIntervalSince(now), 60, accuracy: 0.001)
    }

    func testFromHeadersMissingFieldReturnsNil() {
        let headers: [String: String] = [
            "x-ratelimit-limit-requests": "100"
            // Missing other required fields
        ]
        XCTAssertNil(CodexUsage.fromHeaders(headers))
    }

    func testCodableRoundTrip() throws {
        let usage = CodexUsage(
            requestLimit: 100, requestsRemaining: 72,
            tokenLimit: 50000, tokensRemaining: 35000,
            requestResetTime: Date(), tokenResetTime: Date(),
            lastUpdated: Date()
        )
        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(CodexUsage.self, from: data)
        XCTAssertEqual(usage, decoded)
    }
}
```

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" -only-testing:"Claude UsageTests/CodexUsageTests" 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add "Claude Usage/Shared/Models/CodexUsage.swift" "Claude UsageTests/CodexUsageTests.swift"
git commit -m "feat: add CodexUsage data model with header parsing"
```

---

### Task 4: Extend Profile with new fields

**Files:**
- Modify: `Claude Usage/Shared/Models/Profile.swift`
- Test: `Claude UsageTests/ProfileMigrationTests.swift` (extend)

- [ ] **Step 1: Write migration test — existing profiles decode without new fields**

Add to `Claude UsageTests/ProfileMigrationTests.swift`:

```swift
func testExistingProfileDecodesWithoutNewFields() throws {
    // Simulate a v3 profile JSON (no providerType, no OpenAI fields)
    let json = """
    {
        "id": "550E8400-E29B-41D4-A716-446655440000",
        "name": "Test Profile",
        "hasCliAccount": false,
        "iconConfig": {
            "colorMode": "multiColor",
            "singleColorHex": "#FFFFFF",
            "showIconNames": false,
            "showRemainingPercentage": false,
            "showTimeMarker": true,
            "showPaceMarker": false,
            "usePaceColoring": false,
            "metrics": []
        },
        "refreshInterval": 30.0,
        "autoStartSessionEnabled": false,
        "checkOverageLimitEnabled": true,
        "notificationSettings": {
            "enabled": true,
            "threshold75Enabled": true,
            "threshold90Enabled": true,
            "threshold95Enabled": true,
            "soundName": "default",
            "customThresholds": []
        },
        "isSelectedForDisplay": true,
        "createdAt": 0,
        "lastUsedAt": 0
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let profile = try decoder.decode(Profile.self, from: json)

    XCTAssertEqual(profile.name, "Test Profile")
    // New fields should default gracefully
    XCTAssertEqual(profile.providerType, .claudeMax)
    XCTAssertNil(profile.primaryModel)
    XCTAssertNil(profile.openaiAdminKey)
    XCTAssertNil(profile.openaiApiKey)
    XCTAssertNil(profile.openaiOrganizationId)
    XCTAssertNil(profile.openaiUsage)
    XCTAssertNil(profile.codexUsage)
    XCTAssertNil(profile.spendBudgetCents)
    XCTAssertNil(profile.spendBudgetCurrency)
}

func testNewProfileWithOpenAIFields() throws {
    let profile = Profile(
        name: "OpenAI Test",
        providerType: .openaiAPI,
        openaiAdminKey: "sk-admin-test123"
    )
    XCTAssertEqual(profile.providerType, .openaiAPI)
    XCTAssertEqual(profile.openaiAdminKey, "sk-admin-test123")

    // Codable round-trip
    let data = try JSONEncoder().encode(profile)
    let decoded = try JSONDecoder().decode(Profile.self, from: data)
    XCTAssertEqual(decoded.providerType, .openaiAPI)
    XCTAssertEqual(decoded.openaiAdminKey, "sk-admin-test123")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" -only-testing:"Claude UsageTests/ProfileMigrationTests" 2>&1 | tail -20`
Expected: FAIL — `providerType`, `openaiAdminKey` etc. don't exist yet

- [ ] **Step 3: Add new fields to Profile.swift**

Add these properties after the existing `lastUsedAt` field (around line 48):

```swift
// MARK: - Provider Type (NEW — defaults to .claudeMax for existing profiles)
var providerType: ProfileProviderType
var primaryModel: String?               // "opus", "sonnet" — for Opus-first display

// MARK: - OpenAI Credentials (NEW — only used when providerType is .openaiAPI or .codex)
var openaiAdminKey: String?             // Admin API key for org-level endpoints
var openaiApiKey: String?               // Regular API key for probe requests
var openaiOrganizationId: String?

// MARK: - OpenAI Usage Data (NEW)
var openaiUsage: OpenAIUsage?
var codexUsage: CodexUsage?

// MARK: - Budget Settings (NEW — user-configured spend threshold for API billing alerts)
var spendBudgetCents: Int?
var spendBudgetCurrency: String?
```

Update the `init()` to include new parameters with defaults:

```swift
providerType: ProfileProviderType = .claudeMax,
primaryModel: String? = nil,
openaiAdminKey: String? = nil,
openaiApiKey: String? = nil,
openaiOrganizationId: String? = nil,
openaiUsage: OpenAIUsage? = nil,
codexUsage: CodexUsage? = nil,
spendBudgetCents: Int? = nil,
spendBudgetCurrency: String? = nil,
```

Add corresponding assignments in `init` body.

Add a custom `init(from decoder:)` for backward compatibility:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    // Existing fields
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    claudeSessionKey = try container.decodeIfPresent(String.self, forKey: .claudeSessionKey)
    organizationId = try container.decodeIfPresent(String.self, forKey: .organizationId)
    apiSessionKey = try container.decodeIfPresent(String.self, forKey: .apiSessionKey)
    apiOrganizationId = try container.decodeIfPresent(String.self, forKey: .apiOrganizationId)
    apiSessionKeyExpiry = try container.decodeIfPresent(Date.self, forKey: .apiSessionKeyExpiry)
    cliCredentialsJSON = try container.decodeIfPresent(String.self, forKey: .cliCredentialsJSON)
    hasCliAccount = try container.decodeIfPresent(Bool.self, forKey: .hasCliAccount) ?? false
    cliAccountSyncedAt = try container.decodeIfPresent(Date.self, forKey: .cliAccountSyncedAt)
    claudeUsage = try container.decodeIfPresent(ClaudeUsage.self, forKey: .claudeUsage)
    apiUsage = try container.decodeIfPresent(APIUsage.self, forKey: .apiUsage)
    iconConfig = try container.decodeIfPresent(MenuBarIconConfiguration.self, forKey: .iconConfig) ?? .default
    refreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 30.0
    autoStartSessionEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoStartSessionEnabled) ?? false
    checkOverageLimitEnabled = try container.decodeIfPresent(Bool.self, forKey: .checkOverageLimitEnabled) ?? true
    notificationSettings = try container.decodeIfPresent(NotificationSettings.self, forKey: .notificationSettings) ?? NotificationSettings()
    isSelectedForDisplay = try container.decodeIfPresent(Bool.self, forKey: .isSelectedForDisplay) ?? true
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? Date()

    // New fields — all optional with defaults
    providerType = try container.decodeIfPresent(ProfileProviderType.self, forKey: .providerType) ?? .claudeMax
    primaryModel = try container.decodeIfPresent(String.self, forKey: .primaryModel)
    openaiAdminKey = try container.decodeIfPresent(String.self, forKey: .openaiAdminKey)
    openaiApiKey = try container.decodeIfPresent(String.self, forKey: .openaiApiKey)
    openaiOrganizationId = try container.decodeIfPresent(String.self, forKey: .openaiOrganizationId)
    openaiUsage = try container.decodeIfPresent(OpenAIUsage.self, forKey: .openaiUsage)
    codexUsage = try container.decodeIfPresent(CodexUsage.self, forKey: .codexUsage)
    spendBudgetCents = try container.decodeIfPresent(Int.self, forKey: .spendBudgetCents)
    spendBudgetCurrency = try container.decodeIfPresent(String.self, forKey: .spendBudgetCurrency)
}
```

Add computed properties:

```swift
var hasOpenAIAPI: Bool {
    openaiAdminKey != nil
}

var hasCodexProbe: Bool {
    openaiApiKey != nil
}

/// The percentage to use for status bar threshold comparisons
var effectivePercentageForThreshold: Double? {
    switch providerType {
    case .claudeMax:
        if primaryModel == "sonnet" {
            return claudeUsage?.sonnetWeeklyPercentage
        }
        return claudeUsage?.opusWeeklyPercentage ?? claudeUsage?.effectiveSessionPercentage
    case .codex:
        return codexUsage?.requestPercentageUsed
    case .claudeAPI:
        guard let budget = spendBudgetCents, budget > 0, let usage = apiUsage else { return nil }
        return Double(usage.currentSpendCents) / Double(budget) * 100.0
    case .openaiAPI:
        guard let budget = spendBudgetCents, budget > 0, let usage = openaiUsage else { return nil }
        return Double(usage.currentSpendCents) / Double(budget) * 100.0
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" -only-testing:"Claude UsageTests/ProfileMigrationTests" 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add "Claude Usage/Shared/Models/Profile.swift" "Claude UsageTests/ProfileMigrationTests.swift"
git commit -m "feat: extend Profile with providerType, OpenAI fields, and backward-compatible decoding"
```

---

## Phase 2: Provider Implementations

### Task 5: UsageProvider protocol and factory

**Files:**
- Create: `Claude Usage/Shared/Protocols/UsageProviderProtocol.swift`
- Create: `Claude Usage/Shared/Services/UsageProviderFactory.swift`

- [ ] **Step 1: Create the protocol**

```swift
// Claude Usage/Shared/Protocols/UsageProviderProtocol.swift

import Foundation

/// Type-safe container for provider-specific usage updates.
/// Each provider sets only its relevant field; caller merges into Profile.
struct ProfileUsageUpdate {
    var claudeUsage: ClaudeUsage?
    var apiUsage: APIUsage?
    var openaiUsage: OpenAIUsage?
    var codexUsage: CodexUsage?
}

/// Protocol for all usage data providers. Each Profile maps to one provider.
protocol UsageProvider {
    var providerType: ProfileProviderType { get }
    var profileId: UUID { get }
    var displayName: String { get }

    /// Fetch fresh usage data for the given profile.
    func fetchUsage(for profile: Profile) async throws -> ProfileUsageUpdate

    /// Validate that the profile's credentials are working.
    func validateCredentials(for profile: Profile) async throws -> Bool
}
```

- [ ] **Step 2: Create the factory**

```swift
// Claude Usage/Shared/Services/UsageProviderFactory.swift

import Foundation

/// Creates the appropriate UsageProvider for a given Profile based on its providerType.
enum UsageProviderFactory {
    static func makeProvider(for profile: Profile) -> UsageProvider {
        switch profile.providerType {
        case .claudeMax:
            return ClaudeMaxProvider(profile: profile)
        case .claudeAPI:
            return ClaudeAPIBillingProvider(profile: profile)
        case .openaiAPI:
            return OpenAIAPIProvider(profile: profile)
        case .codex:
            return CodexProvider(profile: profile)
        }
    }
}
```

Note: The concrete provider classes (`ClaudeMaxProvider`, etc.) are created in subsequent tasks. This file will not compile until they exist. That's fine — it gets committed together with the first provider.

- [ ] **Step 3: Commit protocol**

```bash
git add "Claude Usage/Shared/Protocols/UsageProviderProtocol.swift"
git commit -m "feat: add UsageProvider protocol and ProfileUsageUpdate"
```

---

### Task 6: ClaudeMaxProvider wrapper

**Files:**
- Create: `Claude Usage/Shared/Services/ClaudeMaxProvider.swift`

- [ ] **Step 1: Create the wrapper**

This wraps the existing `ClaudeAPIService` without modifying it. References `ClaudeAPIService` methods and `ProfileManager` to set active profile context.

```swift
// Claude Usage/Shared/Services/ClaudeMaxProvider.swift

import Foundation

/// Wraps existing ClaudeAPIService for Claude Max subscription tracking.
/// Does NOT modify the original service — just delegates to it.
struct ClaudeMaxProvider: UsageProvider {
    let providerType: ProfileProviderType = .claudeMax
    let profileId: UUID
    let displayName: String

    init(profile: Profile) {
        self.profileId = profile.id
        self.displayName = profile.name
    }

    func fetchUsage(for profile: Profile) async throws -> ProfileUsageUpdate {
        // ClaudeAPIService reads credentials from ProfileManager.shared.activeProfile
        // so this only works for the currently active profile.
        let apiService = ClaudeAPIService()
        let usage = try await apiService.fetchUsageData()
        return ProfileUsageUpdate(claudeUsage: usage)
    }

    func validateCredentials(for profile: Profile) async throws -> Bool {
        return profile.hasUsageCredentials
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/Shared/Services/ClaudeMaxProvider.swift"
git commit -m "feat: add ClaudeMaxProvider wrapping existing ClaudeAPIService"
```

---

### Task 7: ClaudeAPIBillingProvider wrapper

**Files:**
- Create: `Claude Usage/Shared/Services/ClaudeAPIBillingProvider.swift`

- [ ] **Step 1: Create the wrapper**

```swift
// Claude Usage/Shared/Services/ClaudeAPIBillingProvider.swift

import Foundation

/// Wraps existing Console API billing logic for Claude API spend tracking.
struct ClaudeAPIBillingProvider: UsageProvider {
    let providerType: ProfileProviderType = .claudeAPI
    let profileId: UUID
    let displayName: String

    init(profile: Profile) {
        self.profileId = profile.id
        self.displayName = profile.name
    }

    func fetchUsage(for profile: Profile) async throws -> ProfileUsageUpdate {
        let apiService = ClaudeAPIService()
        guard let apiOrgId = profile.apiOrganizationId,
              let apiKey = profile.apiSessionKey else {
            throw ClaudeAPIService.APIError.noSessionKey
        }
        let apiUsage = try await apiService.fetchAPIUsageData(
            organizationId: apiOrgId,
            apiSessionKey: apiKey
        )
        return ProfileUsageUpdate(apiUsage: apiUsage)
    }

    func validateCredentials(for profile: Profile) async throws -> Bool {
        return profile.hasAPIConsole
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/Shared/Services/ClaudeAPIBillingProvider.swift"
git commit -m "feat: add ClaudeAPIBillingProvider wrapping existing Console API"
```

---

### Task 8: OpenAIAPIProvider

**Files:**
- Create: `Claude Usage/Shared/Services/OpenAIAPIProvider.swift`
- Test: `Claude UsageTests/OpenAIAPIProviderTests.swift`

- [ ] **Step 1: Write test for response parsing**

```swift
// Claude UsageTests/OpenAIAPIProviderTests.swift

import XCTest
@testable import Claude_Usage

final class OpenAIAPIProviderTests: XCTestCase {

    func testParseCostsResponse() throws {
        let json = """
        {
            "object": "page",
            "data": [
                {
                    "object": "bucket",
                    "start_time": 1743638400,
                    "end_time": 1743724800,
                    "results": [
                        {"object": "organization.costs.result", "amount": {"value": 350, "currency": "usd"}, "line_item": "Tokens"}
                    ]
                },
                {
                    "object": "bucket",
                    "start_time": 1743724800,
                    "end_time": 1743811200,
                    "results": [
                        {"object": "organization.costs.result", "amount": {"value": 480, "currency": "usd"}, "line_item": "Tokens"}
                    ]
                }
            ],
            "has_more": false
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OpenAIAPIProvider.CostsPageResponse.self, from: json)
        XCTAssertEqual(response.data.count, 2)
        XCTAssertFalse(response.hasMore)
        XCTAssertEqual(response.data[0].results[0].amount.value, 350)
        XCTAssertEqual(response.data[0].results[0].amount.currency, "usd")
    }

    func testParseCompletionsUsageResponse() throws {
        let json = """
        {
            "object": "page",
            "data": [
                {
                    "object": "bucket",
                    "start_time": 1743638400,
                    "end_time": 1743724800,
                    "results": [
                        {
                            "object": "organization.usage.completions.result",
                            "input_tokens": 5000,
                            "output_tokens": 2000,
                            "input_cached_tokens": 1000,
                            "model": "gpt-4o"
                        }
                    ]
                }
            ],
            "has_more": false
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OpenAIAPIProvider.CompletionsPageResponse.self, from: json)
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].results[0].model, "gpt-4o")
        XCTAssertEqual(response.data[0].results[0].inputTokens, 5000)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" -only-testing:"Claude UsageTests/OpenAIAPIProviderTests" 2>&1 | tail -20`
Expected: FAIL — `OpenAIAPIProvider` doesn't exist

- [ ] **Step 3: Implement OpenAIAPIProvider**

```swift
// Claude Usage/Shared/Services/OpenAIAPIProvider.swift

import Foundation

/// Fetches OpenAI API billing data from org-level admin endpoints.
/// Requires an Admin API key (sk-admin-...).
struct OpenAIAPIProvider: UsageProvider {
    let providerType: ProfileProviderType = .openaiAPI
    let profileId: UUID
    let displayName: String

    private static let baseURL = "https://api.openai.com/v1/organization"

    init(profile: Profile) {
        self.profileId = profile.id
        self.displayName = profile.name
    }

    func fetchUsage(for profile: Profile) async throws -> ProfileUsageUpdate {
        guard let adminKey = profile.openaiAdminKey else {
            throw OpenAIError.noAdminKey
        }

        let now = Date()
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        let startTime = Int(startOfMonth.timeIntervalSince1970)
        let endTime = Int(now.timeIntervalSince1970)

        // Fetch costs (paginated)
        let costs = try await fetchAllCosts(adminKey: adminKey, startTime: startTime, endTime: endTime)

        // Fetch completions usage with model grouping (paginated)
        let completions = try await fetchAllCompletions(adminKey: adminKey, startTime: startTime, endTime: endTime)

        // Sum daily costs
        var dailyCosts: [String: Double] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var totalCents: Int = 0
        var currency = "usd"

        for bucket in costs {
            let dateStr = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(bucket.startTime)))
            let bucketTotal = bucket.results.reduce(0) { $0 + $1.amount.value }
            dailyCosts[dateStr, default: 0] += Double(bucketTotal)
            totalCents += bucketTotal
            if let c = bucket.results.first?.amount.currency {
                currency = c
            }
        }

        // Aggregate tokens by model
        var tokensByModel: [String: OpenAIModelTokens] = [:]
        for bucket in completions {
            for result in bucket.results {
                let model = result.model ?? "unknown"
                let existing = tokensByModel[model] ?? OpenAIModelTokens(inputTokens: 0, outputTokens: 0, cachedTokens: 0)
                tokensByModel[model] = OpenAIModelTokens(
                    inputTokens: existing.inputTokens + result.inputTokens,
                    outputTokens: existing.outputTokens + result.outputTokens,
                    cachedTokens: existing.cachedTokens + result.inputCachedTokens
                )
            }
        }

        let usage = OpenAIUsage(
            currentSpendCents: totalCents,
            currency: currency,
            resetsAt: startOfNextMonth,
            dailyCostCents: dailyCosts,
            tokensByModel: tokensByModel.isEmpty ? nil : tokensByModel,
            lastUpdated: now
        )

        return ProfileUsageUpdate(openaiUsage: usage)
    }

    func validateCredentials(for profile: Profile) async throws -> Bool {
        guard let adminKey = profile.openaiAdminKey else { return false }
        // Quick validation: fetch one day of costs
        let now = Int(Date().timeIntervalSince1970)
        let oneDayAgo = now - 86400
        let url = URL(string: "\(Self.baseURL)/costs?start_time=\(oneDayAgo)&end_time=\(now)&bucket_width=1d&limit=1")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    // MARK: - Pagination

    private func fetchAllCosts(adminKey: String, startTime: Int, endTime: Int) async throws -> [CostBucket] {
        var allBuckets: [CostBucket] = []
        var nextPage: String? = nil

        repeat {
            var urlString = "\(Self.baseURL)/costs?start_time=\(startTime)&end_time=\(endTime)&bucket_width=1d&limit=7"
            if let page = nextPage {
                urlString += "&page=\(page)"
            }
            guard let url = URL(string: urlString) else { break }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            let page = try JSONDecoder().decode(CostsPageResponse.self, from: data)
            allBuckets.append(contentsOf: page.data)
            nextPage = page.hasMore ? page.nextPage : nil
        } while nextPage != nil

        return allBuckets
    }

    private func fetchAllCompletions(adminKey: String, startTime: Int, endTime: Int) async throws -> [CompletionsBucket] {
        var allBuckets: [CompletionsBucket] = []
        var nextPage: String? = nil

        repeat {
            var urlString = "\(Self.baseURL)/usage/completions?start_time=\(startTime)&end_time=\(endTime)&bucket_width=1d&group_by[]=model&limit=7"
            if let page = nextPage {
                urlString += "&page=\(page)"
            }
            guard let url = URL(string: urlString) else { break }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            let page = try JSONDecoder().decode(CompletionsPageResponse.self, from: data)
            allBuckets.append(contentsOf: page.data)
            nextPage = page.hasMore ? page.nextPage : nil
        } while nextPage != nil

        return allBuckets
    }

    // MARK: - Response Types

    struct CostsPageResponse: Codable {
        let data: [CostBucket]
        let hasMore: Bool
        let nextPage: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
        }
    }

    struct CostBucket: Codable {
        let startTime: Int
        let endTime: Int
        let results: [CostResult]

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case endTime = "end_time"
            case results
        }
    }

    struct CostResult: Codable {
        let amount: CostAmount
        let lineItem: String?

        enum CodingKeys: String, CodingKey {
            case amount
            case lineItem = "line_item"
        }
    }

    struct CostAmount: Codable {
        let value: Int
        let currency: String
    }

    struct CompletionsPageResponse: Codable {
        let data: [CompletionsBucket]
        let hasMore: Bool
        let nextPage: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
        }
    }

    struct CompletionsBucket: Codable {
        let startTime: Int
        let endTime: Int
        let results: [CompletionsResult]

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case endTime = "end_time"
            case results
        }
    }

    struct CompletionsResult: Codable {
        let inputTokens: Int
        let outputTokens: Int
        let inputCachedTokens: Int
        let model: String?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case inputCachedTokens = "input_cached_tokens"
            case model
        }
    }

    // MARK: - Errors

    enum OpenAIError: Error, LocalizedError {
        case noAdminKey
        case invalidResponse
        case unauthorized

        var errorDescription: String? {
            switch self {
            case .noAdminKey: return "No OpenAI Admin API key configured"
            case .invalidResponse: return "Invalid response from OpenAI API"
            case .unauthorized: return "OpenAI Admin API key is invalid or expired"
            }
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" -only-testing:"Claude UsageTests/OpenAIAPIProviderTests" 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add "Claude Usage/Shared/Services/OpenAIAPIProvider.swift" "Claude UsageTests/OpenAIAPIProviderTests.swift"
git commit -m "feat: add OpenAIAPIProvider with paginated costs and completions endpoints"
```

---

### Task 9: CodexProvider

**Files:**
- Create: `Claude Usage/Shared/Services/CodexProvider.swift`
- Test: `Claude UsageTests/CodexProviderTests.swift`

- [ ] **Step 1: Write test**

```swift
// Claude UsageTests/CodexProviderTests.swift

import XCTest
@testable import Claude_Usage

final class CodexProviderTests: XCTestCase {

    func testBuildProbeRequest() {
        let provider = CodexProvider(profile: Profile(name: "Test Codex", providerType: .codex, openaiApiKey: "sk-test123"))
        let request = provider.buildProbeRequest(apiKey: "sk-test123")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        // Verify body is minimal
        let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["max_tokens"] as? Int, 1)
        XCTAssertNotNil(body["model"])
        XCTAssertNotNil(body["messages"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" -only-testing:"Claude UsageTests/CodexProviderTests" 2>&1 | tail -20`
Expected: FAIL

- [ ] **Step 3: Implement CodexProvider**

```swift
// Claude Usage/Shared/Services/CodexProvider.swift

import Foundation

/// Tracks OpenAI API rate limits by making a lightweight probe request
/// and reading rate-limit headers from the response.
struct CodexProvider: UsageProvider {
    let providerType: ProfileProviderType = .codex
    let profileId: UUID
    let displayName: String

    private static let completionsURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(profile: Profile) {
        self.profileId = profile.id
        self.displayName = profile.name
    }

    func fetchUsage(for profile: Profile) async throws -> ProfileUsageUpdate {
        guard let apiKey = profile.openaiApiKey else {
            throw CodexError.noApiKey
        }

        let request = buildProbeRequest(apiKey: apiKey)
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexError.invalidResponse
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 429 else {
            if httpResponse.statusCode == 401 {
                throw CodexError.unauthorized
            }
            throw CodexError.serverError(statusCode: httpResponse.statusCode)
        }

        // Extract rate-limit headers (available on both 200 and 429 responses)
        let headers = Dictionary(
            uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { key, value in
                guard let k = key as? String, let v = value as? String else { return nil }
                return (k.lowercased(), v)
            }
        )

        guard let usage = CodexUsage.fromHeaders(headers) else {
            throw CodexError.missingRateLimitHeaders
        }

        return ProfileUsageUpdate(codexUsage: usage)
    }

    func validateCredentials(for profile: Profile) async throws -> Bool {
        guard let apiKey = profile.openaiApiKey else { return false }
        let request = buildProbeRequest(apiKey: apiKey)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    /// Build a minimal probe request: 1 token, cheapest model
    func buildProbeRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: Self.completionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ])
        return request
    }

    // MARK: - Errors

    enum CodexError: Error, LocalizedError {
        case noApiKey
        case invalidResponse
        case unauthorized
        case missingRateLimitHeaders
        case serverError(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .noApiKey: return "No OpenAI API key configured for Codex probe"
            case .invalidResponse: return "Invalid response from OpenAI API"
            case .unauthorized: return "OpenAI API key is invalid or expired"
            case .missingRateLimitHeaders: return "Rate-limit headers missing from response"
            case .serverError(let code): return "OpenAI API returned status \(code)"
            }
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" -only-testing:"Claude UsageTests/CodexProviderTests" 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Now commit the factory too (all providers exist)**

```bash
git add "Claude Usage/Shared/Services/CodexProvider.swift" "Claude UsageTests/CodexProviderTests.swift" "Claude Usage/Shared/Services/UsageProviderFactory.swift"
git commit -m "feat: add CodexProvider with probe requests and UsageProviderFactory"
```

---

## Phase 3: Infrastructure

### Task 10: Smart status bar renderer

**Files:**
- Create: `Claude Usage/MenuBar/SmartStatusBarRenderer.swift`
- Test: `Claude UsageTests/SmartStatusBarRendererTests.swift`

- [ ] **Step 1: Write test**

```swift
// Claude UsageTests/SmartStatusBarRendererTests.swift

import XCTest
@testable import Claude_Usage

final class SmartStatusBarRendererTests: XCTestCase {

    func testNoProfilesAboveThresholdReturnsEmpty() {
        let profiles = [
            makeProfile(name: "Low", percentage: 30),
            makeProfile(name: "Medium", percentage: 55)
        ]
        let result = SmartStatusBarRenderer.profilesForStatusBar(profiles, threshold: 60, maxItems: 4)
        XCTAssertTrue(result.isEmpty)
    }

    func testProfilesAboveThresholdReturned() {
        let profiles = [
            makeProfile(name: "High", percentage: 85),
            makeProfile(name: "Low", percentage: 30),
            makeProfile(name: "Critical", percentage: 95)
        ]
        let result = SmartStatusBarRenderer.profilesForStatusBar(profiles, threshold: 60, maxItems: 4)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Critical")  // Highest first
        XCTAssertEqual(result[1].name, "High")
    }

    func testMaxItemsRespected() {
        let profiles = (1...6).map { i in
            makeProfile(name: "P\(i)", percentage: Double(60 + i * 5))
        }
        let result = SmartStatusBarRenderer.profilesForStatusBar(profiles, threshold: 60, maxItems: 3)
        XCTAssertEqual(result.count, 3)
    }

    func testColorForPercentage() {
        XCTAssertEqual(SmartStatusBarRenderer.alertLevel(for: 50), .none)
        XCTAssertEqual(SmartStatusBarRenderer.alertLevel(for: 72), .warning)
        XCTAssertEqual(SmartStatusBarRenderer.alertLevel(for: 95), .critical)
    }

    func testAPIProfileWithNoBudgetExcluded() {
        var profile = Profile(name: "API", providerType: .claudeAPI)
        profile.apiUsage = APIUsage(
            currentSpendCents: 5000,
            resetsAt: Date(),
            prepaidCreditsCents: 10000,
            currency: "usd",
            apiTokenCostCents: nil,
            apiCostByModel: nil,
            costBySource: nil,
            dailyCostCents: nil
        )
        // No spendBudgetCents set → effectivePercentageForThreshold returns nil
        XCTAssertNil(profile.effectivePercentageForThreshold)
    }

    // MARK: - Helpers

    private func makeProfile(name: String, percentage: Double) -> Profile {
        var profile = Profile(name: name, providerType: .claudeMax)
        profile.claudeUsage = ClaudeUsage(
            sessionTokensUsed: 0, sessionLimit: 0,
            sessionPercentage: percentage,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyTokensUsed: 0, weeklyLimit: 0,
            weeklyPercentage: percentage,
            weeklyResetTime: Date(),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: percentage,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            lastUpdated: Date(),
            userTimezone: .current
        )
        return profile
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `SmartStatusBarRenderer` doesn't exist

- [ ] **Step 3: Implement SmartStatusBarRenderer**

```swift
// Claude Usage/MenuBar/SmartStatusBarRenderer.swift

import Foundation

/// Determines which profiles should appear in the status bar based on threshold logic.
enum SmartStatusBarRenderer {

    enum AlertLevel: Equatable {
        case none       // Below threshold — hidden from status bar
        case warning    // 60-89% — yellow
        case critical   // 90%+ — red
    }

    /// Returns profiles that should appear in the status bar, sorted by urgency (highest % first).
    /// Profiles below the threshold are excluded.
    /// API billing profiles with no budget set are excluded.
    static func profilesForStatusBar(
        _ profiles: [Profile],
        threshold: Double = 60,
        maxItems: Int = 4
    ) -> [Profile] {
        profiles
            .compactMap { profile -> (Profile, Double)? in
                guard let pct = profile.effectivePercentageForThreshold,
                      pct >= threshold else { return nil }
                return (profile, pct)
            }
            .sorted { $0.1 > $1.1 }  // Highest percentage first
            .prefix(maxItems)
            .map(\.0)
    }

    /// Determine the alert level for a given percentage.
    static func alertLevel(for percentage: Double) -> AlertLevel {
        if percentage >= 90 { return .critical }
        if percentage >= 60 { return .warning }
        return .none
    }

    /// Format the status bar label for a profile.
    static func statusBarLabel(for profile: Profile) -> String {
        let pct = profile.effectivePercentageForThreshold ?? 0
        let pctStr = String(format: "%.0f%%", pct)

        switch profile.providerType {
        case .claudeMax:
            let model = profile.primaryModel ?? "opus"
            return "\(profile.name) \(model) \(pctStr)"
        case .codex:
            return "Codex \(pctStr)"
        case .claudeAPI, .openaiAPI:
            if let usage = profile.providerType == .claudeAPI ? profile.apiUsage?.usedAmount : profile.openaiUsage?.usedAmount {
                return "\(profile.name) $\(String(format: "%.0f", usage))"
            }
            return "\(profile.name) \(pctStr)"
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" -only-testing:"Claude UsageTests/SmartStatusBarRendererTests" 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add "Claude Usage/MenuBar/SmartStatusBarRenderer.swift" "Claude UsageTests/SmartStatusBarRendererTests.swift"
git commit -m "feat: add SmartStatusBarRenderer with threshold-based visibility"
```

---

### Task 11: Extend UsageRefreshCoordinator for variable intervals

**Files:**
- Modify: `Claude Usage/MenuBar/UsageRefreshCoordinator.swift`

- [ ] **Step 1: Add per-profile timer support**

The current coordinator uses a single `refreshTimer`. Replace with per-profile timers keyed by `profileId`.

In `UsageRefreshCoordinator.swift`, add:

```swift
// Add property for per-profile timers
private var profileTimers: [UUID: Timer] = [:]

/// Start refresh timers for all enabled profiles with variable intervals
func startMultiProviderRefresh(profiles: [Profile]) {
    stopAllTimers()

    for profile in profiles where profile.isSelectedForDisplay {
        let interval = profile.refreshInterval > 0
            ? profile.refreshInterval
            : profile.providerType.defaultRefreshInterval

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.refreshProfile(profile)
            }
        }
        profileTimers[profile.id] = timer

        // Immediate first refresh
        Task { [weak self] in
            await self?.refreshProfile(profile)
        }
    }
}

/// Refresh a single profile using its provider
private func refreshProfile(_ profile: Profile) async {
    let provider = UsageProviderFactory.makeProvider(for: profile)
    do {
        let update = try await provider.fetchUsage(for: profile)
        await MainActor.run {
            delegate?.profileUsageDidUpdate(profileId: profile.id, update: update)
        }
    } catch {
        await MainActor.run {
            delegate?.profileRefreshDidFail(profileId: profile.id, error: error)
        }
    }
}

func stopAllTimers() {
    profileTimers.values.forEach { $0.invalidate() }
    profileTimers.removeAll()
}
```

Update the `UsageRefreshCoordinatorDelegate` protocol:

```swift
protocol UsageRefreshCoordinatorDelegate: AnyObject {
    // Existing
    func usageRefreshDidComplete(usage: ClaudeUsage)
    func statusRefreshDidComplete(status: ClaudeStatus)
    func apiUsageRefreshDidComplete(apiUsage: APIUsage)

    // New
    func profileUsageDidUpdate(profileId: UUID, update: ProfileUsageUpdate)
    func profileRefreshDidFail(profileId: UUID, error: Error)
}

// Default implementations so existing code doesn't break
extension UsageRefreshCoordinatorDelegate {
    func profileUsageDidUpdate(profileId: UUID, update: ProfileUsageUpdate) {}
    func profileRefreshDidFail(profileId: UUID, error: Error) {}
}
```

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/MenuBar/UsageRefreshCoordinator.swift"
git commit -m "feat: add per-profile variable refresh intervals to UsageRefreshCoordinator"
```

---

### Task 12: Extend ProfileStore with v4 storage migration

**Files:**
- Modify: `Claude Usage/Shared/Storage/ProfileStore.swift`

- [ ] **Step 1: Add v4 key with v3 fallback**

In `ProfileStore.swift`, update the `Keys` enum:

```swift
private enum Keys {
    static let profiles = "profiles_v4"      // Updated from profiles_v3
    static let legacyProfiles = "profiles_v3" // Fallback for migration
    static let activeProfileId = "activeProfileId"
    static let displayMode = "profileDisplayMode"
    static let multiProfileConfig = "multiProfileDisplayConfig"
}
```

Update `loadProfiles()` to try v4 first, fall back to v3:

```swift
func loadProfiles() -> [Profile] {
    // Try v4 first
    if let data = defaults.data(forKey: Keys.profiles) {
        do {
            let profiles = try JSONDecoder().decode([Profile].self, from: data)
            LoggingService.shared.log("ProfileStore: Loaded \(profiles.count) profiles from v4 storage")
            return profiles
        } catch {
            LoggingService.shared.logStorageError("loadProfiles v4", error: error)
        }
    }

    // Fall back to v3 (existing profiles without new fields)
    if let data = defaults.data(forKey: Keys.legacyProfiles) {
        do {
            let profiles = try JSONDecoder().decode([Profile].self, from: data)
            LoggingService.shared.log("ProfileStore: Migrated \(profiles.count) profiles from v3 to v4")
            // Save as v4 immediately
            saveProfiles(profiles)
            return profiles
        } catch {
            LoggingService.shared.logStorageError("loadProfiles v3 migration", error: error)
        }
    }

    LoggingService.shared.log("ProfileStore: No profiles found in storage")
    return []
}
```

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/Shared/Storage/ProfileStore.swift"
git commit -m "feat: add profiles_v4 storage with v3 fallback migration"
```

---

### Task 13: Extend ProfileManager with factory methods

**Files:**
- Modify: `Claude Usage/Shared/Services/ProfileManager.swift`

- [ ] **Step 1: Add factory methods for new provider types**

Add these methods to `ProfileManager`:

```swift
/// Create a new OpenAI API profile
func createOpenAIAPIProfile(name: String, adminKey: String, organizationId: String? = nil) -> Profile {
    let profile = Profile(
        name: name,
        providerType: .openaiAPI,
        openaiAdminKey: adminKey,
        openaiOrganizationId: organizationId
    )
    profiles.append(profile)
    saveAndBroadcast()
    return profile
}

/// Create a new Codex probe profile
func createCodexProfile(name: String, apiKey: String) -> Profile {
    let profile = Profile(
        name: name,
        providerType: .codex,
        openaiApiKey: apiKey
    )
    profiles.append(profile)
    saveAndBroadcast()
    return profile
}

/// Create a new Claude API billing profile
func createClaudeAPIProfile(name: String, apiSessionKey: String, apiOrganizationId: String) -> Profile {
    let profile = Profile(
        name: name,
        providerType: .claudeAPI,
        apiSessionKey: apiSessionKey,
        apiOrganizationId: apiOrganizationId
    )
    profiles.append(profile)
    saveAndBroadcast()
    return profile
}

/// Helper to save and broadcast changes
private func saveAndBroadcast() {
    ProfileStore.shared.saveProfiles(profiles)
    objectWillChange.send()
}
```

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/Shared/Services/ProfileManager.swift"
git commit -m "feat: add ProfileManager factory methods for OpenAI, Codex, and Claude API profiles"
```

---

## Phase 4: UI

### Task 14: OpenAI credential entry view

**Files:**
- Create: `Claude Usage/Views/Credentials/OpenAICredentialView.swift`

- [ ] **Step 1: Create the view**

```swift
// Claude Usage/Views/Credentials/OpenAICredentialView.swift

import SwiftUI

struct OpenAICredentialView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var profileManager = ProfileManager.shared

    let providerType: ProfileProviderType // .openaiAPI or .codex
    @State private var name: String = ""
    @State private var apiKey: String = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var validationSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(providerType == .openaiAPI ? "Add OpenAI API" : "Add Codex")
                .font(.headline)

            TextField("Display Name", text: $name)
                .textFieldStyle(.roundedBorder)

            SecureField(
                providerType == .openaiAPI ? "Admin API Key (sk-admin-...)" : "API Key (sk-...)",
                text: $apiKey
            )
            .textFieldStyle(.roundedBorder)

            if providerType == .openaiAPI {
                Text("Requires an Admin API key from platform.openai.com/settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tracks API rate limits via probe requests. This is NOT your Codex subscription quota.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if validationSuccess {
                Text("Connected successfully!")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Validate & Save") {
                    Task { await validateAndSave() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.isEmpty || name.isEmpty || isValidating)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            name = providerType == .openaiAPI ? "OpenAI API" : "Codex"
        }
    }

    private func validateAndSave() async {
        isValidating = true
        validationError = nil
        validationSuccess = false

        let profile: Profile
        if providerType == .openaiAPI {
            profile = Profile(name: name, providerType: .openaiAPI, openaiAdminKey: apiKey)
        } else {
            profile = Profile(name: name, providerType: .codex, openaiApiKey: apiKey)
        }

        let provider = UsageProviderFactory.makeProvider(for: profile)
        do {
            let isValid = try await provider.validateCredentials(for: profile)
            if isValid {
                if providerType == .openaiAPI {
                    _ = profileManager.createOpenAIAPIProfile(name: name, adminKey: apiKey)
                } else {
                    _ = profileManager.createCodexProfile(name: name, apiKey: apiKey)
                }
                validationSuccess = true
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            } else {
                validationError = "Credentials are invalid. Check your API key."
            }
        } catch {
            validationError = error.localizedDescription
        }

        isValidating = false
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/Views/Credentials/OpenAICredentialView.swift"
git commit -m "feat: add OpenAI and Codex credential entry views"
```

---

### Task 15: Provider type picker for new profiles

**Files:**
- Create: `Claude Usage/Views/Settings/AddProviderView.swift`

- [ ] **Step 1: Create the picker view**

```swift
// Claude Usage/Views/Settings/AddProviderView.swift

import SwiftUI

struct AddProviderView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedType: ProfileProviderType?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Service")
                .font(.headline)

            Text("Choose what you want to track:")
                .foregroundStyle(.secondary)

            ForEach(ProfileProviderType.allCases, id: \.self) { type in
                Button(action: { selectedType = type }) {
                    HStack(spacing: 12) {
                        Image(systemName: type.iconSystemName)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(type.displayName)
                                .fontWeight(.medium)
                            Text(typeDescription(type))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(selectedType == type ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 400)
        .sheet(item: $selectedType) { type in
            switch type {
            case .claudeMax:
                // Reuse existing credential setup flow
                Text("Use the existing Claude setup wizard for Claude Max accounts")
                    .padding()
            case .claudeAPI:
                Text("Use the existing API billing setup for Claude API")
                    .padding()
            case .openaiAPI:
                OpenAICredentialView(providerType: .openaiAPI)
            case .codex:
                OpenAICredentialView(providerType: .codex)
            }
        }
    }

    private func typeDescription(_ type: ProfileProviderType) -> String {
        switch type {
        case .claudeMax: return "Track Claude subscription session and weekly limits"
        case .claudeAPI: return "Track Anthropic API billing and spend"
        case .openaiAPI: return "Track OpenAI API billing and spend (requires Admin key)"
        case .codex: return "Track OpenAI API rate limits via probe requests"
        }
    }
}

extension ProfileProviderType: Identifiable {
    var id: String { rawValue }
}
```

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/Views/Settings/AddProviderView.swift"
git commit -m "feat: add provider type picker for new profile creation"
```

---

### Task 16: Extend PopoverContentView with 3-section layout

**Files:**
- Modify: `Claude Usage/MenuBar/PopoverContentView.swift`

- [ ] **Step 1: Add section views for the new providers**

Add these views to `PopoverContentView.swift` (or a new file `PopoverSections.swift` if the file is already large):

```swift
// Add to PopoverContentView.swift or create Claude Usage/MenuBar/PopoverSections.swift

import SwiftUI

/// Section showing OpenAI API billing in the popover
struct OpenAIBillingSection: View {
    let profile: Profile

    var body: some View {
        if let usage = profile.openaiUsage {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(profile.name)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                    Spacer()
                    Text("Resets \(usage.resetsAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("This month")
                    Spacer()
                    Text(usage.formattedUsed)
                        .foregroundStyle(.blue)
                }
                .font(.caption)

                if let budget = profile.spendBudgetCents, budget > 0 {
                    let remaining = Double(budget - usage.currentSpendCents) / 100.0
                    HStack {
                        Text("Budget remaining")
                        Spacer()
                        Text("$\(String(format: "%.2f", remaining))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

/// Section showing Codex rate limits in the popover
struct CodexSection: View {
    let profile: Profile

    var body: some View {
        if let usage = profile.codexUsage {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(profile.name)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                    Spacer()
                    Text("Resets \(usage.requestResetTime, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Requests bar (primary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Requests")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                        Spacer()
                        Text("\(String(format: "%.0f", usage.requestPercentageUsed))%")
                            .font(.caption2)
                    }
                    ProgressView(value: usage.requestPercentageUsed, total: 100)
                        .tint(.purple)
                }

                // Tokens bar (secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(String(format: "%.0f", usage.tokenPercentageUsed))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: usage.tokenPercentageUsed, total: 100)
                        .tint(.secondary)
                }

                Text("OpenAI API Rate Limits")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/MenuBar/PopoverContentView.swift"
git commit -m "feat: add OpenAI billing and Codex rate-limit popover sections"
```

---

### Task 17: Rebrand app entry point

**Files:**
- Modify: `Claude Usage/App/ClaudeUsageTrackerApp.swift`

- [ ] **Step 1: Rename the app struct**

```swift
// Claude Usage/App/ClaudeUsageTrackerApp.swift

import SwiftUI

@main
struct AIUsageTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
```

Note: The bundle identifier change (`HamedElfayome.Claude-Usage` → new identifier) is done in the Xcode project settings, not in Swift code. That can be configured in Xcode's target settings.

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/App/ClaudeUsageTrackerApp.swift"
git commit -m "refactor: rebrand app entry point to AIUsageTrackerApp"
```

---

## Phase 5: Integration

### Task 18: Wire up MenuBarManager for multi-provider display

**Files:**
- Modify: `Claude Usage/MenuBar/MenuBarManager.swift`

- [ ] **Step 1: Add OpenAI/Codex usage properties and smart status bar integration**

Add to `MenuBarManager` published properties:

```swift
// After existing @Published properties (around line 18)
@Published private(set) var allProfileUsages: [UUID: ProfileUsageUpdate] = [:]
```

Implement the new delegate methods:

```swift
// MARK: - Multi-Provider Support

func profileUsageDidUpdate(profileId: UUID, update: ProfileUsageUpdate) {
    allProfileUsages[profileId] = update

    // Update the profile's stored usage data
    if var profile = profileManager.profiles.first(where: { $0.id == profileId }) {
        if let claudeUsage = update.claudeUsage {
            profile.claudeUsage = claudeUsage
        }
        if let apiUsage = update.apiUsage {
            profile.apiUsage = apiUsage
        }
        if let openaiUsage = update.openaiUsage {
            profile.openaiUsage = openaiUsage
        }
        if let codexUsage = update.codexUsage {
            profile.codexUsage = codexUsage
        }
        profileManager.updateProfile(profile)
    }

    // Re-evaluate smart status bar
    updateSmartStatusBar()
}

func profileRefreshDidFail(profileId: UUID, error: Error) {
    LoggingService.shared.logError("Refresh failed for profile \(profileId): \(error.localizedDescription)")
}

private func updateSmartStatusBar() {
    let profilesForBar = SmartStatusBarRenderer.profilesForStatusBar(
        profileManager.profiles,
        threshold: UserDefaults.standard.double(forKey: "statusBarThreshold").nonZeroOr(60),
        maxItems: UserDefaults.standard.integer(forKey: "statusBarMaxItems").nonZeroOr(4)
    )

    // Update status bar items based on profilesForBar
    // This integrates with the existing icon rendering system
    objectWillChange.send()
}
```

Add this small extension for safe defaults:

```swift
private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double {
        self > 0 ? self : fallback
    }
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int {
        self > 0 ? self : fallback
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/MenuBar/MenuBarManager.swift"
git commit -m "feat: wire up MenuBarManager for multi-provider usage and smart status bar"
```

---

### Task 19: Extend UsageHistoryService with new snapshot types

**Files:**
- Modify: `Claude Usage/Shared/Services/UsageHistoryService.swift`

- [ ] **Step 1: Add OpenAI and Codex recording methods**

Add to `UsageHistoryService`:

```swift
/// Record OpenAI cost snapshot (called on each OpenAI API refresh)
func recordOpenAICost(for profileId: UUID, usage: OpenAIUsage) {
    var history = loadHistory(for: profileId)
    let snapshot = UsageSnapshot(
        timestamp: usage.lastUpdated,
        sessionPercentage: nil,
        weeklyPercentage: nil,
        opusPercentage: nil,
        sonnetPercentage: nil,
        apiSpendCents: usage.currentSpendCents,
        snapshotType: "openaiCost"
    )
    history.snapshots.append(snapshot)
    // Keep last 500 OpenAI snapshots
    let openaiSnapshots = history.snapshots.filter { $0.snapshotType == "openaiCost" }
    if openaiSnapshots.count > 500 {
        let excess = openaiSnapshots.count - 500
        history.snapshots.removeAll { $0.snapshotType == "openaiCost" }
        history.snapshots.append(contentsOf: Array(openaiSnapshots.dropFirst(excess)))
    }
    saveHistory(history, for: profileId)
}

/// Record Codex rate-limit snapshot
func recordCodexRateLimit(for profileId: UUID, usage: CodexUsage) {
    var history = loadHistory(for: profileId)
    let snapshot = UsageSnapshot(
        timestamp: usage.lastUpdated,
        sessionPercentage: usage.requestPercentageUsed,
        weeklyPercentage: usage.tokenPercentageUsed,
        opusPercentage: nil,
        sonnetPercentage: nil,
        apiSpendCents: nil,
        snapshotType: "codexRateLimit"
    )
    history.snapshots.append(snapshot)
    let codexSnapshots = history.snapshots.filter { $0.snapshotType == "codexRateLimit" }
    if codexSnapshots.count > 500 {
        let excess = codexSnapshots.count - 500
        history.snapshots.removeAll { $0.snapshotType == "codexRateLimit" }
        history.snapshots.append(contentsOf: Array(codexSnapshots.dropFirst(excess)))
    }
    saveHistory(history, for: profileId)
}
```

Note: This extends `UsageSnapshot` to include a `snapshotType` field and `apiSpendCents` field. Check if the existing model needs these additions — if `UsageSnapshot` doesn't have a `snapshotType` field, add it as an optional `String?` with backward-compatible decoding.

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/Shared/Services/UsageHistoryService.swift"
git commit -m "feat: add OpenAI and Codex history snapshot recording"
```

---

### Task 20: Extend NotificationManager for provider-aware thresholds

**Files:**
- Modify: `Claude Usage/Shared/Services/NotificationManager.swift`

- [ ] **Step 1: Add provider-aware notification checking**

Add to `NotificationManager`:

```swift
/// Check and notify for any provider type based on profile settings
func checkAndNotifyForProfile(_ profile: Profile) {
    guard profile.notificationSettings.enabled else { return }

    guard let percentage = profile.effectivePercentageForThreshold else { return }

    let thresholds = profile.notificationSettings.sortedThresholds

    for threshold in thresholds {
        if percentage >= Double(threshold) {
            let title: String
            switch profile.providerType {
            case .claudeMax:
                let model = profile.primaryModel ?? "opus"
                title = "\(profile.name) — \(model.capitalized) at \(Int(percentage))%"
            case .claudeAPI:
                title = "\(profile.name) — Claude API spend alert"
            case .openaiAPI:
                title = "\(profile.name) — OpenAI API spend alert"
            case .codex:
                title = "\(profile.name) — Codex rate limit at \(Int(percentage))%"
            }

            sendNotificationIfNeeded(
                identifier: "\(profile.id.uuidString)-\(threshold)",
                title: title,
                body: "Usage has reached \(threshold)%",
                sound: profile.notificationSettings.notificationSound
            )
        }
    }
}

private func sendNotificationIfNeeded(identifier: String, title: String, body: String, sound: UNNotificationSound?) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = sound

    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
}
```

- [ ] **Step 2: Commit**

```bash
git add "Claude Usage/Shared/Services/NotificationManager.swift"
git commit -m "feat: add provider-aware notification thresholds"
```

---

## Verification

### Task 21: Build verification

- [ ] **Step 1: Build the project**

Run: `xcodebuild build -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" 2>&1 | tail -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run all tests**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS" 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 3: Fix any build errors or test failures**

If there are Xcode project file issues (new files not added to target), add them via:
- Open the `.xcodeproj/project.pbxproj` and add file references, OR
- Open in Xcode and add files to the appropriate target

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "fix: resolve any build issues from multi-provider integration"
```

---

## Summary

| Phase | Tasks | What it delivers |
|---|---|---|
| **Phase 1: Models** | Tasks 1-4 | `ProfileProviderType`, `OpenAIUsage`, `CodexUsage`, extended `Profile` |
| **Phase 2: Providers** | Tasks 5-9 | `UsageProvider` protocol, all 4 provider implementations |
| **Phase 3: Infrastructure** | Tasks 10-13 | Smart status bar, variable refresh, storage migration, profile factory |
| **Phase 4: UI** | Tasks 14-16 | Credential views, provider picker, popover sections |
| **Phase 5: Integration** | Tasks 17-21 | Rebrand, wiring, history, notifications, build verification |
