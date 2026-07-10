# Release Notes — Claude Usage (reowens branch)

**Branch:** `reowens`
**Compared to:** `main`
**Commits:** 8

---

## Highlights

This release introduces a **6-tier pace system** for both the menu bar and Claude Code statusline, a **color mode system** (Multi-Color / Greyscale / Single Color), several new **label and formatting toggles**, and a critical **CPU spin-loop fix** in menu bar rendering.

---

## New Features

### 6-Tier Pace System
- **New `PaceStatus` enum** with 6 urgency tiers: Comfortable, On Track, Warming, Pressing, Critical, Runaway
- Projects end-of-period usage from current consumption rate to determine urgency
- Pace calculated from `usedPercentage` and `elapsedFraction` (requires ≥3% elapsed)
- Each tier has a distinct color: Green → Teal → Yellow → Orange → Red → Purple
- Available as both SwiftUI (`Color`) and AppKit (`NSColor`) colors

### Pace Marker on Progress Bars
- **Menu bar:** A bold `┃` marker is drawn at the elapsed-time position on progress bars, colored by pace tier
- **Statusline (CLI):** Pace marker (`┃`) inserted into the ASCII progress bar at the correct elapsed position with ANSI 6-tier colors
- **Popover:** Time marker upgraded from a 1.5px line to a 2.5px rounded rectangle, colored by pace status
- Toggle: "Show Pace Marker" and "Pace tier colors" (6-tier projected pace) are independently controllable

### Color Mode System (Menu Bar + Statusline)
- **`MenuBarColorMode`** enum: `multiColor`, `monochrome`, `singleColor`
- **`StatuslineColorMode`** enum: `colored`, `monochrome`, `singleColor`
- Replaces the old boolean `monochromeMode` with a 3-mode system
- **Single Color mode:** Users pick a custom color (hex) applied to all elements
- **Monochrome mode:** Adapts to menu bar / terminal appearance
- **Multi-Color mode:** Threshold-based colors (default behavior)
- Backwards compatible: old `monochromeMode: true/false` is migrated automatically

### Color Mode Settings UI (ClaudeCodeView)
- New "Statusline Colors" settings card with 3 selectable mode buttons
- Each mode shows icon, name, and description
- `ColorPicker` appears when Single Color is selected
- Preview updates live to match selected color mode

### Terminal-Matching Preview
- Preview in ClaudeCodeView now renders with ANSI-equivalent terminal colors
- Multi-color mode shows each element in its actual terminal color (blue for dir, green for branch, yellow for model, magenta for profile, cyan for context, gradient for usage)
- Pace marker in preview is colored by real pace tier when step colors are enabled

### Label Toggles
- **"Show Ctx: label"** — toggle the `Ctx:` prefix on context display
- **"Show Usage: label"** — toggle the `Usage:` prefix on usage display
- **"Show Reset: label"** — toggle the `Reset:` prefix on reset time
- **24-hour time format** — override system time format for reset time display

### Hex Color Utilities
- New `Color+Extensions.swift` with `Color(hex:)` init, `toHex()`, and `hexString` property
- New `NSColor(hex:)` convenience initializer
- Supports 6-digit (RGB) and 8-digit (RGBA) hex strings

### Date Extension
- `Date.roundedToNearestMinute()` — strips seconds to prevent display flickering in reset time

---

## Bug Fixes

### CPU Spin-Loop Fix (Menu Bar Icon Rendering)
- **Root cause:** Observing each `NSStatusBarButton.effectiveAppearance` via KVO caused an infinite loop — setting `button.image` triggers KVO on `effectiveAppearance`, which triggers a redraw, which sets `button.image` again
- **Fix:** Replaced per-button KVO observers with a single `NSApp.effectiveAppearance` observer
- Added `lastObservedAppearanceName` deduplication to skip redundant notifications
- Added image data cache (`lastImageData`) to skip redundant `button.image` assignments when TIFF data hasn't changed
- `setButtonImage()` helper compares TIFF data before assigning to prevent KVO churn

### Reset Time Rounding
- Reset time in statusline now rounds to nearest minute to prevent "pinballing" between e.g. 6:59 and 7:00
- Both the bash script and the Swift preview use consistent rounding

### Pace Marker Restoration After Session Reset
- Pace marker is preserved/restored correctly after session resets

---

## Refactoring

### MenuBarManager Cleanup
- Removed empty `observeAppearanceChanges()` method (was a no-op with a comment)
- Removed unused `appearanceObserver` property
- Simplified `statusBarAppearanceDidChange()` — removed debounce timer, now redraws directly (safe due to image cache deduplication)

### WindowCoordinator Simplification
- Removed `sizingOptions = .intrinsicContentSize` workaround
- Uses `Constants.WindowSizes.popoverSize` for consistent sizing

### PopoverContentView
- Removed `.fixedSize(horizontal: false, vertical: true)` that could cause layout issues

### StatusBarUIManager
- `image.isTemplate` is now set *before* assigning to `button.image` to avoid extra KVO
- Template mode disabled when pace marker is active (pace marker uses explicit colors)

### MenuBarIconConfiguration
- Replaced `monochromeMode: Bool` with `colorMode: MenuBarColorMode`
- Added `singleColorHex: String` for custom color storage
- Added `showPaceMarker: Bool` alongside existing `usePaceColoring`
- Custom `encode(to:)` — no longer writes legacy `monochromeMode` key
- Custom `init(from:)` — reads legacy `monochromeMode` and converts to new `colorMode`

### MultiProfileDisplayConfig
- Added `showPaceMarker` property (independent of `usePaceColoring`)
- Default for new installs: `showPaceMarker = true`, `usePaceColoring = true`
- Backwards compat: missing keys default to `false` to avoid surprising existing users

### DataStore Migration
- `loadMonochromeMode()` now maps to `colorMode = .monochrome` instead of setting a bool

---

## StatuslineService (Bash Script) Changes

### New Config Variables
| Variable | Default | Description |
|---|---|---|
| `SHOW_PACE_MARKER` | `1` | Show pace marker on progress bar |
| `PACE_MARKER_STEP_COLORS` | `1` | Use 6-tier pace colors for marker |
| `USE_24_HOUR_TIME` | `0` | 24-hour time format for reset time |
| `SHOW_CONTEXT_LABEL` | `1` | Show "Ctx:" prefix |
| `SHOW_USAGE_LABEL` | `1` | Show "Usage:" prefix |
| `SHOW_RESET_LABEL` | `1` | Show "Reset:" prefix |
| `COLOR_MODE` | `colored` | Color mode: colored / monochrome / singleColor |
| `SINGLE_COLOR` | `#00BFFF` | Hex color for single-color mode |

### Color Mode Implementation
- `hex_to_ansi()` function converts user's hex color to ANSI 24-bit true-color escape codes
- Monochrome mode sets all color variables to empty strings
- Single-color mode sets all variables to the same ANSI code
- Pace step colors override mode-specific colors when enabled

### Pace Marker in Bash
- Calculates elapsed time from reset epoch
- Places `┃` character at the proportional position in the 10-char progress bar
- Computes projected usage percentage via integer math for 6-tier color assignment
- Falls back to usage bar color when step colors are disabled

---

## SharedDataStore — New Keys

| Key | Type | Default |
|---|---|---|
| `statuslineShowPaceMarker` | Bool | `true` |
| `statuslinePaceMarkerStepColors` | Bool | `false` |
| `statuslineShowContextLabel` | Bool | `true` |
| `statuslineUse24HourTime` | Bool | `false` |
| `statuslineShowUsageLabel` | Bool | `true` |
| `statuslineShowResetLabel` | Bool | `true` |
| `statuslineColorMode` | String | `"colored"` |
| `statuslineSingleColorHex` | String | `"#00BFFF"` |

---

## Localization

- Updated all 9 localization files (en, es, fr, de, it, ja, ko, pt, zh-ch)
- New keys: `claudecode.component_pace_marker`, `claudecode.pace_marker_info`
- Renamed keys for clarity: `appearance.show_time_marker_title`, `appearance.pace_coloring_title`, etc.
- New keys: `appearance.show_pace_marker_title`, `appearance.show_pace_marker_description`
- New section keys: `appearance.pace_marker_section_title`, `appearance.pace_marker_section_subtitle`

---

## Files Changed

| File | Lines Added | Lines Removed |
|---|---|---|
| `Views/Settings/App/ClaudeCodeView.swift` | ~500 | ~20 |
| `Services/StatuslineService.swift` | ~200 | ~40 |
| `MenuBar/MenuBarIconRenderer.swift` | ~150 | ~60 |
| `MenuBar/StatusBarUIManager.swift` | ~50 | ~50 |
| `Extensions/Color+Extensions.swift` | 112 | 0 (new) |
| `Storage/SharedDataStore.swift` | 91 | 0 |
| `Models/MenuBarIconConfig.swift` | ~80 | ~20 |
| `Utilities/PaceStatus.swift` | 72 | 0 (new) |
| `MenuBar/MenuBarManager.swift` | ~10 | ~50 |
| `Models/StatuslineColorMode.swift` | 53 | 0 (new) |
| `MenuBar/PopoverContentView.swift` | ~25 | ~5 |
| `Views/Settings/App/ManageProfilesView.swift` | ~15 | ~2 |
| `Views/Settings/Profile/AppearanceSettingsView.swift` | ~15 | ~3 |
| `Extensions/Date+Extensions.swift` | 7 | 0 |
| `MenuBar/WindowCoordinator.swift` | 1 | 4 |
| `Storage/DataStore.swift` | 1 | 1 |
| 9x `Localizable.strings` | ~10 each | ~5 each |
| **Total** | **~1,546** | **~232** |
