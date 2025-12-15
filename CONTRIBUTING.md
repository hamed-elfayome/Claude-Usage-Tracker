# Contributing to Claude Usage Tracker

First off, thank you for considering contributing to Claude Usage Tracker! 🎉

This document provides guidelines and information about contributing to this project. We welcome contributions of all kinds: bug reports, feature requests, documentation improvements, and code contributions.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Development Setup](#development-setup)
  - [Project Structure](#project-structure)
- [How to Contribute](#how-to-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Features](#suggesting-features)
  - [Contributing Code](#contributing-code)
- [Development Guidelines](#development-guidelines)
  - [Code Style](#code-style)
  - [Architecture](#architecture)
  - [Commit Messages](#commit-messages)
  - [Branch Naming](#branch-naming)
- [Pull Request Process](#pull-request-process)
- [Release Process](#release-process)
- [Getting Help](#getting-help)

## Code of Conduct

This project adheres to a code of conduct that all contributors are expected to follow. Please be respectful, inclusive, and considerate in all interactions.

**Our Standards:**
- Be welcoming and inclusive
- Be respectful of differing viewpoints
- Accept constructive criticism gracefully
- Focus on what's best for the community
- Show empathy towards other community members

## Getting Started

### Prerequisites

Before you begin, ensure you have the following installed:

- **macOS 14.0+** (Sonoma or later)
- **Xcode 15.0+** (latest stable recommended)
- **Git** for version control
- **A Claude AI account** for testing (to obtain a session key)

### Development Setup

1. **Fork the repository**
   
   Click the "Fork" button on GitHub to create your own copy.

2. **Clone your fork**
   ```bash
   git clone https://github.com/YOUR_USERNAME/Claude-Usage-Tracker.git
   cd Claude-Usage-Tracker
   ```

3. **Add upstream remote**
   ```bash
   git remote add upstream https://github.com/hamed-elfayome/Claude-Usage-Tracker.git
   ```

4. **Open in Xcode**
   ```bash
   open "Claude Usage.xcodeproj"
   ```

5. **Build and run**
   - Select the "Claude Usage" scheme
   - Press `⌘R` to build and run
   - The app will appear in your menu bar

6. **Configure for testing**
   - Extract your session key from claude.ai (see README for instructions)
   - The app will guide you through setup on first launch

### Project Structure

```
Claude Usage/
├── App/
│   ├── AppDelegate.swift          # App lifecycle, notifications setup
│   └── ClaudeUsageTrackerApp.swift # SwiftUI app entry point
│
├── MenuBar/
│   ├── MenuBarManager.swift       # Status item, popover management
│   └── PopoverContentView.swift   # Main UI for usage display
│
├── Views/
│   ├── SettingsView.swift         # Settings window with tabs
│   └── SetupWizardView.swift      # First-run configuration
│
├── Shared/
│   ├── Extensions/                # Date, UserDefaults extensions
│   ├── Models/
│   │   ├── ClaudeUsage.swift      # Usage data model
│   │   └── ClaudeStatus.swift     # API status model
│   ├── Services/
│   │   ├── ClaudeAPIService.swift # API communication
│   │   ├── ClaudeStatusService.swift
│   │   ├── NotificationManager.swift
│   │   └── StatuslineService.swift # Claude Code integration
│   ├── Storage/
│   │   └── DataStore.swift        # UserDefaults wrapper
│   └── Utilities/
│       ├── Constants.swift        # App-wide constants
│       └── FormatterHelper.swift  # Formatting utilities
│
├── Assets.xcassets/               # Images, colors, icons
└── Resources/
    └── Info.plist                 # App configuration
```

## How to Contribute

### Reporting Bugs

Before submitting a bug report:
1. Check existing [issues](https://github.com/hamed-elfayome/Claude-Usage-Tracker/issues) to avoid duplicates
2. Ensure you're running the latest version

**When reporting a bug, include:**
- macOS version (e.g., macOS 14.2)
- App version (found in Settings → About)
- Steps to reproduce the issue
- Expected behavior vs. actual behavior
- Screenshots if applicable
- Relevant Console.app logs (filter by "Claude Usage")

### Suggesting Features

We love feature suggestions! Please:
1. Check existing issues and discussions first
2. Describe the problem your feature would solve
3. Explain your proposed solution
4. Consider alternative approaches

### Contributing Code

1. **Find or create an issue** for what you want to work on
2. **Comment on the issue** to let others know you're working on it
3. **Fork and create a branch** (see [Branch Naming](#branch-naming))
4. **Make your changes** following our [guidelines](#development-guidelines)
5. **Test thoroughly** on macOS 14.0+
6. **Submit a pull request**

## Development Guidelines

### Code Style

We follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) and standard SwiftUI practices.

**Key conventions:**

```swift
// MARK: - Use MARK comments to organize code sections
// MARK: - Properties
// MARK: - Initialization
// MARK: - Public Methods
// MARK: - Private Methods

// Use descriptive names
func fetchUsageData() async throws -> ClaudeUsage  // ✅ Good
func getData() async throws -> ClaudeUsage         // ❌ Avoid

// Document public APIs
/// Fetches the current usage data from Claude's API
/// - Returns: A `ClaudeUsage` object with current session and weekly usage
/// - Throws: `APIError` if the request fails
func fetchUsageData() async throws -> ClaudeUsage

// Use Swift's type inference where clear
let usage = ClaudeUsage.empty    // ✅ Good
let usage: ClaudeUsage = ClaudeUsage.empty  // ❌ Redundant

// Prefer structs for data models
struct ClaudeUsage: Codable, Equatable { ... }

// Use enums for constants and configurations
enum Constants {
    static let sessionWindow: TimeInterval = 5 * 60 * 60
}
```

**SwiftUI specific:**

```swift
// Extract complex views into separate structs
struct SmartUsageCard: View {
    let title: String
    let percentage: Double
    
    var body: some View {
        // Keep body focused and readable
    }
}

// Use @State for local view state
// Use @Published in ObservableObject for shared state
// Use @Environment for system values

// Prefer declarative modifiers over imperative code
Text("Usage")
    .font(.headline)
    .foregroundColor(.primary)
```

### Architecture

This project follows the **MVVM (Model-View-ViewModel)** pattern:

- **Models** (`Shared/Models/`): Data structures, pure Swift
- **Views** (`Views/`, `MenuBar/`): SwiftUI views, presentation only
- **ViewModels/Managers** (`MenuBar/MenuBarManager.swift`): Business logic, state management
- **Services** (`Shared/Services/`): API calls, system interactions

**Guidelines:**
- Keep views "dumb" - they should only display data
- Put business logic in managers/services
- Use dependency injection where possible
- Prefer `async/await` over completion handlers

### Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting, no code change
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `perf`: Performance improvement
- `test`: Adding or updating tests
- `chore`: Build process, dependencies, etc.

**Examples:**
```
feat(api): add support for Opus weekly usage tracking

fix(menubar): resolve icon not updating on appearance change

docs(readme): add Claude Code statusline setup instructions

refactor(services): extract notification logic to NotificationManager
```

### Branch Naming

Use descriptive branch names with prefixes:

| Prefix | Use Case | Example |
|--------|----------|---------|
| `feat/` | New features | `feat/historical-data-chart` |
| `fix/` | Bug fixes | `fix/session-reset-notification` |
| `docs/` | Documentation | `docs/add-contributing-guide` |
| `refactor/` | Code refactoring | `refactor/extract-api-service` |
| `chore/` | Maintenance | `chore/update-dependencies` |

## Pull Request Process

1. **Update your fork**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Create your branch**
   ```bash
   git checkout -b feat/your-feature-name
   ```

3. **Make your changes**
   - Write clean, documented code
   - Follow the style guidelines
   - Test on macOS 14.0+

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat(scope): description of changes"
   ```

5. **Push to your fork**
   ```bash
   git push origin feat/your-feature-name
   ```

6. **Open a Pull Request**
   - Use a clear, descriptive title
   - Reference any related issues (`Closes #123`)
   - Describe what changes you made and why
   - Include screenshots for UI changes
   - List any breaking changes

7. **Code Review**
   - Respond to feedback promptly
   - Make requested changes
   - Keep the PR focused - one feature/fix per PR

**PR Checklist:**
- [ ] Code follows project style guidelines
- [ ] Self-reviewed my own code
- [ ] Added comments for complex logic
- [ ] Updated documentation if needed
- [ ] Tested on macOS 14.0+
- [ ] No new warnings in Xcode
- [ ] UI changes include screenshots

## Release Process

Releases are managed by maintainers. The general process:

1. **Version Bump**
   - Update `MARKETING_VERSION` in `project.pbxproj`
   - Update version badge in `README.md`

2. **Changelog**
   - Update `CHANGELOG.md` with all changes
   - Follow [Keep a Changelog](https://keepachangelog.com/) format

3. **Testing**
   - Full regression test on clean macOS install
   - Verify all features work together

4. **Release**
   - Create GitHub Release with tag (e.g., `v1.4.0`)
   - Attach built `.app` bundle (zipped)
   - Include SHA256 checksum
   - Write comprehensive release notes

## Getting Help

- **Questions?** Open a [Discussion](https://github.com/hamed-elfayome/Claude-Usage-Tracker/discussions)
- **Found a bug?** Open an [Issue](https://github.com/hamed-elfayome/Claude-Usage-Tracker/issues)
- **Want to chat?** Reach out to maintainers

---

## Recognition

Contributors are recognized in:
- The GitHub contributors graph
- Release notes for significant contributions
- README acknowledgments for major features

Thank you for helping make Claude Usage Tracker better! 🙏
