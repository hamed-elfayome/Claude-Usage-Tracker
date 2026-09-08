//
//  NotifySettingsView.swift
//  Claude Usage
//
//  Where the Notify! device is linked, the three surfaces are switched, the
//  Lock Screen gauge's window is chosen, and a publish can be forced.
//

import SwiftUI

struct NotifySettingsView: View {
    private let store = NotifySettingsStore.shared

    // Everything below is filled in by `loadFromStore()` on appear rather than
    // in a property default. A default expression runs on every construction of
    // the view, and one of these reads the Keychain, which is not something to
    // do on every SwiftUI re-init of a settings pane.
    @State private var enabled = false
    @State private var deviceId = ""
    @State private var token = ""

    @State private var liveActivityEnabled = true
    @State private var widgetEnabled = true
    @State private var screenWidgetEnabled = true

    @State private var gaugeSelectionId = ""

    /// Whether a link is actually saved, as opposed to merely typed into the
    /// two fields. Held in state rather than asked of the store on every body
    /// pass, because answering it means a Keychain lookup.
    @State private var isLinked = false


    @State private var isVerifying = false
    @State private var isPublishing = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    @StateObject private var profileManager = ProfileManager.shared

    /// The link the two fields currently describe, or nil when they do not yet
    /// make one. Everything that needs a device to talk to reads this, so the
    /// pane never has to ask twice whether it is linked.
    private var draftLink: NotifyDeviceLink? {
        NotifyDeviceLink(deviceId: deviceId, token: token)
    }

    /// A switch that writes through to the store as the user flips it.
    ///
    /// A write-through binding rather than `onChange`, because `onChange` fires
    /// for any change including the one `loadFromStore` makes on appear, and
    /// telling those two apart needs a flag that is easy to get wrong. A
    /// binding's setter runs only when somebody actually flips the switch.
    private func writeThrough(
        _ value: Binding<Bool>,
        to save: @escaping (Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                save(newValue)
                postSettingsChanged()
            }
        )
    }

    /// The gauge picker's selection, in the "provider|window" spelling the
    /// store persists. Empty means automatic.
    private var gaugeBinding: Binding<String> {
        Binding(
            get: { gaugeSelectionId },
            set: { newValue in
                gaugeSelectionId = newValue
                saveGaugeSelection(newValue)
                postSettingsChanged()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "notify.title".localized,
                    subtitle: "notify.subtitle".localized
                )

                enableCard
                linkCard

                if enabled {
                    surfacesCard
                    gaugeCard
                    publishCard
                }

                privacyCard
            }
            .padding()
        }
        .onAppear(perform: loadFromStore)
    }

    // MARK: - Enable

    private var enableCard: some View {
        SettingsSectionCard(
            title: "notify.section.publishing".localized,
            subtitle: "notify.section.publishing_desc".localized
        ) {
            SettingToggle(
                title: "notify.enable".localized,
                description: "notify.enable_desc".localized,
                badge: .beta,
                isOn: writeThrough($enabled, to: store.setEnabled)
            )
            .disabled(!isLinked && !enabled)
            .opacity(!isLinked && !enabled ? 0.5 : 1.0)
        }
    }

    // MARK: - Link

    private var linkCard: some View {
        SettingsSectionCard(
            title: "notify.section.device".localized,
            subtitle: "notify.section.device_desc".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("notify.device_id".localized)
                        .font(DesignTokens.Typography.bodyMedium)
                    TextField("notify.device_id.placeholder".localized, text: $deviceId)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: deviceId) { _, newValue in
                            // The Notify! app also offers a ready-made
                            // notification URL with both halves in it, so a
                            // paste into either field is unpicked rather than
                            // rejected as a malformed ID.
                            adoptPastedText(newValue)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("notify.device_token".localized)
                        .font(DesignTokens.Typography.bodyMedium)
                    SecureField("notify.device_token.placeholder".localized, text: $token)
                        .textFieldStyle(.roundedBorder)
                }

                if let kind = draftLink?.kind {
                    deviceKindNotes(kind)
                }

                HStack(spacing: DesignTokens.Spacing.medium) {
                    SettingsButton(
                        title: isVerifying
                            ? "notify.verifying".localized
                            : "notify.verify".localized,
                        icon: "checkmark.shield",
                        style: .secondary
                    ) {
                        verifyDevice()
                    }
                    .disabled(draftLink == nil || isVerifying)

                    SettingsButton(
                        title: "notify.save_link".localized,
                        icon: "link",
                        style: .primary
                    ) {
                        saveLink()
                    }
                    .disabled(draftLink == nil)

                    if isLinked {
                        SettingsButton(
                            title: "notify.unlink".localized,
                            icon: "trash",
                            style: .destructive
                        ) {
                            unlink()
                        }
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(DesignTokens.Typography.body)
                        .foregroundColor(statusIsError ? SettingsColors.error : SettingsColors.success)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The sentences that explain what this particular ID can and cannot carry.
    ///
    /// Shown per surface rather than as one verdict, because the three are
    /// gated differently: a Mac can keep both widgets and cannot show a Live
    /// Activity, and a user who reads only "unsupported" would switch the whole
    /// feature off over a limit that costs them one surface.
    @ViewBuilder
    private func deviceKindNotes(_ kind: NotifyDeviceKind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reason = kind.liveActivityUnsupportedReason {
                noteRow(reason)
            }
            if let reason = kind.widgetUnsupportedReason {
                noteRow(reason)
            }
        }
    }

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundColor(SettingsColors.warning)
            Text(text)
                .font(DesignTokens.Typography.body)
                .foregroundColor(SettingsColors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Surfaces

    private var surfacesCard: some View {
        SettingsSectionCard(
            title: "notify.section.surfaces".localized,
            subtitle: "notify.section.surfaces_desc".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                SettingToggle(
                    title: "notify.surface.live_activity".localized,
                    description: "notify.surface.live_activity_desc".localized,
                    badge: nil,
                    isOn: writeThrough($liveActivityEnabled, to: store.setLiveActivityEnabled)
                )
                .disabled(draftLink?.supportsLiveActivity == false)
                .opacity(draftLink?.supportsLiveActivity == false ? 0.5 : 1.0)

                SettingToggle(
                    title: "notify.surface.lock_screen".localized,
                    description: "notify.surface.lock_screen_desc".localized,
                    badge: nil,
                    isOn: writeThrough($widgetEnabled, to: store.setWidgetEnabled)
                )
                .disabled(draftLink?.supportsWidget == false)
                .opacity(draftLink?.supportsWidget == false ? 0.5 : 1.0)

                SettingToggle(
                    title: "notify.surface.home_screen".localized,
                    description: "notify.surface.home_screen_desc".localized,
                    badge: nil,
                    isOn: writeThrough($screenWidgetEnabled, to: store.setScreenWidgetEnabled)
                )
                .disabled(draftLink?.supportsScreenWidget == false)
                .opacity(draftLink?.supportsScreenWidget == false ? 0.5 : 1.0)
            }
        }
    }

    // MARK: - Gauge

    private var gaugeCard: some View {
        SettingsSectionCard(
            title: "notify.section.gauge".localized,
            subtitle: "notify.section.gauge_desc".localized
        ) {
            Picker("notify.gauge.window".localized, selection: gaugeBinding) {
                Text("notify.gauge.automatic".localized).tag("")
                ForEach(availableWindows) { window in
                    Text(window.label).tag(window.id)
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// The windows the active profile is currently reporting, as picker rows.
    ///
    /// Built from the same function the driver publishes through, so a window
    /// that can be chosen here is a window that will actually reach the phone.
    private var availableWindows: [GaugeWindow] {
        guard let profile = profileManager.activeProfile,
              let usage = profile.claudeUsage else {
            return []
        }
        return NotifyUsageReadings.readings(from: usage, provider: profile.provider)
            .map { reading in
                GaugeWindow(
                    id: "\(reading.providerId)|\(reading.quota.key)",
                    label: "\(reading.providerName) \(reading.quota.label)"
                )
            }
    }

    /// One row of the gauge picker. The `id` is the same "provider|window"
    /// string the store persists, so the picker's selection needs no
    /// translation on the way in or out.
    private struct GaugeWindow: Identifiable {
        let id: String
        let label: String
    }

    // MARK: - Publish

    private var publishCard: some View {
        SettingsSectionCard(
            title: "notify.section.publish".localized,
            subtitle: "notify.section.publish_desc".localized
        ) {
            SettingsButton(
                title: isPublishing
                    ? "notify.publishing".localized
                    : "notify.publish_now".localized,
                icon: "paperplane.fill",
                style: .primary
            ) {
                publishNow()
            }
            .disabled(isPublishing || !isLinked)
        }
    }

    // MARK: - Privacy

    private var privacyCard: some View {
        SettingsSectionCard(
            title: "notify.section.privacy".localized,
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 6) {
                BulletPoint("notify.privacy.what_leaves".localized)
                BulletPoint("notify.privacy.where_it_goes".localized)
                BulletPoint("notify.privacy.off_by_default".localized)
                BulletPoint("notify.privacy.token_secret".localized)
            }
        }
    }

    // MARK: - Actions

    /// Unpicks a pasted notification URL, or an "id token" pair, into the two
    /// fields. Silent when the text is neither, because that is simply somebody
    /// typing an ID one character at a time.
    private func adoptPastedText(_ text: String) {
        guard text.count > 32 || text.contains("/") || text.contains(" ") else { return }
        if let link = NotifyDeviceLink(pastedText: text) {
            deviceId = link.deviceId
            token = link.token
        } else if let identifier = NotifyDeviceLink.deviceId(inPastedText: text) {
            deviceId = identifier
        }
    }

    private func saveLink() {
        guard let link = draftLink else { return }

        // The store reports whether the token actually landed. Claiming a link
        // that did not save is how a user ends up pressing Send Now and being
        // told to add the ID and token they can see in front of them.
        guard store.saveDeviceLink(link) else {
            isLinked = false
            show("notify.status.link_save_failed".localized, isError: true)
            return
        }

        isLinked = true
        show("notify.status.link_saved".localized, isError: false)
        postSettingsChanged()
    }

    private func unlink() {
        store.clearDeviceLink()
        isLinked = false
        deviceId = ""
        token = ""
        enabled = false
        store.setEnabled(false)
        show("notify.status.unlinked".localized, isError: false)
        postSettingsChanged()
    }

    /// Checks the credentials against the gateway and names the device they
    /// point at.
    ///
    /// Behind a button and nothing else: the gateway rate limits this route to
    /// five calls a minute per IP, so nothing on a timer may reach it.
    private func verifyDevice() {
        guard let link = draftLink else { return }
        isVerifying = true
        statusMessage = nil

        Task { @MainActor in
            defer { isVerifying = false }
            do {
                let info = try await NotifyGatewayClient().deviceInfo(link: link)
                show("notify.status.verified".localized(with: info.displayDescription), isError: false)
            } catch {
                let message = (error as? NotifyPublishError)?.errorDescription ?? error.localizedDescription
                show(message, isError: true)
            }
        }
    }

    /// Forces a publish through the driver rather than writing to the gateway
    /// here. The driver holds the stored handles and the single in-flight
    /// publish, and two publishers racing over one nil activity id is exactly
    /// how a phone ends up with two Live Activities.
    private func publishNow() {
        isPublishing = true
        statusMessage = nil

        Task { @MainActor in
            defer { isPublishing = false }
            if let failure = await NotifyPublishDriver.shared.publishNow() {
                show(failure, isError: true)
            } else {
                show("notify.status.published".localized, isError: false)
            }
        }
    }

    /// Fills the pane in from the store, including the one Keychain read.
    private func loadFromStore() {
        enabled = store.isEnabled()
        deviceId = store.deviceId()
        token = store.deviceToken() ?? ""
        liveActivityEnabled = store.isLiveActivityEnabled()
        widgetEnabled = store.isWidgetEnabled()
        screenWidgetEnabled = store.isScreenWidgetEnabled()

        let providerId = store.gaugeProviderId()
        let quotaKey = store.gaugeQuotaKey()
        gaugeSelectionId = providerId.isEmpty || quotaKey.isEmpty ? "" : "\(providerId)|\(quotaKey)"
        // From the two values just loaded, so the Keychain is read once here.
        isLinked = NotifyDeviceLink(deviceId: deviceId, token: token) != nil
    }

    private func saveGaugeSelection(_ identifier: String) {
        let parts = identifier.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            store.setGaugeProviderId("")
            store.setGaugeQuotaKey("")
            return
        }
        store.setGaugeProviderId(parts[0])
        store.setGaugeQuotaKey(parts[1])
    }

    private func show(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    /// The link, the switches and the gauge selection all live outside the
    /// state the driver watches, so it has no other way to notice a save.
    private func postSettingsChanged() {
        NotificationCenter.default.post(name: .notifySettingsChanged, object: nil)
    }
}

#Preview {
    NotifySettingsView()
        .frame(width: 560, height: 620)
}
