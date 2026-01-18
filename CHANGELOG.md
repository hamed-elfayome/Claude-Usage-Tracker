# Changelog

All notable changes to Claude Usage Tracker will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.2] - 2026-01-18

### Added

#### CLI OAuth Authentication Fallback
- **Robust authentication system** with automatic fallback
  - Prioritizes claude.ai session key as primary authentication method
  - Falls back to Claude Code CLI OAuth when session key unavailable
  - System Keychain integration for CLI OAuth tokens
  - Automatic token expiration checking in Profile model
  - Seamless authentication without user intervention

### Changed

#### Auto-Start Session Improvements
- **Simplified auto-start logic** for better reliability
  - Removed complex reset detection mechanism
  - Direct 0% session check for cleaner trigger logic
  - Updated model selection to ensure proper usage tracking
  - More predictable auto-start behavior

### Technical Improvements

- Enhanced ClaudeAPIService with multi-authentication support
- ClaudeCodeSyncService improvements for better token management
- Network client entitlements for proper API access
- Image asset refinements

---

## [2.2.1] - 2026-01-14

### Added
- **Sonnet Weekly Usage Tracking**: Display Claude Sonnet 3.5 specific weekly usage alongside total weekly usage
  - New `sonnetWeeklyTokensUsed` and `sonnetWeeklyPercentage` fields in ClaudeUsage model
  - Added to popover display with localization support in all 8 languages
  - Parsed from `seven_day_sonnet_3_5` API field

### Fixed
- **Auto-Start Session Reliability**: Fixed auto-start sessions not working after Mac sleep/wake
  - Added `NSWorkspace.didWakeNotification` observer to detect Mac wake events
  - Performs immediate check when Mac wakes from sleep to catch session resets that occurred during sleep
  - Added immediate initial check on service startup to populate state correctly
  - Implemented debouncing (10-second window) to prevent duplicate checks
  - Set timer tolerance to 30 seconds for energy efficiency
  - Sessions now reliably auto-start even after extended sleep periods

---

## [2.2.0] - 2026-01-12

### Major Release - Multi-Profile Management System 

This major release introduces comprehensive multi-profile support, allowing you to manage unlimited Claude accounts with automatic credential switching and per-profile settings. Combined with Claude Code CLI integration and Korean language support, v2.2.0 represents a significant evolution of the application.

### Added

#### Multi-Profile System
- **Unlimited Profiles**: Create and manage unlimited profiles for different Claude accounts
  - Each profile has isolated credentials, settings, and usage data
  - Fun auto-generated names ("Quantum Llama", "Sneaky Penguin", "Turbo Sloth", etc.)
  - Custom naming support - rename profiles to whatever you prefer
  - Profile deletion (minimum 1 profile enforced)
  - Last used timestamp tracking

- **Profile Switcher**: Quick profile switching in multiple locations
  - Popover header dropdown with profile badges
  - Settings sidebar picker with visual indicators
  - Dedicated "Manage Profiles" tab for full profile management
  - Profile badges show Claude.ai and CLI credential status

- **Per-Profile Settings**: Each profile maintains independent configuration
  - Credentials: Claude.ai session key, organization ID, API keys
  - Appearance: Icon style, monochrome mode (5 icon styles available)
  - Refresh interval: 5-300 seconds
  - Auto-start sessions: Enable/disable per profile
  - Notifications: Independent threshold alerts (75%, 90%, 95%)
  - Usage data: Tracked and stored separately per profile

#### Claude Code CLI Integration
- **ClaudeCodeSyncService**: New service for CLI credential management
  - One-click sync from currently logged-in Claude Code account
  - Reads credentials from system Keychain (`Claude Code-credentials`)
  - Stores credentials per-profile for isolated management
  - Security command integration for Keychain read/write operations

- **Automatic Credential Switching**: Seamless CLI account switching
  - When changing profiles, CLI credentials automatically update
  - System Keychain updated with selected profile's credentials
  - Claude Code automatically switches to the profile's account
  - Smart re-sync before switching captures any CLI login changes

- **CLI Account Settings Tab**: Dedicated UI for CLI management
  - Sync status display (synced/not synced)
  - Masked access token display
  - Subscription type and scopes information
  - One-click sync and remove operations
  - Last synced timestamp

- **Automatic Statusline Updates**: Terminal statusline stays in sync
  - Statusline scripts auto-update when switching profiles
  - Organization ID and session key injected automatically
  - No manual reconfiguration needed

#### Auto-Start Session Service (Per-Profile)
- **AutoStartSessionService**: Background monitoring for all profiles
  - 5-minute check cycle monitors all profiles with auto-start enabled
  - Detects session resets (usage drops to 0%)
  - Automatically initializes new sessions using Claude 3.5 Haiku
  - Per-profile auto-start toggle in General settings
  - Notification on successful auto-start
  - Works independently for each profile

#### Korean Language Support
- **8th Language Added**: Full Korean (한국어) localization
  - 497 localized strings added to ko.lproj/Localizable.strings
  - Complete UI translation for all new features
  - Profile management, CLI account, and settings strings
  - Language badge: 🇰🇷

#### Reorganized Settings Interface
- **New Settings Structure**: Modern sidebar with profile switcher
  - Profile switcher at top of sidebar
  - Credentials section: Claude.AI, API Console, CLI Account
  - Profile Settings: Appearance, General
  - App-Wide Settings: Manage Profiles, Language, Claude Code, Updates, About

- **New Settings Tabs**:
  - **Manage Profiles**: Full profile CRUD operations
  - **CLI Account**: Claude Code credential sync management
  - **Language Settings**: Dedicated language selection tab (previously in General)

- **DesignTokens**: Centralized design system
  - Typography, spacing, colors, icons standardized
  - Consistent UI across all settings views
  - Reusable components (SettingsComponents.swift)

#### New Models & Architecture
- **Profile Model** (Shared/Models/Profile.swift)
  - Complete profile representation with all settings
  - Credentials stored directly in profile (encrypted in UserDefaults)
  - Computed properties: hasClaudeAI, hasAPIConsole, hasUsageCredentials
  - Per-profile usage data storage

- **ProfileManager** (Shared/Services/ProfileManager.swift)
  - Centralized profile lifecycle management
  - Observable with `@Published` properties (Combine framework)
  - Async profile activation with CLI credential sync
  - Thread-safe switching with semaphore
  - Create, update, delete, toggle selection operations

- **ProfileStore** (Shared/Storage/ProfileStore.swift)
  - Profile-specific storage (separate from app-wide settings)
  - Saves/loads profiles, active profile ID, display mode
  - UserDefaults integration with App Groups support

- **SharedDataStore** (Shared/Storage/SharedDataStore.swift)
  - App-wide settings (language, statusline, GitHub prompt, etc.)
  - Separated from profile-specific DataStore

- **ProfileMigrationService** (Shared/Services/ProfileMigrationService.swift)
  - Automatic migration from v2.1.x to multi-profile system
  - Migrates credentials from old Keychain keys
  - Migrates settings (icon config, refresh interval, notifications, auto-start)
  - One-time migration on first launch of v2.2.0
  - Migration flag: `didMigrateToProfilesV3`

- **FunnyNameGenerator** (Shared/Utilities/FunnyNameGenerator.swift)
  - 30 fun profile names (Quantum Llama, Sneaky Penguin, Turbo Sloth, etc.)
  - Ensures uniqueness across profiles
  - Fallback to "Profile XXXX" when names exhausted

- **NotificationSettings Model** (Shared/Models/NotificationSettings.swift)
  - Per-profile notification configuration
  - Threshold toggles: 75%, 90%, 95%
  - Profile name for notification messages

- **ProfileDisplayMode Enum** (Shared/Models/ProfileDisplayMode.swift)
  - `.single`: Show only active profile (current implementation)
  - `.multi`: Reserved for future multi-profile menu bar display

#### New Views
- **ManageProfilesView** (Views/Settings/App/ManageProfilesView.swift)
  - Full profile management interface
  - Profile list with inline name editing
  - Create, delete, activate operations
  - Profile status badges
  - Info card explaining profile features

- **CLIAccountView** (Views/Settings/Credentials/CLIAccountView.swift)
  - CLI account sync management
  - Status card with sync indicator
  - Credential display (masked tokens)
  - Subscription info display
  - Sync and remove operations

- **LanguageSettingsView** (Views/Settings/App/LanguageSettingsView.swift)
  - Dedicated language selection interface
  - Previously embedded in General settings
  - 8 language options with flags

- **Reorganized Settings Views**:
  - PersonalUsageView → Views/Settings/Credentials/
  - APIBillingView → Views/Settings/Credentials/
  - AppearanceSettingsView → Views/Settings/Profile/
  - GeneralSettingsView → Views/Settings/Profile/

#### Enhanced Localization
- **200+ New Strings Per Language**:
  - Profile management strings
  - CLI account strings
  - Settings reorganization strings
  - New tabs and sections
  - All 7 existing languages updated (de, en, es, fr, it, ja, pt)

### Changed

#### Settings Architecture
- **Sidebar-Based Navigation**: Replaced tab-based settings with sidebar
  - Profile switcher integrated into sidebar
  - Credentials, Profile Settings, and App Settings sections
  - More scalable for future features

- **Profile-Aware Components**: All settings respect active profile
  - Credentials apply to active profile only
  - Appearance changes affect active profile
  - Notifications configured per profile

- **SettingsSection Enum**: Expanded and reorganized
  - Credentials: `.claudeAI`, `.apiConsole`, `.cliAccount`
  - Profile Settings: `.appearance`, `.general`
  - App-Wide: `.manageProfiles`, `.language`, `.claudeCode`, `.updates`, `.about`

#### Popover Interface
- **Profile Switcher Header**: New compact profile selector
  - Dropdown menu showing all profiles
  - Profile badges (CLI , Claude.ai , active indicator)
  - "Manage Profiles" quick action
  - Active profile name prominently displayed

#### Data Storage
- **Profile-Based Storage**: Credentials now stored per-profile
  - Each profile stores credentials directly in Profile model
  - Encrypted in UserDefaults (App Groups)
  - No more shared session keys

- **Separated Datastores**:
  - ProfileStore: Profile-specific data
  - SharedDataStore: App-wide settings (language, statusline, etc.)
  - DataStore: Legacy compatibility (being phased out)

#### Menu Bar Manager
- **Profile-Aware Refresh**: Fetches usage for active profile
  - Observes ProfileManager `@Published` properties via Combine
  - Automatic data refresh on profile switch
  - Updates menu bar icons with active profile's configuration
  - Restart refresh timer with profile's interval

- **Automatic Profile Switch Handling**:
  - Clears current usage data before switch
  - Updates refresh interval from new profile
  - Triggers immediate refresh after activation
  - Updates statusline scripts if credentials available

### Fixed

#### Migration Integration
- **ProfileMigrationService Now Called**: Added to AppDelegate
  - Migration runs before ProfileManager.loadProfiles()
  - Automatically migrates v2.1.x settings to first profile
  - Credentials, icon config, refresh interval, notifications preserved
  - One-time migration with flag tracking

### Technical Improvements

#### Architecture
- **Protocol-Oriented Design**: ProfileManager uses Observable pattern
  - `@Published` properties for reactive UI updates
  - Combine framework integration
  - Main Actor isolation for thread safety

- **Service Layer**:
  - ClaudeCodeSyncService for CLI integration
  - AutoStartSessionService for background monitoring
  - ProfileMigrationService for seamless upgrades

- **Centralized Profile Activation**:
  - Single `activateProfile(id)` method handles all switches
  - Automatic CLI credential application
  - Statusline script updates
  - Re-sync of current profile before leaving

#### Code Organization
- **20 New Files Added**:
  - 4 Models: Profile, NotificationSettings, ProfileDisplayMode, (+ ProfileCredentials)
  - 4 Services: ProfileManager, ClaudeCodeSyncService, AutoStartSessionService, ProfileMigrationService
  - 2 Storage: ProfileStore, SharedDataStore
  - 1 Utility: FunnyNameGenerator
  - 6 Views: ManageProfilesView, CLIAccountView, LanguageSettingsView, + reorganized credential views
  - 3 Components: DesignTokens, SettingsComponents, ThresholdIndicator

- **File Reorganization**:
  - Settings views organized into subdirectories (Credentials/, Profile/, App/)
  - Cleaner project structure
  - Better separation of concerns

#### Stats
- **64 Files Changed**: 8,201 insertions(+), 2,409 deletions(-)
- **Net Addition**: ~5,800 lines of code
- **New Swift Files**: 20
- **Updated Localizations**: 8 languages (7 existing + 1 new Korean)

### Breaking Changes

#### Automatic Migration
- **First Launch Migration**: Automatic conversion to multi-profile system
  - Existing configuration becomes first profile
  - Fun name auto-generated (e.g., "Quantum Llama")
  - All credentials and settings preserved
  - Old Keychain keys kept for safety (can be cleaned up later)
  - Migration flag prevents re-running

#### Storage Changes
- **Profile-Based Storage**: Credentials now per-profile
  - Old single-set credentials migrated to first profile
  - New profiles start fresh
  - App Groups UserDefaults for future widget support

### Security Notes

- **CLI Credentials Stored Securely**: Per-profile in UserDefaults (encrypted)
- **System Keychain Integration**: Reads/writes Claude Code credentials via `security` command
- **Credential Isolation**: Each profile's credentials completely isolated
- **Migration Safety**: Old Keychain keys preserved during migration

---

## [2.1.2] - 2026-01-10

### Fixed

#### Statusline Script Updates
- **Conditional Script Updates** - Scripts now only update if already installed
  - Added `updateScriptsIfInstalled()` method with installation check
  - Prevents errors when statusline is not configured
  - Changed `isInstalled()` to computed property for cleaner syntax
  - Fixes issue where app tried to update non-existent scripts

#### Organization ID Handling
- **Direct Organization Injection** - Organization ID now injected into scripts instead of fetching via API
  - Removed API call from Swift statusline script (`fetchOrganizationId()`)
  - Organization ID read from injected value (similar to session key)
  - Eliminates unnecessary network requests during statusline execution
  - Improves performance and reliability

#### Error Handling
- **New Error Case** - Added `organizationNotConfigured` error
  - Clear error message when organization not set
  - Better user feedback during statusline configuration
  - Prevents script installation with incomplete settings

### Contributors
- [@oomathias](https://github.com/oomathias) - Organization ID injection fix

---

## [2.1.1] - 2026-01-05

### Added

#### Next Session Time Display (contributed by [@khromov](https://github.com/khromov))
- **Session reset countdown in menu bar icon** - See exactly when your next 5-hour session starts
  - Displays time until next session in HH:MM format (e.g., "2:45" for 2 hours 45 minutes)
  - Shows "in <1h" when less than an hour remains
  - Automatically updates as time progresses
  - Toggle on/off in Appearance Settings
  - Works with all icon styles
  - Clean, compact display that fits naturally in the menu bar

#### Enhanced Date Utilities
- **New time formatting helpers** in Date+Extensions
  - `timeUntilSessionReset(from:)` - Calculates hours and minutes until next session
  - `formattedTimeUntilReset(from:)` - Returns human-readable time string

### Changed

#### Menu Bar Icon Configuration
- **Extended MenuBarIconConfig** - New `showTimeToNextSession` property
  - Per-metric configuration support
  - Persistent storage via DataStore
  - Default: enabled for better user awareness

#### Appearance Settings
- **Session time toggle** - New option in Appearance Settings tab
  - Easy enable/disable of time-to-next-session display
  - Located in MetricIconCard for per-metric control
  - Applies to all configured menu bar icons

### Fixed

- **Time formatting for sessions under 1 hour** - Fixed display bug showing incorrect format
  - Properly shows "in <1h" when less than 60 minutes remain
  - Prevents confusion with negative or invalid time displays

### Contributors
- [@khromov](https://github.com/khromov) (Stanislav Khromov) - Next session time display feature

---

## [2.1.0] - 2025-12-29

### Enhanced User Experience - Smart Setup Wizard & Modern APIs

This release brings a completely redesigned setup experience with a 3-step wizard flow that makes configuration intuitive and error-free. Combined with modernized notification APIs and critical UX fixes, v2.1.0 significantly improves the onboarding and daily usage experience.

### Added

#### 3-Step Wizard Setup Flow (contributed by [@alexbartok](https://github.com/alexbartok))
- **Redesigned Initial Setup Wizard** - Complete overhaul of first-run experience
  - **Step 1: Enter Session Key** - Test your session key without saving
    - Non-destructive validation using new `testSessionKey()` API method
    - Discovers all organizations associated with your account
    - Clear validation feedback with detailed error messages
    - Auto-advances to next step on success

  - **Step 2: Select Organization** - Choose which organization to track
    - Visual organization selector with radio buttons
    - Displays organization name and UUID
    - Auto-selects first organization for convenience
    - Prevents common 403 errors from wrong organization selection

  - **Step 3: Confirm & Save** - Review and finalize configuration
    - Configuration summary with masked session key
    - Selected organization details
    - Auto-start session toggle (moved from Step 1)
    - Only saves to Keychain when explicitly confirmed

- **Visual Progress Indicator**
  - Step circles (1, 2, 3) with color-coded states
  - Connecting lines turn green when steps are completed
  - Current step highlighted in accent color
  - Completed steps show checkmark icons

- **Personal Usage Settings Wizard** - Settings tab now uses same 3-step flow
  - Consistent UX between initial setup and settings configuration
  - Smart organization preservation (only clears when key actually changes)
  - Clear navigation with Back/Next buttons
  - Prevents accidental data loss during reconfiguration

#### Modern Notification System
- **UNUserNotificationCenter Integration** - Replaced deprecated macOS 11.0 APIs
  - Migrated from `NSUserNotification` to `UNUserNotificationCenter`
  - All notifications now use modern UserNotifications framework
  - Success notifications for user-triggered actions
  - Proper notification categories (`SUCCESS_ALERT`, `INFO_ALERT`, `USAGE_ALERT`)

- **Centralized Notification Architecture**
  - New `sendSuccessNotification()` method in NotificationManager
  - All notification logic consolidated in NotificationManager service
  - Silent success notifications (no sound, 2-second auto-dismiss)
  - Consistent error logging and handling

### Changed

#### API Service Enhancements (contributed by [@alexbartok](https://github.com/alexbartok))
- **Non-Destructive Session Key Testing**
  - New `testSessionKey()` method validates without saving to Keychain
  - Returns list of discovered organizations
  - Prevents premature saving that caused configuration issues
  - Enables proper organization selection before commitment

- **Smart Organization Preservation**
  - Enhanced `saveSessionKey()` with `preserveOrgIfUnchanged` parameter
  - Only clears organization ID when session key actually changes
  - Prevents data loss during reconfiguration
  - Targeted refresh notifications (session key vs. organization changes)

- **Notification Extensions**
  - New `.organizationChanged` notification for independent organization updates
  - MenuBarManager observes organization changes separately from session key
  - More granular refresh control

### Fixed

#### Menu Bar Icon Flicker (contributed by [@alexbartok](https://github.com/alexbartok))
- **Smooth Refresh Experience** - Icons no longer briefly show zeros during data refresh
  - Removed clearing of usage data during refresh process
  - Old data remains visible until new data arrives
  - Prevents visual "flashing" that was jarring to users
  - Maintains professional appearance during background updates

#### Setup Wizard Issues (contributed by [@alexbartok](https://github.com/alexbartok))
- **Fixed 403 Errors** - Resolved critical issue where saving after organization selection would fail
  - "Test Connection" and "Save" no longer clear organization IDs prematurely
  - Proper organization selection workflow prevents API authentication errors
  - Smart preservation ensures configuration consistency

- **Visual Guidance** - Users now have clear indication of setup progress
  - No more confusion about what step they're on
  - Clear path forward with visual progress indicator
  - Prevents incomplete configurations

#### Deprecation Warnings
- **Eliminated NSUserNotification Warnings** - Removed all 3 macOS 11.0 deprecation warnings
  - Replaced deprecated APIs throughout MenuBarManager
  - App now fully compatible with modern macOS notification system
  - Cleaner build output with no deprecation warnings
  - Future-proof notification implementation

### Technical Improvements

#### Architecture
- **Protocol Conformance** - NotificationManager follows service-oriented architecture
  - All notification code centralized in dedicated service
  - No direct UNUserNotificationCenter usage in MenuBarManager
  - Clean separation of concerns
  - Permission requests handled by AppDelegate with proper delegate setup

#### Code Organization
- **Wizard State Machine** - Proper state management for multi-step flows
  - `SetupWizardStep` enum for type-safe step tracking
  - `SetupWizardState` struct encapsulates all wizard data
  - Clean component separation (EnterKeyStepSetup, SelectOrgStepSetup, ConfirmStepSetup)
  - Reusable visual components (SetupStepCircle, SetupStepLine, SetupStepHeader)

#### DataStore Enhancements
- **Organization ID Management**
  - New methods for loading/saving organization IDs
  - Supports smart preservation logic
  - Clean data migration path

### Contributors
- [@alexbartok](https://github.com/alexbartok) (Alex Bartok) - 3-step wizard setup flow, organization selection, smart preservation logic, menu bar icon flicker fix

---

## [2.0.0] - 2025-12-28

### Major Release - Professional Grade Security & User Experience

This major release represents a significant milestone for Claude Usage Tracker, bringing professional-grade features including official Apple code signing, automatic updates, and enterprise-level security.

### Added

#### Official Apple Code Signing
- **Professionally signed application** with Apple Developer certificate
  - No more security warnings or workarounds on installation
  - Seamless installation experience like any other Mac app
  - Full macOS Gatekeeper compatibility
  - Users can now install by simply double-clicking the app

#### Automatic Updates (Sparkle Framework)
- **In-app update system** powered by Sparkle framework
  - Automatic update checking and notifications
  - One-click update installation
  - Secure update delivery with code signature verification
  - New Updates Settings tab for managing update preferences
  - Configurable update check frequency
  - Release notes displayed within the app

#### Enhanced Security
- **Keychain Integration** - Session keys now stored securely in macOS Keychain
  - Migration from file-based and UserDefaults storage to Keychain
  - Automatic one-time migration on first launch of v2.0
  - Enhanced security for API credentials
  - KeychainService and KeychainMigrationService implementation
  - Secure storage for both web and API session keys

#### Multi-Language Support (Internationalization)
- **6 Language Support** - Comprehensive localization across the entire application
  - English (en)
  - Spanish (es)
  - French (fr)
  - German (de)
  - Italian (it)
  - Portuguese (pt)
- **Language Switcher** in General Settings
  - LanguageManager and LocalizationManager for dynamic language switching
  - Localized strings for all UI components
  - Localized notification messages
  - Validation script for ensuring translation completeness

#### Multi-Metric Menu Bar Icons
- **Multiple Simultaneous Icons** - Display separate menu bar icons for different metrics
  - Configure independent icons for session, weekly, and opus usage
  - MenuBarIconConfig for flexible icon configuration
  - MenuBarIconRenderer for modular rendering logic
  - Per-metric customization (icon style, monochrome mode)
  - Global settings with metric-specific overrides

#### Advanced Error Handling System
- **Comprehensive Error Framework** - Professional error handling throughout the app
  - AppError enum with categorized error types
  - ErrorLogger for detailed error tracking
  - ErrorPresenter for user-friendly error messages
  - ErrorRecovery with automatic recovery suggestions
  - Enhanced error feedback in UI components
  - Improved debugging and troubleshooting

#### Session Key Validation
- **Robust Validation System** - Enhanced session key validation and API security
  - SessionKeyValidator with comprehensive validation rules
  - Format validation (sk-ant-sid01- prefix)
  - Length validation
  - Character set validation
  - URLBuilder for safer API endpoint construction
  - Comprehensive test coverage (SessionKeyValidatorTests, URLBuilderTests)

#### Network Monitoring
- **Network Change Detection** - Automatic network status monitoring
  - NetworkMonitor service for connectivity tracking
  - Automatic retry on network restoration
  - Better handling of offline scenarios
  - User feedback when network is unavailable

#### Launch at Login
- **System Auto-Start** - Launch the app automatically on macOS login
  - LaunchAtLoginManager for system integration
  - Toggle in Session Management settings
  - Proper cleanup on disable
  - System-level integration (not login item)

#### Code of Conduct
- **Contributor Covenant Code of Conduct** - Community guidelines and standards
  - Clear behavioral standards
  - Enforcement procedures
  - Community pledge

### Changed

#### API Service Architecture
- **Refactored API Service** - Cleaner, more maintainable code structure
  - ClaudeAPIService split into extensions (ConsoleAPI, Types)
  - Improved organization ID fetching with session key parameter
  - Enhanced error handling throughout API layer
  - Better separation of concerns

#### Icon Rendering System
- **Modularized Icon Rendering** - Extracted to dedicated components
  - MenuBarIconRenderer for centralized rendering logic
  - MenuBar/MenuBarManager+IconRendering.swift extension
  - Optimized appearance change observation
  - Better performance and maintainability

#### Popover Management
- **Multi-Popover Support** - Track and manage multiple menu bar buttons
  - currentPopoverButton tracking
  - Enhanced togglePopover for multiple buttons
  - Improved cleanup and resource management
  - Better state management

#### Setup Wizard
- **Streamlined First-Run Experience** - Simplified setup flow
  - Removed icon style settings from wizard
  - Immediate data refresh on session key save
  - Session key observer for reactive updates
  - Faster time-to-first-use

#### UI Refinements
- **Window Management** - All custom windows made non-restorable
  - Cleaner state management
  - Better user experience
  - Adjusted control sizes in popover and about view
  - Improved refresh button styling

### Technical Improvements

#### Testing
- **Comprehensive Test Coverage** - Added unit tests for critical components
  - SessionKeyValidatorTests - Validation logic testing
  - URLBuilderTests - API endpoint construction testing
  - DataStoreTests - Storage layer testing
  - DateExtensionsTests - Date utility testing
  - ClaudeUsageTests - Core functionality testing

#### CI/CD Pipeline
- **Automated Release Workflow** - Professional release pipeline
  - GitHub Actions for building, signing, and notarizing
  - Automatic appcast generation for Sparkle updates
  - Automated Homebrew cask updates
  - Changelog-based release notes
  - Code signing and notarization with Apple
  - Multi-step release process automation

#### Code Quality
- **Improved Code Organization** - Better structure and maintainability
  - Protocol-oriented design enhancements
  - Cleaner service layer
  - Reduced code duplication
  - Better whitespace and formatting consistency
  - Enhanced documentation

### Fixed

- **Migration Safety** - Keychain migration handles all edge cases
- **Network Resilience** - Better handling of network interruptions
- **Error Recovery** - Improved recovery from API failures
- **Multi-Display Support** - Better handling in multi-popover scenarios

### Breaking Changes

- **Keychain Migration** - Session keys automatically migrated from file/UserDefaults to Keychain
  - Migration happens automatically on first launch of v2.0
  - No user action required
  - Old storage methods deprecated
  - Users upgrading from v1.x will experience seamless migration

### Security Notes

- All session keys now stored in macOS Keychain (most secure option)
- App signed with Apple Developer certificate (enhanced trust)
- Automatic updates delivered over HTTPS with signature verification
- No breaking changes to API integration

---

## [1.6.2] - 2025-12-22

### Fixed

#### Settings UI Improvement
- **Fixed sidebar tab click area** in Settings window
    - Tabs now respond to clicks anywhere in the tab area, not just on the text
    - Added `.contentShape(Rectangle())` to make entire button area clickable
    - Improves user experience by making tab navigation more intuitive

### Changed

#### Release Pipeline Improvements
- **Fixed GitHub Actions release workflow** to create working app bundles
    - Added ad-hoc code signing to prevent "damaged app" errors on macOS
    - Changed from `zip` to `ditto` for ZIP creation to preserve code signatures
    - Updated from `macos-15` to `macos-14` runner for better compatibility
    - Removed `xcpretty` dependency that was causing build failures
- **Enhanced Homebrew Cask automation workflow**
    - Added download verification with file size checks
    - Added validation that cask file updates succeed
    - Better error handling throughout the workflow
- **Automated release process** now works end-to-end:
    1. Push tag → Builds app with signing
    2. Creates GitHub Release with working ZIP
    3. Automatically updates Homebrew tap

---

## [1.6.1] - 2025-12-21

### Fixed

#### Critical Performance Issue - High CPU Usage (Issue #48)
- **Resolved excessive CPU consumption** affecting users with multiple displays
    - Fixed 10-35% CPU usage during normal operation (now ~2-9%)
    - CPU usage was scaling with number of connected displays (14% single → 35% triple display)
    - Particularly affected users with:
        - Multiple displays (2-3 monitors)
        - High-end Macs (M2 Max, M1 Pro)
        - Retina displays
        - Stage Manager enabled

#### Root Cause
- Menu bar icon was being redrawn from scratch **every 30 seconds**
- macOS creates multiple "replicants" of menu bar items for each display, Space/Desktop, and Stage Manager
- Each redraw triggered complex bezier path drawing and forced macOS to re-render for every replicant
- ~45% of CPU time was spent in `_updateReplicantsUnlessMenuIsTracking` → `renderInContext`

#### Performance Optimizations Implemented
1. **Image Caching System** (MenuBar/MenuBarManager.swift)
    - Intelligent caching that only regenerates images when visual factors change
    - Cache key based on: percentage, appearance, icon style, and monochrome mode
    - 70% CPU reduction - Reuses cached images when nothing has changed

2. **Removed Deprecated UserDefaults.synchronize()** (Shared/Storage/DataStore.swift)
    - Removed 12 instances of blocking synchronize() calls
    - Deprecated since macOS 10.14 - UserDefaults auto-syncs periodically
    - 10% CPU reduction - Eliminated unnecessary main thread blocking

3. **Debounced Replicant Updates** (MenuBar/MenuBarManager.swift)
    - Added 100ms debounce timer to prevent rendering congestion
    - 10% CPU reduction - Prevents overlapping render operations

4. **Optimized Appearance Observer** (MenuBar/MenuBarManager.swift)
    - Changed from observing button appearance to NSApp appearance
    - 5% CPU reduction - Fewer redundant redraws

5. **Smart Cache Invalidation**
    - Cache clears only when necessary (appearance changes, icon style changes)
    - Forces fresh render only when visual factors actually change

#### Performance Results

| Configuration | Before | After | Improvement |
|---------------|--------|-------|-------------|
| Single Display | 14% | ~2-3% | **80% reduction** |
| Dual Display | 20-25% | ~4-6% | **75-80% reduction** |
| Triple Display | 30-35% | ~6-9% | **70-75% reduction** |

#### Technical Details
- Cache hit rate: Expected 95%+ (refresh every 30s, percentage changes slowly)
- Memory impact: +~50KB per cached image (negligible)
- Cached path: O(1) string comparison only
- Uncached path: O(n) full image rendering (unchanged)

---

## [1.6.0] - 2025-12-21

### Added

#### API Console Usage Tracking
- **New API Settings Tab** - Configure API console usage tracking separately from web usage
  - API session key input field with validation
  - Organization ID configuration
  - Dual tracking capability: Monitor both claude.ai web usage and API console usage simultaneously
  - API billing view integration

- **API Usage Display** - Enhanced popover shows API console usage data
  - Real-time API usage statistics
  - Separate tracking from web usage metrics
  - Seamless integration with existing usage views

- **ClaudeAPIService Enhancements** - Extended API service to support multiple endpoints
  - API console endpoint integration (`https://api.anthropic.com/v1/organization/{org_id}/usage`)
  - Dual authentication support (session cookie + API key)
  - Parallel usage data fetching for both web and API

#### Customizable Menu Bar Icon Styles
- **5 Icon Style Options** - Choose your preferred menu bar display mode
  - **Battery Style**: Classic battery indicator with fill level (original style)
  - **Progress Bar**: Horizontal progress bar with percentage display
  - **Percentage Only**: Minimalist text-only display
  - **Icon with Bar**: Claude icon with integrated progress bar
  - **Compact**: Space-efficient minimal design

- **New Appearance Settings Tab** - Dedicated UI for visual customization
  - Icon style picker with visual previews
  - Live preview showing how each style looks
  - Monochrome mode toggle (see below)
  - Real-time updates when changing styles

- **Monochrome Mode** - Optional black & white icon aesthetic
  - Toggle for minimalist monochrome menu bar icons
  - Removes colored indicators for clean appearance
  - Works with all icon styles
  - Perfect for users who prefer subtle menu bar presence

- **StatusBarUIManager** - New component for menu bar icon rendering
  - Centralized icon drawing logic for all styles
  - Handles style switching seamlessly
  - Manages monochrome mode rendering
  - Optimized drawing performance

#### Redesigned Settings Interface
- **Modular Settings Architecture** - Complete refactor with separate view files
  - **APIBillingView**: API console billing and usage display
  - **AboutView**: Version info, credits, and links
  - **AppearanceSettingsView**: Icon styles and visual preferences (new)
  - **ClaudeCodeView**: Terminal statusline configuration
  - **GeneralSettingsView**: Session key and refresh settings
  - **NotificationsSettingsView**: Alert preferences
  - **PersonalUsageView**: Individual usage tracking
  - **SessionManagementView**: Auto-start configuration

- **New Design System** - Reusable component library for consistent UI
  - **SettingsCard**: Bordered container component for grouping settings
  - **SettingToggle**: Standardized toggle switch with description
  - **SettingsButton**: Consistent button styling (primary, secondary, danger variants)
  - **SettingsInputField**: Text input with validation states
  - **SettingsStatusBox**: Status message display with color coding
  - **SettingsHeader**: Section headers with consistent styling
  - **Typography System**: Standardized text styles (title, heading, body, caption, small)
  - **Spacing System**: Consistent padding and margin values
  - **Color System**: Centralized color definitions for light/dark mode

- **IconStylePicker Component** - Visual icon style selection interface
  - Grid layout with style previews
  - Hover effects and selection states
  - Clear style descriptions
  - Intuitive selection UX

#### Core Architecture Improvements
- **Protocol-Oriented Design** - Enhanced modularity and testability
  - **APIServiceProtocol**: Service layer abstraction
  - **NotificationServiceProtocol**: Notification system interface
  - **StorageProvider**: Storage abstraction for data persistence
  - Dependency injection support for better testing

- **Coordinator Pattern Implementation**
  - **UsageRefreshCoordinator**: Orchestrates automatic data refresh cycles
  - **WindowCoordinator**: Manages popover and detached window lifecycle
  - **StatusBarUIManager**: Coordinates menu bar icon rendering
  - Separation of concerns between navigation and business logic

- **LoggingService** - Centralized logging system
  - Categorized log levels (debug, info, warning, error)
  - Consistent logging across the application
  - Helps with debugging and troubleshooting
  - Production-ready with configurable verbosity

- **ValidationState Model** - Type-safe validation state representation
  - States: idle, validating, success, error
  - Used across settings UI for consistent validation feedback
  - Improves UX with clear validation states

#### Enhanced Data Storage
- **Extended DataStore Capabilities**
  - Icon style preference persistence
  - Monochrome mode setting storage
  - API configuration storage (API key, organization ID)
  - Appearance preferences management
  - App Groups support for future widget integration

- **Constants Utility** - Centralized configuration keys
  - API endpoint definitions
  - UI constant values
  - UserDefaults keys
  - Improved code maintainability

#### UI/UX Improvements
- **Standardized Settings Sections** - Consistent headers and spacing across all tabs
  - SettingsHeader component for uniform section titles
  - Standardized padding using Spacing design system
  - Improved visual hierarchy

- **Enhanced Conversation Deletion** - Improved initialization message handling
  - `sendInitializationMessage` now includes conversation cleanup
  - Prevents conversation clutter from auto-start sessions
  - More reliable session initialization

### Fixed

- **Settings Layout Consistency** - Adjusted spacing and alignment across all settings views
  - Uniform padding in General, Notifications, Session, and Claude Code tabs
  - Consistent component spacing throughout settings interface
  - Better visual balance in About view

### Technical Improvements

- **MenuBarManager Enhancements**
  - Integration with StatusBarUIManager for multi-style icon rendering
  - Support for icon style switching
  - Monochrome mode handling
  - Improved refresh coordination

- **Notification Extensions** - Added notification name constants
  - `Notification.Name.iconStyleChanged`
  - `Notification.Name.monochromeChanged`
  - Reactive UI updates on preference changes

- **Improved Code Organization**
  - Separated UI components from business logic
  - Clear file structure with dedicated folders
  - Reusable design system components
  - Reduced code duplication

### Documentation

- **Comprehensive README Overhaul**
  - Restructured for feature-first documentation
  - Getting Started section moved before Features
  - Condensed Features section for better readability
  - Added Table of Contents for easy navigation
  - Removed decorative emojis for professional tone
  - Enhanced Architecture section with system diagram
  - Updated API Integration docs for dual endpoints
  - Added Prerequisites and Quick Start Guide sections
  - Expanded Settings documentation covering all 7 tabs

---

## [1.5.0] - 2025-12-16

### Added

#### GitHub Star Prompt
- **New "Star Us" Feature** - Encourages community engagement
  - GitHub star prompt displayed in settings after 24 hours of usage
  - One-time prompt with "Star on GitHub" and "Maybe Later" options
  - Opens GitHub repository in browser on confirmation
  - Smart tracking to prevent repeated prompts
  - Non-intrusive timing ensures positive user experience

- **GitHubService** - New service for GitHub-related operations
  - Opens repository URL in default browser
  - Handles GitHub interactions
  - Extensible for future GitHub integrations

- **Enhanced DataStore** - Star prompt tracking capabilities
  - `shouldShowStarPrompt()`: Determines if prompt should be shown based on install time
  - `markStarPromptShown()`: Records when prompt was displayed
  - Install time tracking for timing calculations
  - Persistent storage of prompt state

#### Contributors Section
- **New Contributors Display** in About settings
  - Shows project contributors with avatars from contrib.rocks
  - Dynamic image loading from GitHub API
  - Professional attribution section
  - Acknowledges community contributions

### Fixed

#### Popover UI Improvements
- **Enhanced Status Display** - Improved Claude system status UI in popover
  - Better visual hierarchy for status information
  - Refined spacing and layout
  - Improved readability of status messages
  - More polished overall appearance

### Technical Improvements

- **MenuBarManager Updates**
  - Integration with star prompt logic
  - Proper timing checks for prompt display
  - State management for prompt lifecycle

- **AppDelegate Enhancements**
  - Install time recording on first launch
  - Initialization of tracking mechanisms

### Documentation

- **Updated Popover Screenshot** - New popover.png reflecting latest UI improvements
- **README Updates** - Added contributors section and updated documentation

---

## [1.4.0] - 2025-12-15

### Added

#### Claude System Status Indicator
- **Real-time Claude API Status** - Live status indicator in the popover footer
  - Fetches status from `status.claude.com` API (Statuspage)
  - Color-coded indicators: 🟢 Green (operational), 🟡 Yellow (minor), 🟠 Orange (major), 🔴 Red (critical), ⚪ Gray (unknown)
  - Displays current status description (e.g., "All Systems Operational")
  - Clickable row opens status.claude.com for detailed information
  - Hover tooltip and subtle hover effect for better UX
  - 10-second timeout prevents UI blocking on slow connections

- **New ClaudeStatusService** - Dedicated service for status monitoring
  - Async/await implementation with proper error handling
  - Automatic status refresh alongside usage data
  - Graceful fallback to "Status Unknown" on failures

- **ClaudeStatus Model** - Type-safe status representation
  - `StatusIndicator` enum: none, minor, major, critical, unknown
  - `StatusColor` enum for consistent color mapping
  - Static factories for common states (.unknown, .operational)

#### Detachable Popover
- **Floating Window Mode** - Drag the popover to detach it into a standalone window
  - Detaches by dragging the popover away from the menu bar
  - Floating window stays above other windows (`NSWindow.Level.floating`)
  - Close button only (minimal chrome) for clean appearance
  - Window properly cleans up when closed
  - Menu bar icon click toggles/closes detached window

#### GitHub Issue Templates
- **Bug Report Template** (`bug_report.yml`) - Structured bug reporting
  - Description, steps to reproduce, app version, macOS version fields
  - Additional context section for logs/screenshots
  
- **Feature Request Template** (`feature_request.yml`) - Feature suggestions
  - Problem/use case, proposed solution, alternatives considered
  
- **Documentation Template** (`documentation.yml`) - Docs improvements
  - Issue location, suggested improvement fields

- **Config** (`config.yml`) - Links to GitHub Discussions for questions

#### Developer Documentation
- **CONTRIBUTING.md** - Comprehensive contributor guide
  - Development setup and prerequisites
  - Project structure overview
  - Code style guidelines (Swift API Design Guidelines)
  - Commit message conventions (Conventional Commits)
  - Branch naming conventions
  - Pull request process with checklist
  - Release process documentation

### Fixed

#### Popover Behavior
- **Close on Outside Click** - Popover now properly closes when clicking outside
  - Global event monitor for left and right mouse clicks
  - Automatically stops monitoring when popover closes or detaches
  - Prevents accidental dismissal while interacting with popover

#### About View
- **Dynamic Version Display** - Version number now reads from app bundle
  - Pulls `CFBundleShortVersionString` from `Bundle.main`
  - Falls back to "Unknown" if unavailable
  - No more hardcoded version strings to update

### Technical Improvements

- **MenuBarManager Enhancements**
  - Added `@Published var status: ClaudeStatus` for reactive status updates
  - Integrated `ClaudeStatusService` for parallel status fetching
  - `NSPopoverDelegate` implementation for detachable window support
  - `NSWindowDelegate` for proper window lifecycle management
  - Event monitor management for outside click detection

- **PopoverContentView Updates**
  - New `ClaudeStatusRow` component with hover effects
  - `SmartFooter` now displays live Claude status
  - Smooth animations for status transitions

### Contributors
- [@hamed-elfayome](https://github.com/hamed-elfayome) (Hamed Elfayome) - Project creator and maintainer
- [@ggfevans](https://github.com/ggfevans) - Claude status indicator, detachable popover, outside click fix, dynamic version, issue templates, contributing guide

---

## [1.3.0] - 2025-12-14

### Added

#### Claude Code Terminal Integration
- **New Claude Code Settings Tab** - Dedicated UI for configuring terminal statusline integration
  - Toggle individual components (directory, git branch, usage, progress bar)
  - Live preview showing exactly how your statusline will appear
  - One-click installation with automated script deployment
  - Visual component selection with clear descriptions

- **Terminal Statusline Display** - Real-time usage monitoring directly in your Claude Code terminal
  - **Current Directory**: Shows working directory name with blue highlight
  - **Git Branch**: Live branch indicator with ⎇ icon (automatically detected)
  - **Usage Percentage**: Session usage with 10-level color gradient (green → yellow → orange → red)
  - **Progress Bar**: Optional 10-segment visual indicator (▓░) for at-a-glance status
  - **Reset Time**: Countdown showing when your 5-hour session resets
  - **Format Example**: `my-project │ ⎇ main │ Usage: 25% ▓▓░░░░░░░░ → Reset: 3:45 PM`

- **Automated Installation** - Scripts installed to `~/.claude/` directory
  - `fetch-claude-usage.swift`: Swift script for fetching usage data from Claude API
  - `statusline-command.sh`: Bash script that builds the statusline display
  - `statusline-config.txt`: Configuration file storing component preferences
  - Automatic updates to Claude Code's `settings.json`
  - Secure file permissions (755) set automatically

- **Smart Color Coding** - 10-level gradient provides visual feedback
  - 0-10%: Dark green (safe zone)
  - 11-30%: Green shades (light usage)
  - 31-50%: Yellow-green to olive (moderate usage)
  - 51-70%: Yellow to orange (elevated usage)
  - 71-90%: Dark orange to red (high usage)
  - 91-100%: Deep red (critical usage)

- **Flexible Configuration**
  - Mix and match any combination of components
  - Preview updates in real-time as you toggle options
  - Easy enable/disable with Apply and Reset buttons
  - Settings persist across app restarts

#### Validation & Error Handling
- **Session Key Validation** - Checks for valid session key before allowing statusline configuration
  - Clear error message if session key is not configured
  - Prevents installation failures by validating prerequisites
  - Directs users to General tab for API setup

- **Component Validation** - Ensures at least one component is selected before applying
  - Prevents empty statusline configurations
  - User-friendly error messages

### Fixed

- **Config File Formatting** - Removed unwanted leading whitespace in statusline configuration file
  - Ensures proper parsing by bash script
  - Prevents configuration read errors

- **Conditional Cast Warning** - Removed redundant cast in `ClaudeAPIService.swift`
  - Cleaned up overage data handling code
  - Improved code clarity

- **Bash Script Percentage Display** - Fixed double percent sign (`%%`) in statusline output
  - Now correctly displays single `%` (e.g., "Usage: 25%" instead of "Usage: 25%%")

### Technical Improvements

- Added `StatuslineService` for managing Claude Code integration
  - Embedded Swift and Bash scripts for portability
  - File management and permission handling
  - Claude Code settings.json integration
  - Installation and configuration management

- Enhanced `DataStore` with statusline preferences
  - Save/load methods for component visibility settings
  - Default values (all components enabled by default)
  - Persistent storage across app launches

- New `StatuslineView` SwiftUI interface
  - Live preview with dynamic updates
  - Clean, modern UI matching app design
  - Status message feedback for user actions
  - Validation and error handling

- Updated `Constants` with statusline-related keys
  - UserDefaults keys for component preferences
  - Centralized configuration management

### Documentation

- **Comprehensive README Updates**
  - New "Claude Code Integration" section with full setup guide
  - Component table with descriptions and examples
  - Color coding reference
  - Troubleshooting guide
  - Multiple example configurations
  - Updated version badges to v1.3.0

- **Inline Code Documentation**
  - Detailed comments in StatuslineService
  - Clear explanations of Swift and Bash scripts
  - Function-level documentation

---

## [1.2.0] - 2025-12-13

### Added

#### Extra Usage Cost Tracking
- **Real-time cost monitoring** for Claude Extra usage (contributed by [@khromov](https://github.com/khromov))
  - Displays current spending vs. budget limit (e.g., 15.38 / 25.00 EUR)
  - Visual progress indicator with percentage tracking
  - Seamlessly integrated below Weekly usage in the popover interface
  - Automatically appears when Claude Extra usage is enabled on your account

### Contributors
- [@khromov](https://github.com/khromov) (Stanislav Khromov) - Extra usage cost tracking feature

---

## [1.1.0] - 2025-12-13

### Added

#### Auto-Start Session Feature
- **New Session Management Tab** in Settings with dedicated UI for session automation
- **Auto-start session on reset** - Automatically initializes a new session when the current session hits 0%
  - Sends a simple "Hi" message to Claude 3.5 Haiku (cheapest model)
  - Ensures you always have a fresh 5-hour session ready without manual intervention
  - Configurable toggle in Settings → Session
  - Detailed "How it works" section explaining the feature with visual icons

#### Enhanced Notifications
- **Session Auto-Start Notification** - Get notified when a new session is automatically initialized
  - Title: "Session Auto-Started"
  - Message: Confirms that your fresh 5-hour session is ready
- **Notifications Enabled Confirmation** - Immediate feedback when enabling notifications
  - Title: "Notifications Enabled"
  - Message: Explains what alerts you'll receive (75%, 90%, 95% thresholds + session resets)
  - Helps users confirm their notification settings are working

#### UI Improvements
- New **Session settings tab** with professional layout and clear feature explanations
- **Increased Settings window size** from 600x550 to 720x600 for better content visibility
- Enhanced notification permission handling with proper authorization checks

### Fixed

#### Menu Bar Icon Visibility
- **Appearance adaptation** - Menu bar icon now properly adapts to light/dark mode and wallpaper changes
  - Icon outline and "Claude" text now render in appropriate colors (black on light, white on dark)
  - Keeps colored progress indicator (green/orange/red) for status visibility
  - Real-time updates when system appearance changes
  - No need to restart the app when switching themes

#### Notification System
- **Added UNUserNotificationCenterDelegate** to AppDelegate for proper menu bar app notification support
  - Notifications now display while the app is running (menu bar apps are always "foreground")
  - Implemented `willPresent` delegate method to show banners and sounds
  - Set notification center delegate on app launch
- **Fixed notification delivery** - Notifications now properly appear on screen instead of being silently suppressed

### Technical Improvements
- Added appearance change observer using KVO on `effectiveAppearance`
- Proper notification authorization status checking before sending alerts
- Clean error handling for auto-start session initialization
- Production-ready code with debug logging removed

---

## [1.0.0] - 2025-12-13

### Added
- Initial release
- Real-time Claude usage monitoring (session, weekly, and Opus-specific)
- Menu bar integration with battery-style progress indicator
- Smart notifications at usage thresholds (75%, 90%, 95%)
- Session reset notifications
- Setup wizard for first-run configuration
- Secure session key storage with restricted permissions (0600)
- Auto-refresh with configurable intervals (5-120 seconds)
- Settings interface for API, General, Notifications, and About sections
- Detailed usage dashboard with countdown timers
- Support for macOS 14.0+ (Sonoma and later)

[2.2.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v2.1.2...v2.2.0
[2.1.2]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v2.1.1...v2.1.2
[2.1.1]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.6.2...v2.0.0
[1.6.2]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.6.1...v1.6.2
[1.6.1]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.6.0...v1.6.1
[1.6.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/releases/tag/v1.0.0
