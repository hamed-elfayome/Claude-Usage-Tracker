# Changelog

All notable changes to Claude Usage Tracker will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.1.0]: https://github.com/yourusername/claude-usage-tracker/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/yourusername/claude-usage-tracker/releases/tag/v1.0.0
