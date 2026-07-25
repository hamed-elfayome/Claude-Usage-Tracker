# Claude Usage Tracker - SwiftBar Widget

This directory contains a lightweight SwiftBar widget that allows you to monitor your Antigravity (agy) usage directly from your macOS menu bar.

## Features
- **Menu Bar View**: Shows your current Gemini usage (e.g., `W: 34% S: 24%`).
- **Dropdown Details**: Displays comprehensive usage bars, percentages, and session reset times for both **GEMINI** and **CLAUDE & GPT**.
- **Manual Refresh**: Click `Refresh` in the dropdown to instantly fetch your latest usage data.

## Prerequisites
- [SwiftBar](https://swiftbar.app) must be installed.
- **agy must be installed and already logged in** via the terminal (`agy login`).
- `python3` and `tmux` must be installed.

## Installation

You can automatically set up the widget by running the included setup script:

```bash
chmod +x setup_widget.sh
./setup_widget.sh
```

### What the script does:
1. Prompts you to select your SwiftBar Plugins directory.
2. Copies `agy_usage.30s.py` and `get_agy_usage.sh` to your SwiftBar plugins folder.
3. Sets the necessary execution permissions.
4. Opens SwiftBar (if installed) to immediately load the new widget.

## Manual Installation
1. Copy `agy_usage.30s.py` and `get_agy_usage.sh` to your SwiftBar Plugins directory (typically `~/Documents/SwiftBar_Plugins`).
2. Make both files executable:
   ```bash
   chmod +x ~/Documents/SwiftBar_Plugins/agy_usage.30s.py
   chmod +x ~/Documents/SwiftBar_Plugins/get_agy_usage.sh
   ```
3. Open SwiftBar and click **Refresh All**.

## How it Works
Since `agy` requires a pseudo-terminal (TTY) to properly output formatted usage data without ANSI artifacts, the widget uses `tmux` in the background to launch `agy limits`, capture the output, and parse it in Python for SwiftBar.
