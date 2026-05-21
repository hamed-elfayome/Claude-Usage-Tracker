//
//  MobileAppView.swift
//  Claude Usage
//
//  Pairing screen for the companion mobile app. Lets the user enable a
//  read-only local server (LocalServerService) and pair a phone by scanning
//  a QR code that encodes { host, port, token }.
//
//  The Claude session key never leaves this machine — the phone only ever
//  reads the derived usage numbers over the local network.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct MobileAppView: View {
    @State private var isEnabled = SharedDataStore.shared.loadLocalServerEnabled()
    @State private var lanAddress: String? = LocalServerService.primaryLANAddress()
    @State private var token: String = ""
    @State private var didCopy = false

    private var port: Int { SharedDataStore.shared.loadLocalServerPort() }

    /// JSON payload encoded into the pairing QR code.
    private var pairingPayload: String? {
        guard let host = lanAddress, !token.isEmpty else { return nil }
        let dict: [String: Any] = [
            "v": 1,
            "host": host,
            "port": port,
            "token": token
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "Mobile App",
                    subtitle: "View your usage on your phone over your local network"
                )

                SettingToggle(
                    title: "Enable companion server",
                    description: "Serves your current usage (read-only) to paired devices on this network. Off by default.",
                    badge: .beta,
                    isOn: Binding(
                        get: { isEnabled },
                        set: { setEnabled($0) }
                    )
                )

                if isEnabled {
                    pairingCard
                    securityNote
                } else {
                    SettingsCard {
                        Text("Turn this on to pair the Claude Usage mobile app. Your Mac will serve usage data to your phone while it's awake and on the same Wi-Fi network.")
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }
            .padding(28)
        }
        .onAppear {
            token = SharedDataStore.shared.loadOrCreateLocalServerToken()
            lanAddress = LocalServerService.primaryLANAddress()
        }
    }

    // MARK: - Pairing card

    private var pairingCard: some View {
        SettingsCard(title: "Pair your phone") {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                if let payload = pairingPayload, let qr = Self.qrImage(from: payload) {
                    HStack {
                        Spacer()
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 180, height: 180)
                            .padding(8)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
                        Spacer()
                    }
                    Text("Open the Claude Usage app on your phone and scan this code.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label("No local network address found. Connect to Wi-Fi and reopen this screen.",
                          systemImage: "wifi.exclamationmark")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(SettingsColors.warning)
                }

                Divider()

                detailRow(label: "Address", value: lanAddress.map { "\($0):\(port)" } ?? "—")
                detailRow(label: "Token", value: token, monospaced: true)

                HStack(spacing: DesignTokens.Spacing.small) {
                    SettingsButton.subtle(
                        title: didCopy ? "Copied" : "Copy details",
                        icon: didCopy ? "checkmark" : "doc.on.doc",
                        action: copyDetails
                    )
                    SettingsButton.subtle(
                        title: "Regenerate token",
                        icon: "arrow.triangle.2.circlepath",
                        action: regenerateToken
                    )
                }
            }
        }
    }

    private func detailRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : DesignTokens.Typography.caption)
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
            Image(systemName: "lock.shield")
                .font(.system(size: DesignTokens.Icons.tiny))
                .foregroundColor(.secondary)
            Text("Read-only and token-protected. Your Claude session key never leaves this Mac — the phone only sees usage numbers. Regenerating the token un-pairs existing devices.")
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        SharedDataStore.shared.saveLocalServerEnabled(enabled)
        if enabled {
            token = SharedDataStore.shared.loadOrCreateLocalServerToken()
            lanAddress = LocalServerService.primaryLANAddress()
            LocalServerService.shared.start()
        } else {
            LocalServerService.shared.stop()
        }
    }

    private func regenerateToken() {
        token = SharedDataStore.shared.regenerateLocalServerToken()
        if isEnabled { LocalServerService.shared.restart() }
    }

    private func copyDetails() {
        let details = "Host: \(lanAddress ?? "?")\nPort: \(port)\nToken: \(token)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
    }

    // MARK: - QR generation

    private static func qrImage(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}

#Preview {
    MobileAppView()
        .frame(width: 520, height: 700)
}
