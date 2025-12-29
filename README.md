# Claude Usage Tracker

<div align="center">
  <img src=".github/cover.jpg" alt="Claude Usage Tracker" width="100%">

  **A native macOS menu bar application for real-time monitoring of Claude AI usage limits**

  ![macOS](https://img.shields.io/badge/macOS-14.0+-black?style=flat-square&logo=apple)
  ![Swift](https://img.shields.io/badge/Swift-5.0+-orange?style=flat-square&logo=swift)
  ![SwiftUI](https://img.shields.io/badge/SwiftUI-5.0+-blue?style=flat-square&logo=swift)
  ![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
  ![Version](https://img.shields.io/badge/version-2.1.0-blue?style=flat-square)

  ### [Download Latest Release (v2.1.0)](https://github.com/hamed-elfayome/Claude-Usage-Tracker/releases/latest/download/Claude-Usage.zip)

  <sub>macOS 14.0+ (Sonoma) | ~3 MB | Native Swift/SwiftUI | Officially Signed</sub>

  [![Buy Me A Coffee](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=☕&slug=hamedelfayome&button_colour=e48131&font_colour=000000&font_family=Poppins&outline_colour=000000&coffee_colour=ffffff)](https://buymeacoffee.com/hamedelfayome)
</div>

---

## Overview

Claude Usage Tracker is a lightweight, native macOS menu bar application that provides real-time monitoring of your Claude AI usage limits. Built entirely with Swift and SwiftUI, it offers a clean, intuitive interface to track your 5-hour session window, weekly usage limits, and Opus-specific consumption.

### Key Capabilities

- **Real-Time Monitoring**: Track session, weekly, and API console usage
- **Customizable Interface**: 5 icon styles + monochrome mode
- **Smart Automation**: Auto-start sessions, threshold notifications
- **Developer Tools**: Terminal statusline integration for Claude Code
- **Privacy-First**: Local storage, no telemetry, no cloud sync
- **Native Performance**: Lightweight Swift/SwiftUI design for macOS

<div align="center">
  <img src=".github/icon.jpg" alt="Menu Bar Icon" height="180">
  <img src=".github/popover.png" alt="Popover Interface" width="200">

  <sub>Menu bar icon and detailed usage popover</sub>

  <img src=".github/statusline.png" alt="Claude Code Statusline">
  <br>
  <sub>Live terminal statusline showing directory, branch, and color-coded usage</sub>
</div>

---

## What's New

**v2.1.0 - UX & Reliability Improvements (2025-12-29)**:
- **Wizard-Style Setup Flow** - New 3-step guided wizard for session key configuration
  - Step 1: Non-destructive connection testing (validates without saving)
  - Step 2: Visual organization selector with radio buttons
  - Step 3: Configuration summary with masked key preview
- **Smart Organization Preservation** - Organization IDs only cleared when session key actually changes
- **Enhanced Data Parsing** - Robust handling of Int/Double/String utilization values from API
- **Smooth Refresh Experience** - Menu bar icons no longer flicker during data refresh
- **Improved Error Context** - Detailed error messages with endpoint names and response previews

**v2.0.0 - Major Release (2025-12-28)**:
- **Official Apple Code Signing** - No more security warnings! Install like any normal Mac app
- **Automatic Updates** - Built-in update system powered by Sparkle framework
- **Enhanced Security** - Session keys now stored in macOS Keychain with automatic migration
- **Multi-Language Support** - 6 languages: English, Spanish, French, German, Italian, Portuguese
- **Multi-Metric Menu Bar Icons** - Display separate icons for session, weekly, and api usage
- **Advanced Error Handling** - Professional error system with user-friendly messages and recovery
- **Network Monitoring** - Auto-detect connectivity changes and handle offline scenarios
- **Launch at Login** - System-level auto-start option

**[View Full Release History](CHANGELOG.md)**

---

## Getting Started

### Prerequisites

Before installing Claude Usage Tracker, ensure you have:

- **macOS 14.0 (Sonoma) or later** - Check: Apple menu → About This Mac
- **Active Claude AI account** - Sign up at [claude.ai](https://claude.ai)
- **Web browser access** - For extracting your session key (Chrome, Safari, Firefox, etc.)

**Optional**:
- [Claude Code](https://claude.com/claude-code) - For terminal statusline integration

### Installation

#### Option 1: Homebrew (Recommended)

```bash
brew install --cask hamed-elfayome/claude-usage/claude-usage-tracker
```

Or tap first, then install:

```bash
brew tap hamed-elfayome/claude-usage
brew install --cask claude-usage-tracker
```

**Note**: Starting with v2.0.0, the app is officially signed with an Apple Developer certificate. No security workarounds needed!

**To update**:
```bash
brew upgrade --cask claude-usage-tracker
```

Or use the built-in automatic update feature (Settings → Updates).

**To uninstall**:
```bash
brew uninstall --cask claude-usage-tracker
```

#### Option 2: Direct Download

**[Download Claude-Usage.zip](https://github.com/hamed-elfayome/Claude-Usage-Tracker/releases/latest/download/Claude-Usage.zip)**

1. Download the `.zip` file from the link above
2. Extract the zip file (double-click or use Archive Utility)
3. Drag `Claude Usage.app` to your Applications folder
4. Double-click to launch - that's it!

**v2.0.0+ Note**: The app is now officially signed with an Apple Developer certificate. You can install and run it like any other Mac application - no security warnings or workarounds needed.

**Automatic Updates**: Once installed, the app will automatically check for updates and notify you when new versions are available (Settings → Updates).

#### Option 3: Build from Source

```bash
# Clone the repository
git clone https://github.com/alexbartok/Claude-Usage-Tracker.git
cd Claude-Usage-Tracker

# Open in Xcode
open "Claude Usage.xcodeproj"

# Build and run (⌘R)
```

### Quick Start Guide

#### Step 1: Extract Your Session Key

Your session key authenticates the app with Claude AI. Here's how to get it:

1. **Open Claude AI**
   - Navigate to [claude.ai](https://claude.ai) in your browser
   - Make sure you're logged in

2. **Open Developer Tools**
   - **Chrome/Edge**: Press `F12` or `Cmd+Option+I` (macOS) / `Ctrl+Shift+I` (Windows)
   - **Safari**: Enable Developer menu in Preferences → Advanced, then press `Cmd+Option+I`
   - **Firefox**: Press `F12` or `Cmd+Option+I` (macOS) / `Ctrl+Shift+I` (Windows)

3. **Navigate to Cookies**
   - Go to: **Application** tab (Chrome/Edge) or **Storage** tab (Firefox)
   - Expand: **Cookies** → **https://claude.ai**
   - Find: `sessionKey` cookie
   - Copy: The value (starts with `sk-ant-sid01-...`)

<div align="center">
  <sub>Tip: The session key is a long string starting with "sk-ant-sid01-". Make sure to copy the entire value.</sub>
</div>

#### Step 2: Configure Session Key

Access the Personal Usage settings to configure your session key:

1. **Click the menu bar icon** and select "Settings"
2. **Navigate to "Personal Usage"** tab
3. **3-Step Wizard** guides you through setup:
   - **Step 1**: Paste your session key and click "Test Connection"
   - **Step 2**: Select your Claude organization from the list
   - **Step 3**: Review and click "Save Configuration"
4. **Wait for confirmation** (success message appears)

The new wizard validates your key without saving it first, ensuring a smooth setup experience

#### Step 3: Verify It's Working

1. **Check Menu Bar**: You should see the Claude Usage icon in your menu bar
2. **Click the Icon**: Popover appears showing your usage statistics
3. **View Data**: Session usage, weekly usage, and reset timers should display

**Success!** The app is now monitoring your Claude usage.

#### Next Steps

- **Customize Icon**: Go to Settings → Appearance to choose your preferred menu bar style
- **Enable Notifications**: Settings → Notifications to get threshold alerts
- **Auto-Start Sessions**: Settings → Session Management to enable automatic session initialization
- **Terminal Integration**: Settings → Claude Code to set up statusline (requires [Claude Code](https://claude.com/claude-code))

---

## Advanced Configuration

### Manual Session Key Setup

If you prefer to configure the session key manually instead of using the setup wizard:

```bash
# Create session key file
echo "sk-ant-sid01-YOUR_SESSION_KEY_HERE" > ~/.claude-session-key

# Set secure permissions (important for security)
chmod 600 ~/.claude-session-key
```

After creating the file, launch the app and it will automatically detect the session key.

---

## Features

### Installation & Updates
- **Official Apple Code Signing**: Professionally signed application - installs like any Mac app
- **Automatic Updates**: Built-in update system powered by Sparkle framework
- **One-Click Installation**: No security workarounds or manual approvals needed
- **Update Notifications**: Get notified when new versions are available

### Usage Tracking & Monitoring
- Real-time monitoring of 5-hour session, weekly limits, and Opus-specific usage
- API console usage tracking for comprehensive visibility
- Extra usage cost tracking for Claude Extra subscribers
- Color-coded indicators (green/orange/red) based on consumption levels
- Smart countdown timers for session and weekly resets

### Menu Bar & Interface
- **5 Customizable Icon Styles**: Battery, Progress Bar, Percentage Only, Icon with Bar, Compact
- **Multi-Metric Icons**: Display separate icons for session, weekly, and api usage simultaneously
- **Monochrome Mode**: Optional black & white aesthetic
- **Interactive Popover**: One-click access with detachable floating window capability
- **Live Status Indicator**: Real-time Claude system status from status.claude.com
- **Multi-Language Support**: 6 languages (English, Spanish, French, German, Italian, Portuguese)
- Adaptive colors for light/dark mode

### Automation & Intelligence
- **Auto-Start Sessions**: Automatically initialize new sessions when usage resets to 0%
- **Smart Notifications**: Threshold alerts at 75%, 90%, and 95% usage
- **Network Monitoring**: Auto-detect connectivity changes and handle offline scenarios
- **Launch at Login**: System-level auto-start option
- **Configurable Refresh**: Set intervals from 5 to 120 seconds
- Session reset and auto-start confirmations

### Developer Integration
- **Claude Code Terminal Statusline**: Real-time usage in your terminal
- Customizable components: directory, git branch, usage percentage, progress bar, reset timer
- One-click automated installation
- Live preview before applying changes

### Security & Privacy
- **macOS Keychain Storage**: Session keys stored in macOS Keychain (most secure option)
- **Automatic Migration**: Seamless migration from old storage methods
- **Apple Code Signed**: Verified by Apple for enhanced security and trust
- **Advanced Error Handling**: Professional error system with user-friendly recovery
- **Robust Validation**: Session key and API endpoint validation
- Local storage with no cloud sync
- Zero telemetry or tracking
- HTTPS-only communication with Claude API

### Advanced Capabilities
- Multi-screen support
- First-run guided setup wizard
- Protocol-based modular architecture
- Persistent settings with App Groups
- Comprehensive test coverage

---

## Usage

### Menu Bar Interface

Click the menu bar icon to access:

- **Session Usage**: 5-hour rolling window percentage and reset time
- **Weekly Usage**: Overall weekly consumption across all models
- **Opus Usage**: Weekly Opus-specific usage (if applicable)
- **Quick Actions**: Refresh, Settings, and Quit

### Settings

Access comprehensive settings through the menu bar popover → Settings button. The app features a modern, modular settings interface organized into focused tabs:

#### Personal Usage
Configure your Claude.ai personal account:
- **3-Step Setup Wizard**: Guided session key configuration
  - Non-destructive connection testing
  - Visual organization selector
  - Configuration summary with preview
- **Smart Updates**: Organization preserved when re-entering same key
- **Quick Access**: One-click link to claude.ai

#### General Settings
- **Refresh Interval**: Configure auto-refresh rate (5-120 seconds)
- **Connection Status**: View current API connection state
- **Advanced Settings**: Debug logging and error tracking

#### Appearance Settings
Customize how the menu bar icon looks:
- **Icon Style Selection**: Choose from 5 different display modes
  - Battery Style (classic indicator with fill)
  - Progress Bar (horizontal bar with percentage)
  - Percentage Only (text-only minimalist)
  - Icon with Bar (Claude icon + progress)
  - Compact (space-efficient)
- **Monochrome Mode**: Toggle black & white icon style
- **Live Preview**: See changes in real-time before applying

#### API Settings
Configure API console usage tracking:
- **API Session Key**: Set your API authentication key
- **Organization ID**: Configure organization for API tracking
- **Dual Tracking**: Monitor both web and API usage simultaneously
- **API Billing**: View API console usage costs

#### Session Management
Control automatic session behavior:
- **Auto-Start on Reset**: Enable/disable automatic session initialization
- **Model Selection**: Uses Claude 3.5 Haiku (most cost-effective)
- **Initialization Status**: View last auto-start activity

#### Notifications
Fine-tune alert preferences:
- **Enable/Disable**: Master toggle for all notifications
- **Threshold Alerts**: Notifications at 75%, 90%, and 95% usage
- **Session Reset Alerts**: Get notified when 5-hour window refreshes
- **Auto-Start Alerts**: Confirmations for automatic session initialization
- **Test Notifications**: Send test notification to verify setup

#### Claude Code Integration
Set up terminal statusline (requires [Claude Code](https://claude.com/claude-code)):
- **Component Selection**: Choose what to display (directory, branch, usage, progress bar, reset time)
- **Live Preview**: See exact statusline format before installing
- **One-Click Install**: Automated script installation to `~/.claude/`
- **Configuration Management**: Apply or reset statusline settings
- See [Claude Code Integration](#claude-code-integration) section for detailed setup

#### Updates
- **Automatic Update Checking**: Configure how often to check for updates
- **Update Notifications**: Get notified when new versions are available
- **One-Click Installation**: Download and install updates with a single click
- **Release Notes**: View what's new in each update
- **Update Channel**: Stay on stable releases or opt into beta testing

#### About
- **Version Information**: Current app version
- **Credits**: Contributors and acknowledgments
- **Links**: GitHub repository, issue tracker, documentation


## Claude Code Integration

Bring real-time Claude usage monitoring directly into your terminal with Claude Code statusline integration! Display your current usage percentage, git branch, and working directory without leaving your development workflow.

### What is Claude Code?

[Claude Code](https://claude.com/claude-code) is Anthropic's official CLI tool for interacting with Claude AI directly from your terminal. The statusline feature allows you to display custom information at the bottom of your terminal window.

<div align="center">
  <img src=".github/statusline.png" alt="Claude Code Statusline in Action" width="90%">
  <br>
  <sub>Example: Terminal statusline with all components enabled</sub>
</div>

### Setup Instructions

#### Prerequisites

1. **Claude Code installed**: Download from [claude.com/claude-code](https://claude.com/claude-code)
2. **Session key configured**: Must be set in the General tab of Claude Usage Tracker

#### Installation Steps

1. **Open Claude Usage Tracker Settings**
   - Click the menu bar icon
   - Click "Settings"
   - Navigate to the "Claude Code" tab

2. **Choose Your Components**
   - Toggle on/off the components you want to see:
     - **Directory name**: Shows current working directory
     - **Git branch**: Displays current branch with ⎇ icon
     - **Usage statistics**: Shows session percentage with color coding
     - **Progress bar**: Visual 10-segment indicator (optional when usage is enabled)

3. **Preview Your Statusline**
   - The live preview shows exactly how it will appear
   - Example: `claude-usage │ ⎇ main │ Usage: 25% ▓▓░░░░░░░░`

4. **Apply Configuration**
   - Click "Apply" button
   - Scripts will be installed to `~/.claude/`
   - Claude Code's `settings.json` will be updated automatically

5. **Restart Claude Code**
   - Close and reopen your Claude Code terminal
   - The statusline will appear at the bottom of your terminal window

### What Gets Installed

The setup automatically creates:

- `~/.claude/fetch-claude-usage.swift`: Swift script that fetches usage data from Claude API
- `~/.claude/statusline-command.sh`: Bash script that builds the statusline display
- `~/.claude/statusline-config.txt`: Configuration file with your component preferences
- `~/.claude/settings.json`: Updated with statusline command (or created if doesn't exist)

All scripts are set with secure permissions (755) and only read your existing session key file.

### Customization

#### Available Components

| Component | Description | Example |
|-----------|-------------|---------|
| Directory | Current directory name | `claude-usage` |
| Git Branch | Active git branch | `⎇ main` |
| Usage | Session percentage | `Usage: 25%` |
| Progress Bar | 10-segment visual indicator | `▓▓░░░░░░░░` |
| Reset Time | When session resets | `→ Reset: 3:45 PM` |

#### Color Coding

Usage percentage is color-coded with a 10-level gradient:
- **0-10%**: Dark green
- **11-30%**: Green shades
- **31-50%**: Yellow-green transitioning to olive
- **51-70%**: Yellow to orange
- **71-90%**: Dark orange to red
- **91-100%**: Deep red

#### Disabling Statusline

To remove the statusline:
1. Open Claude Usage Tracker Settings → Claude Code tab
2. Click "Reset" button
3. Restart Claude Code

This removes the statusline configuration but keeps the scripts installed for easy re-enabling.

### Troubleshooting

#### Statusline Not Appearing

1. Verify Claude Code is installed and working
2. Check that you restarted Claude Code after applying
3. Ensure session key is valid in General settings tab
4. Check that `~/.claude/settings.json` exists and has the statusline configuration

#### Shows "Usage: ~"

This indicates the Swift script couldn't fetch usage data:
- Verify your session key is valid
- Check that `~/.claude-session-key` exists
- Ensure you're connected to the internet
- Try refreshing your session key from claude.ai

#### Permission Issues

If scripts can't be executed:
```bash
chmod 755 ~/.claude/fetch-claude-usage.swift
chmod 755 ~/.claude/statusline-command.sh
```

### Example Statuslines

With all components enabled:
```
my-project │ ⎇ feature/new-ui │ Usage: 47% ▓▓▓▓▓░░░░░ → Reset: 4:15 PM
```

Minimal (usage only):
```
Usage: 12% ▓░░░░░░░░░
```

Directory and branch only:
```
backend-api │ ⎇ develop
```

## Architecture

### Technology Stack

- **Language**: Swift 5.0+
- **UI Framework**: SwiftUI 5.0+
- **Platform**: macOS 14.0+ (Sonoma)
- **Architecture**: MVVM with Protocol-Oriented Design
- **Storage**: UserDefaults with App Groups
- **Networking**: URLSession with async/await
- **Design Patterns**: Coordinator pattern, Protocol-based services, Modular components

## API Integration

The application integrates with multiple Claude API endpoints for comprehensive usage tracking:

### Web Usage Endpoint

```
GET https://claude.ai/api/organizations/{org_id}/usage
```

**Authentication**: Session cookie (`sessionKey`) from claude.ai

**Response Structure**:
- `five_hour`: 5-hour session usage data
  - `utilization_pct`: Usage percentage (0-100)
  - `reset_at`: ISO 8601 timestamp for next reset
- `seven_day`: Weekly usage across all models
  - `utilization_pct`: Weekly usage percentage
- `seven_day_opus`: Opus-specific weekly usage
  - `utilization_pct`: Opus weekly percentage
- `extra_usage`: Claude Extra cost tracking (if applicable)
  - `current_spending`: Amount spent
  - `budget_limit`: Maximum allowed spending

### API Console Endpoint

```
GET https://api.anthropic.com/v1/organization/{org_id}/usage
```

**Authentication**: API Key (`x-api-key` header)

**Response Structure**:
- API console usage statistics
- Billing information
- Rate limits and quotas

### Dual Tracking

The app can simultaneously monitor both web (claude.ai) and API console usage, providing complete visibility into your Claude consumption across all access methods.

## Security

- **macOS Keychain**: Session keys stored securely in macOS Keychain (most secure storage available)
- **Automatic Migration**: v2.0+ automatically migrates session keys from older storage methods to Keychain
- **Apple Code Signed**: Officially signed with Apple Developer certificate for verified authenticity
- **Secure Updates**: Automatic updates delivered over HTTPS with code signature verification
- **No Cloud Sync**: All data remains local to your machine
- **No Telemetry**: Zero tracking or analytics
- **Advanced Error Handling**: Robust error system with user-friendly recovery
- **Session Key Validation**: Comprehensive validation of API credentials
- **Network**: HTTPS-only communication with claude.ai and Anthropic API

## Troubleshooting

### Application Not Connecting

1. Verify your session key is valid
2. Check that you're logged into claude.ai in your browser
3. Try extracting a fresh session key
4. Ensure you have an active internet connection

### 403 Permission Errors

If you see "Unauthorized" or 403 errors:
1. Open Settings → Personal Usage
2. Use the 3-step wizard to reconfigure:
   - Test your session key
   - Select the correct organization
   - Save configuration
3. The wizard will preserve your organization selection when updating keys

### Menu Bar Icons Showing Zero

If icons briefly flash to zero during refresh:
- This has been fixed in v2.1.0+
- Update to the latest version for smooth refresh experience
- Old data now stays visible until new data arrives

### Menu Bar Icon Not Appearing

1. Check System Settings → Desktop & Dock → Menu Bar
2. Restart the application
3. Check Console.app for error messages

### Session Key Expired

Session keys may expire after a period of time. Extract a new key from claude.ai and update it in Settings → Personal Usage using the wizard.

### Updates Not Working

If automatic updates aren't working:

1. Check Settings → Updates to ensure automatic checking is enabled
2. Verify you're running v2.0.0 or later (earlier versions don't have auto-update)
3. Check your internet connection
4. Manually download the latest version from GitHub if needed

## Contributors

<img src="https://contrib.rocks/image?repo=hamed-elfayome/Claude-Usage-Tracker" alt="Contributors" height="30px" />

This project is built for the community — everyone is welcome

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

## Acknowledgments

- Built with Swift and SwiftUI
- Designed for macOS Sonoma and later
- Uses Claude AI's usage API
- Inspired by the need for better usage visibility

## Disclaimer

This application is not affiliated with, endorsed by, or sponsored by Anthropic PBC. Claude is a trademark of Anthropic PBC. This is an independent third-party tool created for personal usage monitoring.

## AI Transparency

This project is developed using AI-assisted workflows (primarily Claude Code via Happy). We believe in transparent collaboration between human developers and AI tools.

---

<div align="center">
  <sub>Built for the Claude AI community</sub>
</div>
