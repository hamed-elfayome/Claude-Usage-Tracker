//
//  AboutView.swift
//  Claude Usage - About and Credits
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// About page with app information and contributors
struct AboutView: View {
    @State private var contributors: [Contributor] = []
    @State private var isLoadingContributors = false
    @State private var contributorsError: String?

    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "Unknown"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App Icon and Title
                VStack(spacing: Spacing.lg) {
                    Image("AboutLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)

                    VStack(spacing: Spacing.xs) {
                        Text("Claude Usage Tracker")
                            .font(Typography.title)
                            .foregroundColor(.primary)

                        Text("Version \(appVersion)")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("Real-time usage monitoring for Claude AI")
                        .font(Typography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Spacing.xl)

                // Creator Card
                SettingsCard(title: "Created By") {
                    VStack(spacing: Spacing.md) {
                        Button(action: {
                            if let url = URL(string: "https://github.com/hamed-elfayome") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(SettingsColors.primary)

                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text("Hamed Elfayome")
                                        .font(Typography.sectionHeader)
                                        .foregroundColor(.primary)

                                    Text("@hamed-elfayome")
                                        .font(Typography.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                                    .fill(SettingsColors.lightOverlay(.gray, opacity: 0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Contributors Card
                SettingsCard(
                    title: "Contributors",
                    subtitle: !contributors.isEmpty ? "\(contributors.count) amazing people" : nil
                ) {
                    VStack(spacing: Spacing.md) {
                        if isLoadingContributors {
                            ContributorsLoadingView()
                        } else if let error = contributorsError {
                            ContributorsErrorView(error: error) {
                                fetchContributors()
                            }
                        } else if contributors.isEmpty {
                            EmptyContributorsView()
                        } else {
                            ContributorsGridView(contributors: contributors)
                        }
                    }
                }

                // Links and Actions
                SettingsCard(title: "Community") {
                    VStack(spacing: Spacing.buttonRowSpacing) {
                        SettingsButton.primary(
                            title: "Star on GitHub",
                            icon: "star.fill"
                        ) {
                            if let url = URL(string: "https://github.com/hamed-elfayome/Claude-Usage-Tracker") {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        HStack(spacing: Spacing.buttonRowSpacing) {
                            SettingsButton(
                                title: "Send Feedback",
                                icon: "envelope.fill"
                            ) {
                                if let url = URL(string: "mailto:hamedelfayome@gmail.com") {
                                    NSWorkspace.shared.open(url)
                                }
                            }

                            SettingsButton(
                                title: "Report Issue",
                                icon: "exclamationmark.triangle"
                            ) {
                                if let url = URL(string: "https://github.com/hamed-elfayome/Claude-Usage-Tracker/issues") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }

                // License and Copyright
                VStack(spacing: Spacing.xs) {
                    Text("Open Source • MIT License")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)

                    Text("© 2024 Hamed Elfayome")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, Spacing.lg)

                Spacer()
            }
            .padding(28)
        }
        .onAppear {
            if contributors.isEmpty && !isLoadingContributors {
                fetchContributors()
            }
        }
    }

    private func fetchContributors() {
        isLoadingContributors = true
        contributorsError = nil

        Task {
            do {
                let fetchedContributors = try await GitHubService.shared.fetchContributors()
                await MainActor.run {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        self.contributors = fetchedContributors
                        self.isLoadingContributors = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.contributorsError = error.localizedDescription
                    self.isLoadingContributors = false
                }
            }
        }
    }
}

// MARK: - Contributors Grid View
// (Reuse existing components from SettingsView.swift)

struct ContributorsGridView: View {
    let contributors: [Contributor]

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 44, maximum: 48), spacing: 10)
        ], spacing: 10) {
            ForEach(contributors) { contributor in
                ContributorAvatar(contributor: contributor)
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

struct ContributorAvatar: View {
    let contributor: Contributor
    @State private var isHovered = false
    @State private var imageData: Data?
    @State private var isLoadingImage = true

    var body: some View {
        Button(action: {
            if let url = URL(string: contributor.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        }) {
            ZStack {
                if let data = imageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else if isLoadingImage {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                        )
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary.opacity(0.3))
                        )
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(SettingsColors.primary, lineWidth: 2)
                    .opacity(isHovered ? 1 : 0)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .help(contributor.login)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            loadAvatar()
        }
    }

    private func loadAvatar() {
        guard let url = URL(string: contributor.avatarUrl) else {
            isLoadingImage = false
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    self.imageData = data
                    self.isLoadingImage = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingImage = false
                }
            }
        }
    }
}

struct ContributorsLoadingView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Loading contributors...")
                .font(Typography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}

struct ContributorsErrorView: View {
    let error: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(SettingsColors.warning)

            Text("Failed to load contributors")
                .font(Typography.body)

            Text(error)
                .font(Typography.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            SettingsButton(title: "Retry", icon: "arrow.clockwise") {
                retry()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }
}

struct EmptyContributorsView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No contributors found")
                .font(Typography.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}

// MARK: - Previews

#Preview {
    AboutView()
        .frame(width: 520, height: 600)
}
