# Changelog

All notable changes to Claude Usage Tracker will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.4.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/hamed-elfayome/Claude-Usage-Tracker/releases/tag/v1.0.0
