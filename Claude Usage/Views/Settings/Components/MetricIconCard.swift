//
//  MetricIconCard.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI

/// Card component for configuring a metric's icon appearance
struct MetricIconCard: View {
    let metricType: MenuBarMetricType
    @Binding var config: MetricIconConfig
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            // Header with enable toggle
            HStack(spacing: DesignTokens.Spacing.iconText) {
                Image(systemName: metricType.icon)
                    .font(.system(size: DesignTokens.Icons.standard, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.accent)
                    .frame(width: DesignTokens.Spacing.iconFrame)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                    Text(metricType.displayName)
                        .font(DesignTokens.Typography.sectionTitle)

                    Text(metricType.description)
                        .font(DesignTokens.Typography.tiny)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { config.isEnabled },
                    set: { newValue in
                        config.isEnabled = newValue
                        onConfigChanged()
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if config.isEnabled {
                // Icon style selector (only for Session and Week, not API)
                if metricType != .api {
                    Divider()
                        .padding(.vertical, DesignTokens.Spacing.extraSmall)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text("ui.icon_style".localized)
                            .font(DesignTokens.Typography.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        IconStylePicker(selectedStyle: Binding(
                            get: { config.iconStyle },
                            set: { newValue in
                                config.iconStyle = newValue
                                onConfigChanged()
                            }
                        ))
                    }
                }

                // Progress direction (for session and week circular styles)
                if metricType != .api {
                    Divider()
                        .padding(.vertical, DesignTokens.Spacing.extraSmall)

                    SettingToggle(
                        title: "appearance.clockwise_title".localized,
                        description: "appearance.clockwise_description".localized,
                        isOn: Binding(
                            get: { config.clockwiseProgress },
                            set: { newValue in
                                config.clockwiseProgress = newValue
                                onConfigChanged()
                            }
                        )
                    )
                }

                // Metric-specific options
                if metricType == .session && (config.iconStyle == .battery || config.iconStyle == .progressBar) {
                    Divider()
                        .padding(.vertical, DesignTokens.Spacing.extraSmall)

                    SessionDisplayOptions(config: $config, onConfigChanged: onConfigChanged)
                } else if metricType == .week && config.iconStyle == .percentageOnly {
                    Divider()
                        .padding(.vertical, DesignTokens.Spacing.extraSmall)

                    WeekDisplayOptions(config: $config, onConfigChanged: onConfigChanged)
                } else if metricType == .api {
                    Divider()
                        .padding(.vertical, DesignTokens.Spacing.extraSmall)

                    APIDisplayOptions(config: $config, onConfigChanged: onConfigChanged)
                }
            }
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(DesignTokens.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(
                    config.isEnabled ? DesignTokens.Colors.success.opacity(0.3) : DesignTokens.Colors.cardBorder,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Session Display Options

private struct SessionDisplayOptions: View {
    @Binding var config: MetricIconConfig
    let onConfigChanged: () -> Void

    var body: some View {
        SettingToggle(
            title: "metric.show_countdown".localized,
            description: "metric.countdown_description".localized,
            isOn: Binding(
                get: { config.showNextSessionTime },
                set: { newValue in
                    config.showNextSessionTime = newValue
                    onConfigChanged()
                }
            )
        )
    }
}

// MARK: - Week Display Options

private struct WeekDisplayOptions: View {
    @Binding var config: MetricIconConfig
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("ui.display_mode".localized)
                .font(DesignTokens.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Picker("", selection: Binding(
                get: { config.weekDisplayMode },
                set: { newValue in
                    config.weekDisplayMode = newValue
                    onConfigChanged()
                }
            )) {
                ForEach(WeekDisplayMode.allCases, id: \.self) { mode in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                        Text(mode.displayName)
                        Text(mode.description)
                            .font(DesignTokens.Typography.tiny)
                            .foregroundColor(.secondary)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }
}

// MARK: - API Display Options

private struct APIDisplayOptions: View {
    @Binding var config: MetricIconConfig
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("ui.display_mode".localized)
                .font(DesignTokens.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Picker("", selection: Binding(
                get: { config.apiDisplayMode },
                set: { newValue in
                    config.apiDisplayMode = newValue
                    onConfigChanged()
                }
            )) {
                ForEach(APIDisplayMode.allCases, id: \.self) { mode in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                        Text(mode.displayName)
                        Text(mode.description)
                            .font(DesignTokens.Typography.tiny)
                            .foregroundColor(.secondary)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }
}

// MARK: - Previews

#Preview("Session Card - Enabled") {
    MetricIconCard(
        metricType: .session,
        config: .constant(.sessionDefault),
        onConfigChanged: {}
    )
    .frame(width: 500)
    .padding()
}

#Preview("Week Card - Enabled") {
    MetricIconCard(
        metricType: .week,
        config: .constant(MetricIconConfig(
            metricType: .week,
            isEnabled: true,
            iconStyle: .battery,
            order: 1,
            weekDisplayMode: .percentage
        )),
        onConfigChanged: {}
    )
    .frame(width: 500)
    .padding()
}

#Preview("API Card - Disabled") {
    MetricIconCard(
        metricType: .api,
        config: .constant(.apiDefault),
        onConfigChanged: {}
    )
    .frame(width: 500)
    .padding()
}
