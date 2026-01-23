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
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header with enable toggle
            HStack {
                Image(systemName: metricType.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(SettingsColors.primary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(metricType.displayName)
                        .font(Typography.sectionHeader)

                    Text(metricType.description)
                        .font(.system(size: 10))
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
                // Icon style selector (only for Session and Week, not API or Claude Code)
                if metricType != .api && metricType != .claudeCode {
                    Divider()
                        .padding(.vertical, Spacing.xs)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("ui.icon_style".localized)
                            .font(.system(size: 11, weight: .medium))
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

                // Metric-specific options
                if metricType == .session && (config.iconStyle == .battery || config.iconStyle == .progressBar) {
                    Divider()
                        .padding(.vertical, Spacing.xs)

                    SessionDisplayOptions(config: $config, onConfigChanged: onConfigChanged)
                } else if metricType == .week && config.iconStyle == .percentageOnly {
                    Divider()
                        .padding(.vertical, Spacing.xs)

                    WeekDisplayOptions(config: $config, onConfigChanged: onConfigChanged)
                } else if metricType == .api {
                    Divider()
                        .padding(.vertical, Spacing.xs)

                    APIDisplayOptions(config: $config, onConfigChanged: onConfigChanged)
                } else if metricType == .claudeCode {
                    Divider()
                        .padding(.vertical, Spacing.xs)

                    ClaudeCodeDisplayOptions(config: $config, onConfigChanged: onConfigChanged)
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                .strokeBorder(
                    config.isEnabled ? SettingsColors.success.opacity(0.3) : Color.gray.opacity(0.2),
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: Binding(
                get: { config.showNextSessionTime },
                set: { newValue in
                    config.showNextSessionTime = newValue
                    onConfigChanged()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("metric.show_countdown".localized)
                        .font(.system(size: 11, weight: .medium))
                    Text("metric.countdown_description".localized)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }
}

// MARK: - Week Display Options

private struct WeekDisplayOptions: View {
    @Binding var config: MetricIconConfig
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("ui.display_mode".localized)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Picker("", selection: Binding(
                get: { config.weekDisplayMode },
                set: { newValue in
                    config.weekDisplayMode = newValue
                    onConfigChanged()
                }
            )) {
                ForEach(WeekDisplayMode.allCases, id: \.self) { mode in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.displayName)
                        Text(mode.description)
                            .font(.system(size: 10))
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("ui.display_mode".localized)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Picker("", selection: Binding(
                get: { config.apiDisplayMode },
                set: { newValue in
                    config.apiDisplayMode = newValue
                    onConfigChanged()
                }
            )) {
                ForEach(APIDisplayMode.allCases, id: \.self) { mode in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.displayName)
                        Text(mode.description)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }
}

// MARK: - Claude Code Display Options

private struct ClaudeCodeDisplayOptions: View {
    @Binding var config: MetricIconConfig
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("ui.display_mode".localized)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Picker("", selection: Binding(
                get: { config.claudeCodeDisplayMode },
                set: { newValue in
                    config.claudeCodeDisplayMode = newValue
                    onConfigChanged()
                }
            )) {
                ForEach(ClaudeCodeDisplayMode.allCases, id: \.self) { mode in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.displayName)
                        Text(mode.description)
                            .font(.system(size: 10))
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

#Preview("Claude Code Card - Enabled") {
    MetricIconCard(
        metricType: .claudeCode,
        config: .constant(MetricIconConfig(
            metricType: .claudeCode,
            isEnabled: true,
            iconStyle: .percentageOnly,
            order: 3,
            claudeCodeDisplayMode: .totalCost
        )),
        onConfigChanged: {}
    )
    .frame(width: 500)
    .padding()
}
