//
//  Typography.swift
//  Claude Usage - Settings Design System
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Typography system for Settings UI
/// Provides consistent font hierarchy across all settings views
enum Typography {
    /// Large titles for main screen headers (20pt, semibold)
    static let title: Font = .system(size: 20, weight: .semibold)

    /// Section headers and important labels (14pt, semibold)
    static let subtitle: Font = .system(size: 14, weight: .semibold)

    /// Subsection headers and setting labels (13pt, medium)
    static let sectionHeader: Font = .system(size: 13, weight: .medium)

    /// Regular body text and descriptions (13pt, regular)
    static let body: Font = .system(size: 13, weight: .regular)

    /// Small labels and form inputs (12pt, regular)
    static let label: Font = .system(size: 12, weight: .regular)

    /// Help text and secondary information (11pt, regular)
    static let caption: Font = .system(size: 11, weight: .regular)

    /// Monospaced text for code and keys (12pt, monospaced)
    static let monospacedInput: Font = .system(size: 12, design: .monospaced)

    /// Monospaced values display (13pt, monospaced)
    static let monospacedValue: Font = .system(size: 13, design: .monospaced)

    /// Small badges and tags (9pt, bold)
    static let badge: Font = .system(size: 9, weight: .bold)
}

/// Text styles with built-in colors for common use cases
extension Text {
    func settingsTitle() -> some View {
        self.font(Typography.title)
            .foregroundColor(.primary)
    }

    func settingsSubtitle() -> some View {
        self.font(Typography.subtitle)
            .foregroundColor(.primary)
    }

    func settingsSectionHeader() -> some View {
        self.font(Typography.sectionHeader)
            .foregroundColor(.primary)
    }

    func settingsBody() -> some View {
        self.font(Typography.body)
            .foregroundColor(.primary)
    }

    func settingsCaption() -> some View {
        self.font(Typography.caption)
            .foregroundColor(.secondary)
    }

    func settingsLabel() -> some View {
        self.font(Typography.label)
            .foregroundColor(.primary)
    }
}
