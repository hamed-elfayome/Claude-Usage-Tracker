# Claude Usage Tracker

<div align="center">
  <img src="https://hamedelfayome.dev/m/gcut" alt="Claude Usage Tracker" width="100%">

  **A native macOS menu bar application for real-time monitoring of Claude AI usage limits**

  ![macOS](https://img.shields.io/badge/macOS-14.0+-black?style=flat-square&logo=apple)
  ![Swift](https://img.shields.io/badge/Swift-5.0+-orange?style=flat-square&logo=swift)
  ![SwiftUI](https://img.shields.io/badge/SwiftUI-5.0+-blue?style=flat-square&logo=swift)
  ![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
  ![Version](https://img.shields.io/badge/version-1.1.0-blue?style=flat-square)

  ### [Download Latest Release (v1.1.0)](https://github.com/hamed-elfayome/Claude-Usage-Tracker/releases/latest/download/Claude-Usage.zip)

  <sub>macOS 14.0+ (Sonoma) | ~3 MB | Native Swift/SwiftUI</sub>

  <sub>⚠️ **Note:** This app is not signed with an Apple Developer certificate. You'll need to bypass the security warning on first launch (see installation steps below).</sub>
</div>

---

## Overview

Claude Usage Tracker is a lightweight, native macOS menu bar application that provides real-time monitoring of your Claude AI usage limits. Built entirely with Swift and SwiftUI, it offers a clean, intuitive interface to track your 5-hour session window, weekly usage limits, and Opus-specific consumption.

<div align="center">
  <img src=".github/icon.jpeg" alt="Menu Bar Icon" height="60">
  <img src=".github/popover.png" alt="Popover Interface" width="200">

  <sub>Menu bar icon and detailed usage popover</sub>
</div>

## What's New in v1.1.0

### Auto-Start Session Feature
Never worry about manually starting a new session! When your 5-hour session resets to 0%, the app automatically sends a simple "Hi" message to Claude 3.5 Haiku (cheapest model) to initialize a fresh session. Configure it in the new **Session Management** tab in Settings.

### Enhanced Notifications
- Get notified when a session is automatically started
- Immediate confirmation when enabling notifications
- Improved notification system with proper delegate support for menu bar apps

### Menu Bar Icon Improvements
Fixed visibility issues! The menu bar icon now properly adapts to light/dark mode and wallpaper changes in real-time. The outline and text automatically adjust (black on light, white on dark) while keeping the colored progress indicator.

### See [CHANGELOG.md](CHANGELOG.md) for full details

---

## Features

### Real-Time Usage Monitoring
- **Session Tracking**: Monitor your 5-hour rolling window usage with live percentage updates
- **Weekly Limits**: Track overall weekly token consumption across all models
- **Opus Tracking**: Dedicated monitoring for Claude Opus weekly usage
- **Visual Indicators**: Color-coded status (green, orange, red) based on consumption levels

### Menu Bar Integration
- **Compact Display**: Beautiful custom menu bar icon showing usage at a glance
- **Battery-Style Indicator**: Visual progress bar with "Claude" branding
- **One-Click Access**: Instant popover interface with detailed statistics
- **Native macOS Design**: Follows Apple's Human Interface Guidelines

### Session Management
- **Auto-Start on Reset**: Automatically initialize a new session when usage hits 0%
- **Zero Manual Intervention**: No need to manually send a message to start your session
- **Cheapest Model**: Uses Claude 3.5 Haiku to minimize token consumption
- **Instant Readiness**: Fresh 5-hour session immediately available after reset
- **Configurable**: Enable or disable in the dedicated Session settings tab

### Smart Notifications
- **Threshold Alerts**: Automatic notifications at 75%, 90%, and 95% usage
- **Session Resets**: Get notified when your 5-hour session resets
- **Auto-Start Alerts**: Confirmation when a new session is automatically initialized
- **Enable Confirmation**: Immediate feedback when turning on notifications
- **Customizable**: Enable or disable notifications in settings
- **Non-Intrusive**: macOS native notification system integration
- **Always Visible**: Proper delegate support ensures notifications appear while app is running

### Advanced Features
- **Auto-Refresh**: Configurable refresh intervals (5-120 seconds)
- **Reset Timers**: Countdown to next session and weekly reset
- **Setup Wizard**: First-run guided setup for API configuration
- **Secure Storage**: Session keys stored with restrictive file permissions (0600)
- **Multi-Screen Support**: Works seamlessly across multiple displays

## Requirements

- macOS 14.0 (Sonoma) or later
- Active Claude AI account
- Session key from claude.ai

## Installation

### Download and Install

**[Download Claude-Usage.zip](https://github.com/hamed-elfayome/Claude-Usage-Tracker/releases/latest/download/Claude-Usage.zip)**

1. Download the `.zip` file from the link above
2. Extract the zip file (double-click or use Archive Utility)
3. Drag `Claude Usage.app` to your Applications folder
4. Try to open the app (you'll see a security warning)
5. Go to **System Settings** → **Privacy & Security**
6. Scroll down and click **"Open Anyway"** next to the Claude Usage message
7. Click **"Open"** in the confirmation dialog
8. Done! The app will launch

**Alternative Method**: Right-click (or Control+click) on `Claude Usage.app` in Applications and select **"Open"**, then click **"Open"** again in the security dialog.

**First Launch Only**: You need to use one of these methods the first time due to macOS security for unsigned apps. After that, you can open it normally.

**Note**: This app is open-source and free. It's not signed with an Apple Developer certificate ($100/year), so macOS requires manual approval on first launch.

### Build from Source

```bash
# Clone the repository
git clone https://github.com/hamed-elfayome/Claude-Usage-Tracker.git
cd Claude-Usage-Tracker

# Open in Xcode
open "Claude Usage.xcodeproj"

# Build and run (⌘R)
```

## Setup

### First Launch

When you launch Claude Usage Tracker for the first time, you'll see a setup wizard:

1. **Extract Session Key**
   - Open [claude.ai](https://claude.ai) in your browser
   - Open Developer Tools (F12 or Cmd+Option+I)
   - Navigate to: Application/Storage → Cookies → https://claude.ai
   - Find the `sessionKey` cookie
   - Copy its value (starts with `sk-ant-sid-...`)

2. **Configure Application**
   - Paste your session key in the setup wizard
   - Click "Validate" to test the connection
   - Click "Done" to complete setup

3. **Start Monitoring**
   - The app will appear in your menu bar
   - Click the icon to view detailed usage statistics

### Manual Configuration

Alternatively, you can manually create the session key file:

```bash
# Create session key file
echo "sk-ant-sid-YOUR_SESSION_KEY_HERE" > ~/.claude-session-key

# Set secure permissions
chmod 600 ~/.claude-session-key
```

## Usage

### Menu Bar Interface

Click the menu bar icon to access:

- **Session Usage**: 5-hour rolling window percentage and reset time
- **Weekly Usage**: Overall weekly consumption across all models
- **Opus Usage**: Weekly Opus-specific usage (if applicable)
- **Quick Actions**: Refresh, Settings, and Quit

### Settings

Access settings through the menu bar or popover:

- **General**: Configure refresh interval (5-120 seconds)
- **Notifications**: Enable/disable usage alerts
- **API**: Update session key or test connection
- **About**: Version information and credits

### Keyboard Shortcuts

- Click menu bar icon: Toggle popover
- Settings window: Cmd+, (when popover is open)

## Architecture

### Technology Stack

- **Language**: Swift 5.0+
- **UI Framework**: SwiftUI 5.0+
- **Platform**: macOS 14.0+ (Sonoma)
- **Architecture**: MVVM pattern
- **Storage**: UserDefaults with App Groups
- **Networking**: URLSession with async/await

### Key Components

**MenuBarManager**: Manages the status bar item, handles user interactions, and coordinates data refresh cycles.

**ClaudeAPIService**: Handles all API communication with Claude's usage endpoint, including authentication and response parsing.

**DataStore**: Provides centralized data persistence using App Groups for potential future widget support.

**NotificationManager**: Manages intelligent notification delivery based on usage thresholds and state changes.

## API Integration

The application integrates with Claude's internal API:

```
GET https://claude.ai/api/organizations/{org_id}/usage
```

Response includes:
- `five_hour`: Session usage data with utilization percentage and reset time
- `seven_day`: Weekly usage data with utilization percentage
- `seven_day_opus`: Opus-specific weekly usage data

Authentication is handled via session cookie extracted from the browser.

## Security

- **Local Storage**: Session keys stored in `~/.claude-session-key` with 0600 permissions
- **No Cloud Sync**: All data remains local to your machine
- **No Telemetry**: Zero tracking or analytics
- **Sandboxing**: Disabled to allow file system access (required for session key)
- **Network**: HTTPS-only communication with claude.ai

## Troubleshooting

### Application Not Connecting

1. Verify your session key is valid
2. Check that you're logged into claude.ai in your browser
3. Try extracting a fresh session key
4. Ensure you have an active internet connection

### Menu Bar Icon Not Appearing

1. Check System Settings → Desktop & Dock → Menu Bar
2. Restart the application
3. Check Console.app for error messages

### Session Key Expired

Session keys may expire after a period of time. Extract a new key from claude.ai and update it in Settings → API.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Setup

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftUI best practices
- Maintain MVVM architecture
- Add comments for complex logic
- Write descriptive commit messages

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**Hamed Elfayome**

- GitHub: [@hamed-elfayome](https://github.com/hamed-elfayome)
- Email: hamedelfayome@gmail.com

## Acknowledgments

- Built with Swift and SwiftUI
- Designed for macOS Sonoma and later
- Uses Claude AI's usage API
- Inspired by the need for better usage visibility

## Disclaimer

This application is not affiliated with, endorsed by, or sponsored by Anthropic PBC. Claude is a trademark of Anthropic PBC. This is an independent third-party tool created for personal usage monitoring.

---

<div align="center">
  <sub>Built for the Claude AI community</sub>
</div>
