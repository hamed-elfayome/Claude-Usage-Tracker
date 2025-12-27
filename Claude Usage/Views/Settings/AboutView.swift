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
            VStack(spacing: Spacing.sectionSpacing) {
                // Header with App Info
                VStack(spacing: Spacing.md) {
                    Image("AboutLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)

                    VStack(spacing: Spacing.xs) {
                        Text("app.name".localized)
                            .font(Typography.title)

                        Text("about.version".localized(with: appVersion))
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.lg)

                Divider()

                // Creator
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("about.created_by".localized)
                        .font(Typography.sectionHeader)

                    Button(action: {
                        if let url = URL(string: "https://github.com/hamed-elfayome") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hamed Elfayome")
                                    .font(Typography.body)
                                    .foregroundColor(.primary)

                                Text("@hamed-elfayome")
                                    .font(Typography.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Contributors
                if !contributors.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("about.contributors".localized(with: contributors.count))
                            .font(Typography.sectionHeader)

                        ContributorsGridView(contributors: contributors)
                    }
                } else if isLoadingContributors {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("about.contributors_loading".localized)
                            .font(Typography.sectionHeader)

                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, Spacing.md)
                    }
                }

                // Links
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("about.links".localized)
                        .font(Typography.sectionHeader)

                    VStack(spacing: Spacing.sm) {
                        LinkButton(title: "about.star_github".localized, icon: "star.fill") {
                            if let url = URL(string: "https://github.com/hamed-elfayome/Claude-Usage-Tracker") {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        LinkButton(title: "about.report_issue".localized, icon: "exclamationmark.triangle") {
                            if let url = URL(string: "https://github.com/hamed-elfayome/Claude-Usage-Tracker/issues") {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        LinkButton(title: "about.send_feedback".localized, icon: "envelope") {
                            if let url = URL(string: "mailto:hamedelfayome@gmail.com") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                // Footer
                VStack(spacing: Spacing.xs) {
                    Text("about.mit_license".localized)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)

                    Text("about.copyright".localized)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)

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

// MARK: - Link Button

struct LinkButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.iconTextSpacing) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16)

                Text(title)
                    .font(Typography.label)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Contributors Grid View

struct ContributorsGridView: View {
    let contributors: [Contributor]

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 40, maximum: 44), spacing: Spacing.sm)
        ], spacing: Spacing.sm) {
            ForEach(contributors) { contributor in
                ContributorAvatar(contributor: contributor)
            }
        }
    }
}

struct ContributorAvatar: View {
    let contributor: Contributor
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
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Group {
                                if isLoadingImage {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary.opacity(0.3))
                                }
                            }
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .help(contributor.login)
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

// MARK: - Previews

#Preview {
    AboutView()
        .frame(width: 520, height: 600)
}
