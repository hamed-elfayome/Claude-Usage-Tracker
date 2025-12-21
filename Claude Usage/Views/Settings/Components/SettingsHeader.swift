//
//  SettingsHeader.swift
//  Claude Usage - Settings Header Component
//
//  Created by Claude Code on 2025-12-21.
//

import SwiftUI

/// Unified header component for all settings tabs
struct SettingsHeader: View {
    let title: String
    let subtitle: String
    let icon: String?

    init(title: String, subtitle: String, icon: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let icon = icon {
                HStack(spacing: Spacing.md) {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(title)
                            .font(Typography.title)

                        Text(subtitle)
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(Typography.title)

                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Header without Icon") {
    SettingsHeader(
        title: "General Settings",
        subtitle: "Configure app behavior and preferences"
    )
    .padding()
}

#Preview("Header with Icon") {
    SettingsHeader(
        title: "Notifications",
        subtitle: "Manage alerts and usage warnings",
        icon: "bell.fill"
    )
    .padding()
}
