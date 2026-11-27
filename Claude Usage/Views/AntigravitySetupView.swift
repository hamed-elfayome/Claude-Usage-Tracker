//
//  AntigravitySetupView.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-11-27.
//

import SwiftUI

/// Wizard step for Google Antigravity profiles: detect the `agy` CLI (which
/// owns the Google login) and pick the quota pool the profile shows.
struct AntigravitySetupView: View {
    let onDone: (AntigravityPool) -> Void
    let onBack: () -> Void

    @State private var executable: URL?
    @State private var isDetecting = true
    @State private var pool: AntigravityPool = .thirdParty

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 80, height: 80)

                    ProviderLogoView(provider: .antigravity, size: 36)
                        .foregroundColor(.blue)
                }

                if isDetecting {
                    ProgressView()
                } else if executable != nil {
                    Text("setup.antigravity_detected.title".localized)
                        .font(.system(size: 24, weight: .bold))

                    Text("setup.antigravity_detected.description".localized)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 60)

                    Picker("", selection: $pool) {
                        ForEach(AntigravityPool.allCases, id: \.self) { pool in
                            Text(AntigravityAccountView.poolName(pool)).tag(pool)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    Button(action: { onDone(pool) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.bar.fill")
                            Text("setup.cli_detected.start".localized)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("setup.antigravity_not_detected.title".localized)
                        .font(.system(size: 24, weight: .bold))

                    Text("setup.antigravity_not_detected.description".localized)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 60)

                    Button(action: { detect(resetShellLookup: true) }) {
                        Text("antigravity.rescan".localized)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button(action: onBack) {
                    Text("common.back".localized)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(width: 580, height: 680)
        .onAppear { detect(resetShellLookup: false) }
    }

    private func detect(resetShellLookup: Bool) {
        if resetShellLookup { AntigravityCLILocator.shared.resetShellLookup() }
        isDetecting = true
        Task {
            let found = await AntigravityCLILocator.shared.resolve()
            await MainActor.run {
                executable = found
                isDetecting = false
            }
        }
    }
}
