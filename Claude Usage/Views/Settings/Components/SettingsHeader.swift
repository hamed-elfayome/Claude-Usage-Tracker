//
//  SettingsHeader.swift
//  Claude Usage - Settings Header Component
//
//  Created by Claude Code on 2025-12-21.
//

import SwiftUI

/// Unified header component for all settings tabs (legacy compatibility)
/// NOTE: New code should use SettingsPageHeader from SettingsComponents.swift
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
