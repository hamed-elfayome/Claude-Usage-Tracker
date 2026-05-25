import SwiftUI

struct SessionPlanningSettingsView: View {
    let profile: Profile
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var planningService = SessionPlanningService.shared

    private var settings: SessionPlanningSettings {
        profile.sessionPlanningSettings ?? .default
    }

    var body: some View {
        SettingsSectionCard(
            title: "planning.title".localized,
            subtitle: "planning.subtitle".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                // Educational card
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                        Text("planning.educational_title".localized)
                            .font(DesignTokens.Typography.caption)
                            .fontWeight(.medium)
                    }
                    Text("planning.educational_body".localized)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                }
                .padding(DesignTokens.Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .fill(Color.accentColor.opacity(0.06))
                )

                // Enable toggle
                SettingToggle(
                    title: "planning.enable".localized,
                    isOn: Binding(
                        get: { settings.isEnabled },
                        set: { newValue in
                            updateSettings { $0.isEnabled = newValue }
                        }
                    )
                )

                if settings.isEnabled {
                    Divider()

                    // Planned work start
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text("planning.planned_work_start".localized)
                            .font(DesignTokens.Typography.body)

                        DatePicker(
                            "",
                            selection: Binding(
                                get: { settings.plannedWorkStart ?? Date() },
                                set: { newValue in
                                    updateSettings { $0.plannedWorkStart = newValue }
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.field)
                        .labelsHidden()
                    }

                    // Typical time to limit
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        HStack {
                            Text("planning.typical_time_to_limit".localized)
                                .font(DesignTokens.Typography.body)
                            Spacer()
                            Text("\(settings.manualTypicalTimeToLimitMinutes) min")
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(settings.manualTypicalTimeToLimitMinutes) },
                                set: { newValue in
                                    updateSettings { $0.manualTypicalTimeToLimitMinutes = Int(newValue) }
                                }
                            ),
                            in: Double(Constants.SessionPlanning.minTimeToLimitMinutes)...Double(Constants.SessionPlanning.maxTimeToLimitMinutes),
                            step: 15
                        )

                        // Auto-estimate toggle
                        SettingToggle(
                            title: "planning.auto_estimate".localized,
                            isOn: Binding(
                                get: { settings.useAutoEstimate },
                                set: { newValue in
                                    updateSettings { $0.useAutoEstimate = newValue }
                                }
                            )
                        )

                        if settings.useAutoEstimate {
                            let estimate = planningService.estimateTypicalTimeToLimit(for: profile)
                            if estimate == settings.manualTypicalTimeToLimitMinutes {
                                Text("planning.auto_estimate_not_enough".localized)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Estimated: \(estimate) minutes (based on usage history)")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.adaptiveGreen)
                            }
                        }
                    }

                    // Ping mode
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        SettingToggle(
                            title: "planning.reminder_only".localized,
                            isOn: Binding(
                                get: { !settings.autoPingEnabled },
                                set: { newValue in
                                    updateSettings { $0.autoPingEnabled = !newValue }
                                }
                            )
                        )

                        if settings.autoPingEnabled {
                            VStack(alignment: .leading, spacing: 4) {
                                SettingToggle(
                                    title: "planning.auto_ping".localized,
                                    isOn: Binding(
                                        get: { settings.autoPingEnabled },
                                        set: { newValue in
                                            updateSettings { $0.autoPingEnabled = newValue }
                                        }
                                    )
                                )
                                Text("planning.auto_ping_opt_in".localized)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    // Waste warning
                    SettingToggle(
                        title: "planning.waste_warning".localized,
                        isOn: Binding(
                            get: { settings.wasteWarningEnabled },
                            set: { newValue in
                                updateSettings { $0.wasteWarningEnabled = newValue }
                            }
                        )
                    )

                    // Plan mode tips
                    SettingToggle(
                        title: "planning.plan_mode_tips".localized,
                        isOn: Binding(
                            get: { settings.planModeTipsEnabled },
                            set: { newValue in
                                updateSettings { $0.planModeTipsEnabled = newValue }
                            }
                        )
                    )

                    // Live recommendation
                    if let pingTime = planningService.calculateRecommendedPingTime(for: profile),
                       let secondSessionTime = planningService.calculateSecondSessionAvailableTime(for: profile) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            Text("planning.recommendation".localized(
                                with: FormatterHelper.timeString(from: pingTime),
                                FormatterHelper.timeString(from: secondSessionTime)
                            ))
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.accentColor)

                            HStack(spacing: DesignTokens.Spacing.small) {
                                Button {
                                    if let url = URL(string: "https://claude.ai") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up.forward.square")
                                            .font(.system(size: 10))
                                        Text("planning.open_claude".localized)
                                            .font(DesignTokens.Typography.caption)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(Constants.SessionPlanning.dummyPrompt, forType: .string)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10))
                                        Text("planning.copy_prompt".localized)
                                            .font(DesignTokens.Typography.caption)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(DesignTokens.Spacing.small)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                .fill(Color.accentColor.opacity(0.06))
                        )
                    }
                }
            }
        }
    }

    private func updateSettings(_ block: (inout SessionPlanningSettings) -> Void) {
        var updatedSettings = settings
        block(&updatedSettings)
        profileManager.updateSessionPlanningSettings(updatedSettings, for: profile.id)
    }
}