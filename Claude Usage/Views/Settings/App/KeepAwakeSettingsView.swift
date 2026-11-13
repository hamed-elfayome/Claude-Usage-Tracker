//
//  KeepAwakeSettingsView.swift
//  Claude Usage
//
//  Settings for Keep Awake: manual toggle with duration (presets or custom
//  hours), auto mode driven by Claude Code sessions with a configurable
//  grace period, and the sleep-prevention type (system vs display).
//

import SwiftUI

struct KeepAwakeSettingsView: View {
    /// Sentinel tag for the "Custom…" picker rows.
    private static let customTag: TimeInterval = -1

    private static let durationPresets: [TimeInterval] = [15 * 60, 30 * 60, 3600, 2 * 3600, 4 * 3600, 8 * 3600]
    private static let gracePresets: [TimeInterval] = [15 * 60, 30 * 60, 3600]

    @ObservedObject private var service = KeepAwakeService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var autoEnabled: Bool = SharedDataStore.shared.loadKeepAwakeAutoEnabled()
    @State private var sleepMode: KeepAwakeService.SleepMode =
        SharedDataStore.shared.loadKeepAwakeSleepMode()
            .flatMap(KeepAwakeService.SleepMode.init(rawValue:)) ?? .default

    @State private var durationChoice: TimeInterval = 0
    @State private var customDurationHours: Int = 3
    @State private var graceChoice: TimeInterval = 15 * 60
    @State private var customGraceHours: Int = 1
    @State private var statusPulse = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "section.keep_awake_title".localized,
                    subtitle: "section.keep_awake_desc".localized
                )

                autoCard
                manualCard
                sleepTypeCard
            }
            .padding()
        }
        .onAppear(perform: loadPickerState)
        .onChange(of: autoEnabled) { _, newValue in
            service.setAutoEnabled(newValue)
        }
        .onChange(of: sleepMode) { _, newValue in
            SharedDataStore.shared.saveKeepAwakeSleepMode(newValue.rawValue)
            NotificationCenter.default.post(name: .keepAwakeSettingChanged, object: nil)
        }
        .onChange(of: durationChoice) { _, _ in saveDuration() }
        .onChange(of: customDurationHours) { _, _ in saveDuration() }
        .onChange(of: graceChoice) { _, _ in saveGracePeriod() }
        .onChange(of: customGraceHours) { _, _ in saveGracePeriod() }
    }

    // MARK: - Manual card

    private var manualCard: some View {
        SettingsSectionCard(
            title: "keep_awake.manual_title".localized,
            subtitle: "keep_awake.manual_desc".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                SettingToggle(
                    title: "keep_awake.enable".localized,
                    description: "keep_awake.enable_desc".localized,
                    isOn: Binding(
                        get: { service.isManualOn },
                        set: { service.setManual(on: $0) }
                    )
                )

                if service.isAssertionHeld {
                    statusRow
                }

                pickerRow(label: "keep_awake.duration".localized) {
                    Picker("", selection: $durationChoice) {
                        Text("keep_awake.duration.indefinite".localized).tag(TimeInterval(0))
                        ForEach(Self.durationPresets, id: \.self) { preset in
                            Text(Self.format(preset)).tag(preset)
                        }
                        Text("keep_awake.duration.custom".localized).tag(Self.customTag)
                    }
                }

                if durationChoice == Self.customTag {
                    customHoursStepper(hours: $customDurationHours)
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .scaleEffect(statusPulse && !reduceMotion ? 1.25 : 1.0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: statusPulse
                )
                .onAppear { statusPulse = true }
                .onDisappear { statusPulse = false }

            if let expiry = service.manualExpiry {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("keep_awake.remaining".localized(with: Self.formatRemaining(until: expiry, from: context.date)))
                        .font(DesignTokens.Typography.body)
                        .foregroundColor(SettingsColors.secondary)
                }
            } else {
                Text("keep_awake.status_active".localized)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(SettingsColors.secondary)
            }
            Spacer()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Auto card

    private var autoCard: some View {
        SettingsSectionCard(
            title: "keep_awake.auto_title".localized,
            subtitle: "keep_awake.auto_card_desc".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                SettingToggle(
                    title: "keep_awake.auto".localized,
                    description: "keep_awake.auto_desc".localized,
                    badge: .beta,
                    isOn: Binding(
                        get: { autoEnabled },
                        set: { newValue in
                            // Turning it on adds hooks to Claude Code's settings: ask first.
                            if newValue, service.enablingAutoInstallsHooks, !KeepAwakeHookConsent.confirm() {
                                return
                            }
                            autoEnabled = newValue
                        }
                    )
                )

                if let problem = service.autoModeProblem {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(problem.message)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(SettingsColors.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }

                Group {
                    pickerRow(label: "keep_awake.grace".localized) {
                        Picker("", selection: $graceChoice) {
                            ForEach(Self.gracePresets, id: \.self) { preset in
                                Text("keep_awake.grace.stay".localized(with: Self.format(preset))).tag(preset)
                            }
                            Text("keep_awake.duration.custom".localized).tag(Self.customTag)
                        }
                    }

                    if graceChoice == Self.customTag {
                        customHoursStepper(hours: $customGraceHours)
                    }
                }
                .disabled(!autoEnabled)
                .opacity(autoEnabled ? 1.0 : 0.5)
                .padding(.leading, 16)

                Text("keep_awake.hooks_note".localized)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(SettingsColors.secondary)
            }
        }
    }

    // MARK: - Sleep type card

    private var sleepTypeCard: some View {
        SettingsSectionCard(
            title: "keep_awake.sleep_type".localized,
            subtitle: "keep_awake.sleep_type_desc".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                Picker("", selection: $sleepMode) {
                    Text("keep_awake.sleep_type.display".localized)
                        .tag(KeepAwakeService.SleepMode.preventDisplaySleep)
                    Text("keep_awake.sleep_type.system".localized)
                        .tag(KeepAwakeService.SleepMode.allowDisplaySleep)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("keep_awake.lid_note".localized)
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(SettingsColors.secondary)
            }
        }
    }

    // MARK: - Shared row builders

    private func pickerRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(DesignTokens.Typography.body)
            Spacer()
            content()
                .labelsHidden()
                .fixedSize()
        }
    }

    private func customHoursStepper(hours: Binding<Int>) -> some View {
        HStack {
            Spacer()
            Stepper(
                "keep_awake.custom_hours".localized(with: hours.wrappedValue),
                value: hours,
                in: 1...24
            )
            .font(DesignTokens.Typography.body)
            .fixedSize()
        }
    }

    // MARK: - Persistence

    private func loadPickerState() {
        let duration = SharedDataStore.shared.loadKeepAwakeDefaultDuration()
        if duration == 0 || Self.durationPresets.contains(duration) {
            durationChoice = duration
        } else {
            durationChoice = Self.customTag
            customDurationHours = max(1, min(24, Int((duration / 3600).rounded())))
        }

        let grace = SharedDataStore.shared.loadKeepAwakeAutoGracePeriod()
        if Self.gracePresets.contains(grace) {
            graceChoice = grace
        } else {
            graceChoice = Self.customTag
            customGraceHours = max(1, min(24, Int((grace / 3600).rounded())))
        }
    }

    private func saveDuration() {
        let duration = durationChoice == Self.customTag
            ? TimeInterval(customDurationHours) * 3600
            : durationChoice
        SharedDataStore.shared.saveKeepAwakeDefaultDuration(duration)
        NotificationCenter.default.post(name: .keepAwakeSettingChanged, object: nil)
    }

    private func saveGracePeriod() {
        let grace = graceChoice == Self.customTag
            ? TimeInterval(customGraceHours) * 3600
            : graceChoice
        SharedDataStore.shared.saveKeepAwakeAutoGracePeriod(grace)
        NotificationCenter.default.post(name: .keepAwakeSettingChanged, object: nil)
    }

    // MARK: - Formatting

    private static func format(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval < 3600 ? [.minute] : [.hour]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? ""
    }

    private static func formatRemaining(until expiry: Date, from reference: Date) -> String {
        let remaining = max(0, expiry.timeIntervalSince(reference))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = remaining < 3600 ? [.minute, .second] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: remaining) ?? ""
    }
}

#Preview {
    KeepAwakeSettingsView()
        .frame(width: 520, height: 560)
}

// MARK: - Hook consent and problem text

/// Auto mode works through Claude Code hooks. Adding them changes a file the
/// user owns, so the first time it would happen the user is asked.
enum KeepAwakeHookConsent {
    @MainActor
    static func confirm() -> Bool {
        let alert = NSAlert()
        alert.messageText = "keep_awake.consent_title".localized
        alert.informativeText = "keep_awake.consent_message".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "keep_awake.consent_confirm".localized)
        alert.addButton(withTitle: "common.cancel".localized)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension KeepAwakeService.AutoModeProblem {
    var message: String {
        switch self {
        case .hooksMissing: return "keep_awake.problem_hooks".localized
        case .listenerUnavailable: return "keep_awake.problem_listener".localized
        }
    }
}
