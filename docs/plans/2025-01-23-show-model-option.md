# Show Model Option Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Model name" checkbox to the Claude Code statusline settings that displays the current model (e.g., "Opus", "Sonnet") as the first component in the status line.

**Architecture:** Add a new `showModel` setting following the existing pattern for other checkboxes (SharedDataStore → ClaudeCodeView → StatuslineService). The bash script extracts `display_name` from the JSON input and outputs it first.

**Tech Stack:** Swift/SwiftUI, Bash scripting, UserDefaults

---

## Task 1: Add Storage Key and Methods to SharedDataStore

**Files:**
- Modify: `Claude Usage/Shared/Storage/SharedDataStore.swift:21-25` (add key)
- Modify: `Claude Usage/Shared/Storage/SharedDataStore.swift:57-112` (add methods)

**Step 1: Add the storage key**

In the `Keys` enum (around line 21), add the new key as the FIRST statusline key:

```swift
// Statusline Configuration
static let statuslineShowModel = "statuslineShowModel"  // NEW - add first
static let statuslineShowDirectory = "statuslineShowDirectory"
static let statuslineShowBranch = "statuslineShowBranch"
```

**Step 2: Add save method**

After line 56 (after `// MARK: - Statusline Configuration`), add:

```swift
func saveStatuslineShowModel(_ show: Bool) {
    defaults.set(show, forKey: Keys.statuslineShowModel)
}
```

**Step 3: Add load method**

After the save method, add:

```swift
func loadStatuslineShowModel() -> Bool {
    if defaults.object(forKey: Keys.statuslineShowModel) == nil {
        return true  // Default to true (checked)
    }
    return defaults.bool(forKey: Keys.statuslineShowModel)
}
```

**Step 4: Commit**

```bash
git add "Claude Usage/Shared/Storage/SharedDataStore.swift"
git commit -m "feat: add showModel storage methods to SharedDataStore"
```

---

## Task 2: Add Test for New Storage Methods

**Files:**
- Modify: `Claude UsageTests/SharedDataStoreTests.swift`

**Step 1: Add test method**

After `testStatuslineShowResetTime()` (around line 80), add:

```swift
func testStatuslineShowModel() {
    // Test default value (true)
    XCTAssertTrue(store.loadStatuslineShowModel())

    // Test save and load
    store.saveStatuslineShowModel(false)
    XCTAssertFalse(store.loadStatuslineShowModel())

    store.saveStatuslineShowModel(true)
    XCTAssertTrue(store.loadStatuslineShowModel())
}
```

**Step 2: Run tests to verify**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS"`

Expected: All tests pass including new `testStatuslineShowModel`

**Step 3: Commit**

```bash
git add "Claude UsageTests/SharedDataStoreTests.swift"
git commit -m "test: add unit test for showModel storage"
```

---

## Task 3: Add showModel Parameter to StatuslineService

**Files:**
- Modify: `Claude Usage/Shared/Services/StatuslineService.swift:341-360`

**Step 1: Update function signature**

Change the `updateConfiguration` function signature to add `showModel` as the FIRST parameter:

```swift
func updateConfiguration(
    showModel: Bool,  // NEW - add first
    showDirectory: Bool,
    showBranch: Bool,
    showUsage: Bool,
    showProgressBar: Bool,
    showResetTime: Bool
) throws {
```

**Step 2: Update config file output**

Update the config string to include `SHOW_MODEL` as the FIRST line:

```swift
let config = """
SHOW_MODEL=\(showModel ? "1" : "0")
SHOW_DIRECTORY=\(showDirectory ? "1" : "0")
SHOW_BRANCH=\(showBranch ? "1" : "0")
SHOW_USAGE=\(showUsage ? "1" : "0")
SHOW_PROGRESS_BAR=\(showProgressBar ? "1" : "0")
SHOW_RESET_TIME=\(showResetTime ? "1" : "0")
"""
```

**Step 3: Commit**

```bash
git add "Claude Usage/Shared/Services/StatuslineService.swift"
git commit -m "feat: add showModel parameter to updateConfiguration"
```

---

## Task 4: Update Bash Script to Support Model Display

**Files:**
- Modify: `Claude Usage/Shared/Services/StatuslineService.swift:114-270` (bashScript constant)

**Step 1: Update config reading section (lines 117-130)**

Replace the config reading section with:

```bash
config_file="$HOME/.claude/statusline-config.txt"
if [ -f "$config_file" ]; then
  source "$config_file"
  show_model=$SHOW_MODEL
  show_dir=$SHOW_DIRECTORY
  show_branch=$SHOW_BRANCH
  show_usage=$SHOW_USAGE
  show_bar=$SHOW_PROGRESS_BAR
  show_reset=$SHOW_RESET_TIME
else
  show_model=1
  show_dir=1
  show_branch=1
  show_usage=1
  show_bar=1
  show_reset=1
fi
```

**Step 2: Add model extraction after current_dir (after line 134)**

Add after `current_dir=$(basename "$current_dir_path")`:

```bash
model=$(echo "$input" | grep -o '"display_name":"[^"]*"' | sed 's/"display_name":"//;s/"$//')
```

**Step 3: Add model_text component (after branch_text section, around line 165)**

Add after the branch_text block:

```bash
model_text=""
if [ "$show_model" = "1" ] && [ -n "$model" ]; then
  model_text="${YELLOW}${model}${RESET}"
fi
```

**Step 4: Update output building (lines 254-267)**

Replace the output building section with:

```bash
output=""
separator="${GRAY} │ ${RESET}"

# Model comes first
[ -n "$model_text" ] && output="${model_text}"

# Then directory
if [ -n "$dir_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${dir_text}"
fi

# Then branch
if [ -n "$branch_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${branch_text}"
fi

# Finally usage
if [ -n "$usage_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${usage_text}"
fi
```

**Step 5: Commit**

```bash
git add "Claude Usage/Shared/Services/StatuslineService.swift"
git commit -m "feat: update bash script to display model name first"
```

---

## Task 5: Add Localization Strings

**Files:**
- Modify: `Claude Usage/Resources/en.lproj/Localizable.strings`
- Modify: `Claude Usage/Resources/de.lproj/Localizable.strings`
- Modify: `Claude Usage/Resources/es.lproj/Localizable.strings`
- Modify: `Claude Usage/Resources/fr.lproj/Localizable.strings`
- Modify: `Claude Usage/Resources/it.lproj/Localizable.strings`
- Modify: `Claude Usage/Resources/ja.lproj/Localizable.strings`
- Modify: `Claude Usage/Resources/ko.lproj/Localizable.strings`
- Modify: `Claude Usage/Resources/pt.lproj/Localizable.strings`

**Step 1: Add English string**

In `en.lproj/Localizable.strings`, find the claudecode.component section (around line 342) and add BEFORE `claudecode.component_directory`:

```
"claudecode.component_model" = "Model name";
```

**Step 2: Add translations to other files**

| File | String |
|------|--------|
| de.lproj | `"claudecode.component_model" = "Modellname";` |
| es.lproj | `"claudecode.component_model" = "Nombre del modelo";` |
| fr.lproj | `"claudecode.component_model" = "Nom du modèle";` |
| it.lproj | `"claudecode.component_model" = "Nome del modello";` |
| ja.lproj | `"claudecode.component_model" = "モデル名";` |
| ko.lproj | `"claudecode.component_model" = "모델 이름";` |
| pt.lproj | `"claudecode.component_model" = "Nome do modelo";` |

**Step 3: Commit**

```bash
git add "Claude Usage/Resources/"
git commit -m "feat: add localization strings for model name option"
```

---

## Task 6: Update ClaudeCodeView UI

**Files:**
- Modify: `Claude Usage/Views/Settings/App/ClaudeCodeView.swift`

**Step 1: Add state variable (around line 13)**

Add as the FIRST state variable:

```swift
@State private var showModel: Bool = SharedDataStore.shared.loadStatuslineShowModel()
```

**Step 2: Add toggle in UI (around line 78)**

Add the Model toggle BEFORE the Directory toggle:

```swift
VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
    Toggle("claudecode.component_model".localized, isOn: $showModel)
        .font(DesignTokens.Typography.body)

    Toggle("claudecode.component_directory".localized, isOn: $showDirectory)
        .font(DesignTokens.Typography.body)
```

**Step 3: Update validation (around line 172)**

Update the validation to include `showModel`:

```swift
guard showModel || showDirectory || showBranch || showUsage else {
```

**Step 4: Add save call (around line 186)**

Add save for showModel as the FIRST save:

```swift
SharedDataStore.shared.saveStatuslineShowModel(showModel)
SharedDataStore.shared.saveStatuslineShowDirectory(showDirectory)
```

**Step 5: Update updateConfiguration call (around line 197)**

Add `showModel` as the first parameter:

```swift
try StatuslineService.shared.updateConfiguration(
    showModel: showModel,
    showDirectory: showDirectory,
    showBranch: showBranch,
    showUsage: showUsage,
    showProgressBar: showProgressBar,
    showResetTime: showResetTime
)
```

**Step 6: Update generatePreview (around line 230)**

Add model to preview as the FIRST component:

```swift
private func generatePreview() -> String {
    var parts: [String] = []

    if showModel {
        parts.append("Opus")  // Example model name
    }

    if showDirectory {
        parts.append("claude-usage")
    }
```

**Step 7: Commit**

```bash
git add "Claude Usage/Views/Settings/App/ClaudeCodeView.swift"
git commit -m "feat: add Model name checkbox to Claude Code settings UI"
```

---

## Task 7: Build and Test

**Step 1: Build the project**

Run: `xcodebuild build -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS"`

Expected: Build succeeds with no errors

**Step 2: Run all tests**

Run: `xcodebuild test -project "Claude Usage.xcodeproj" -scheme "Claude Usage" -destination "platform=macOS"`

Expected: All tests pass

**Step 3: Manual testing**

1. Open the app
2. Go to Settings → Claude CLI
3. Verify "Model name" checkbox appears first
4. Verify it's checked by default
5. Toggle it on/off and verify Live Preview updates
6. Click Apply
7. Verify `~/.claude/statusline-config.txt` contains `SHOW_MODEL=1` (or 0)
8. Start a new Claude Code session and verify model appears in status line

**Step 4: Commit any fixes if needed**

---

## Task 8: Create Pull Request

**Step 1: Push branch to fork**

```bash
cd ~/Development/Claude-Usage-Tracker
git push -u origin feature/show-model-option
```

**Step 2: Create PR**

```bash
gh pr create --title "feat: add Model name display option to statusline" --body "$(cat <<'EOF'
## Summary
- Adds a new "Model name" checkbox to the Claude CLI settings
- When enabled, displays the current model (e.g., "Opus", "Sonnet", "Haiku") as the first component in the status line
- Checked by default for new users
- Includes localization for all 8 supported languages

## Changes
- `SharedDataStore.swift`: Add `showModel` storage methods
- `StatuslineService.swift`: Update config generation and bash script
- `ClaudeCodeView.swift`: Add checkbox UI and preview
- `Localizable.strings`: Add translations for all languages
- `SharedDataStoreTests.swift`: Add unit test

## Screenshots
[Add screenshot of settings UI with new checkbox]

## Testing
- [x] Unit tests pass
- [x] Manual testing: checkbox toggles correctly
- [x] Manual testing: Live Preview updates in real-time
- [x] Manual testing: Model appears in Claude Code status line

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)" --repo hamed-elfayome/Claude-Usage-Tracker
```

---

## Summary of Files Changed

| File | Change Type | Description |
|------|-------------|-------------|
| `SharedDataStore.swift` | Modify | Add storage key and load/save methods |
| `SharedDataStoreTests.swift` | Modify | Add unit test |
| `StatuslineService.swift` | Modify | Update config function and bash script |
| `ClaudeCodeView.swift` | Modify | Add checkbox, preview, and save logic |
| `en.lproj/Localizable.strings` | Modify | Add English string |
| `de.lproj/Localizable.strings` | Modify | Add German translation |
| `es.lproj/Localizable.strings` | Modify | Add Spanish translation |
| `fr.lproj/Localizable.strings` | Modify | Add French translation |
| `it.lproj/Localizable.strings` | Modify | Add Italian translation |
| `ja.lproj/Localizable.strings` | Modify | Add Japanese translation |
| `ko.lproj/Localizable.strings` | Modify | Add Korean translation |
| `pt.lproj/Localizable.strings` | Modify | Add Portuguese translation |
