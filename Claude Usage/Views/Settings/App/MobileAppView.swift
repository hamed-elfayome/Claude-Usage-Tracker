//
//  MobileAppView.swift
//  Claude Usage
//
//  "Painted door" interest-collection view for a potential mobile app.
//
//  Created by Claude Code on 2026-02-25.
//

import SwiftUI

// ─────────────────────────────────────────────────────────────────────
// IMPORTANT — Analytics-only endpoint (NO credentials involved)
// ─────────────────────────────────────────────────────────────────────
//
// The URL below is a lightweight Cloudflare Worker that **only** records
// anonymous interest signals (a single POST with `?type=mobile`).
//
// • It does NOT receive, store, or process any user credentials.
// • It does NOT receive any personally-identifiable information.
// • It does NOT set cookies or return tracking identifiers.
// • It is completely separate from the Claude AI / Anthropic APIs.
//
// Its sole purpose is to count how many users tap "Notify Me" so the
// developer can gauge demand before investing in a mobile app.
//
// Domain: claude-usage-tracker.hamedelfayome.workers.dev
// ─────────────────────────────────────────────────────────────────────
private let kAnalyticsOnlyEndpoint = "https://claude-usage-tracker.hamedelfayome.workers.dev?type=mobile"

/// Mobile app "coming soon" painted-door view.
/// Collects interest via a single analytics-only POST request.
struct MobileAppView: View {
    @State private var hasNotified = UserDefaults.standard.bool(forKey: "mobileApp.notifyMe")
    @State private var isSubmitting = false
    @State private var showError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "mobile.title".localized,
                    subtitle: "mobile.subtitle".localized
                )

                // Coming Soon badge + icon
                HStack {
                    Spacer()
                    VStack(spacing: DesignTokens.Spacing.medium) {
                        Image(systemName: "iphone")
                            .font(.system(size: 28))
                            .foregroundColor(.accentColor)

                        Text("mobile.coming_soon_badge".localized)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1)
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                    }
                    Spacer()
                }

                Divider()

                // Notify Me / Already notified
                if hasNotified {
                    HStack(spacing: DesignTokens.Spacing.medium) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: DesignTokens.Icons.standard))
                            .foregroundColor(SettingsColors.success)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("mobile.notified".localized)
                                .font(DesignTokens.Typography.bodyMedium)
                            Text("mobile.notified_desc".localized)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(DesignTokens.Spacing.medium)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                            .fill(SettingsColors.lightOverlay(.green))
                    )
                } else {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        Text("mobile.cta_message".localized)
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(.secondary)

                        SettingsButton.primary(
                            title: isSubmitting ? "mobile.submitting".localized : "mobile.notify_me".localized,
                            icon: isSubmitting ? nil : "bell",
                            action: submitInterest
                        )
                        .disabled(isSubmitting)
                    }
                }

                // Privacy note
                HStack(spacing: DesignTokens.Spacing.small) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: DesignTokens.Icons.tiny))
                        .foregroundColor(.secondary)
                    Text("mobile.privacy_note".localized)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(28)
        }
        .alert("mobile.error_title".localized, isPresented: $showError) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            Text("mobile.error_message".localized)
        }
    }

    // MARK: - Analytics-only POST (no credentials, no PII)

    /// Sends a single anonymous POST to the analytics-only endpoint.
    /// See the comment at the top of this file for full details.
    private func submitInterest() {
        guard !isSubmitting, !hasNotified else { return }
        isSubmitting = true

        Task {
            do {
                guard let url = URL(string: kAnalyticsOnlyEndpoint) else { return }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 15

                let (_, response) = try await URLSession.shared.data(for: request)

                await MainActor.run {
                    if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        hasNotified = true
                        UserDefaults.standard.set(true, forKey: "mobileApp.notifyMe")
                    } else {
                        showError = true
                    }
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    showError = true
                    isSubmitting = false
                }
            }
        }
    }
}

#Preview {
    MobileAppView()
        .frame(width: 520, height: 600)
}
