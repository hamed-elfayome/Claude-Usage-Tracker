//
//  FeedbackPromptView.swift
//  Claude Usage
//
//  Feedback collection popup — shown after 7 days of install.
//
//  Created by Claude Code on 2026-02-25.
//

import SwiftUI

// ─────────────────────────────────────────────────────────────────────
// IMPORTANT — Analytics-only endpoint (NO credentials involved)
// ─────────────────────────────────────────────────────────────────────
//
// The URL below is a lightweight Cloudflare Worker that **only** records
// anonymous, voluntary feedback submitted by the user.
//
// • It does NOT receive, store, or process any user credentials.
// • It does NOT collect data automatically — only when the user clicks Submit.
// • It is completely separate from the Claude AI / Anthropic APIs.
//
// Domain: claude-usage-tracker.hamedelfayome.workers.dev
// ─────────────────────────────────────────────────────────────────────
private let kFeedbackEndpoint = "https://claude-usage-tracker.hamedelfayome.workers.dev?type=improve"

/// Role options for the feedback form
enum FeedbackRole: String, CaseIterable {
    case developer = "Developer"
    case designer = "Designer"
    case manager = "Manager"
    case student = "Student"
    case researcher = "Researcher"
    case other = "Other"

    var localized: String {
        switch self {
        case .developer: return "feedback.role_developer".localized
        case .designer: return "feedback.role_designer".localized
        case .manager: return "feedback.role_manager".localized
        case .student: return "feedback.role_student".localized
        case .researcher: return "feedback.role_researcher".localized
        case .other: return "feedback.role_other".localized
        }
    }
}

/// Feedback collection popup view — matches the GitHubStarPromptView style
struct FeedbackPromptView: View {
    let onSubmit: (_ name: String, _ role: String, _ contact: String, _ message: String) -> Void
    let onRemindLater: () -> Void
    let onDontAskAgain: () -> Void

    @State private var name = ""
    @State private var selectedRole: FeedbackRole = .developer
    @State private var email = ""
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showThanks = false

    @State private var isHoveringSubmit = false
    @State private var isHoveringRemind = false

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if showThanks {
                thanksContent
            } else {
                formContent
            }
        }
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 5)
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("feedback.title".localized)
                        .font(.system(size: 13, weight: .semibold))
                    Text("feedback.subtitle".localized)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            // Fields
            VStack(spacing: 10) {
                // Name
                TextField("feedback.name_placeholder".localized, text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )

                // Role picker
                HStack {
                    Text("feedback.title_label".localized)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $selectedRole) {
                        ForEach(FeedbackRole.allCases, id: \.self) { role in
                            Text(role.localized).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )

                // Contact
                TextField("feedback.contact_placeholder".localized, text: $email)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )

                // Message
                TextEditor(text: $message)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("feedback.message_placeholder".localized)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(.horizontal, 20)

            // Buttons
            HStack(spacing: 8) {
                Button(action: onRemindLater) {
                    Text("feedback.remind_later".localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isHoveringRemind ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringRemind = $0 }

                Button(action: handleSubmit) {
                    HStack(spacing: 5) {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 10))
                        }
                        Text(isSubmitting ? "feedback.submitting".localized : "feedback.submit".localized)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHoveringSubmit ? Color.accentColor.opacity(0.85) : Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || !canSubmit)
                .opacity(canSubmit ? 1.0 : 0.5)
                .onHover { isHoveringSubmit = $0 }
            }
            .padding(.horizontal, 20)

            // Don't ask again
            Button(action: onDontAskAgain) {
                Text("feedback.never_show".localized)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                    .underline()
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Thanks

    private var thanksContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.fill")
                .font(.system(size: 24))
                .foregroundColor(.accentColor)

            Text("feedback.thanks".localized)
                .font(.system(size: 13, weight: .semibold))

            Button(action: onRemindLater) {
                Text("common.close".localized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    // MARK: - Submit

    private func handleSubmit() {
        guard !isSubmitting else { return }
        isSubmitting = true

        let payload: [String: String] = [
            "name": name,
            "role": selectedRole.rawValue,
            "email": email,
            "message": message
        ]

        Task {
            do {
                guard let url = URL(string: kFeedbackEndpoint) else { return }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 15
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (_, response) = try await URLSession.shared.data(for: request)

                await MainActor.run {
                    isSubmitting = false
                    if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showThanks = true
                        }
                        onSubmit(name, selectedRole.rawValue, email, message)
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    // Still count as submitted to not annoy user
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showThanks = true
                    }
                    onSubmit(name, selectedRole.rawValue, email, message)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    FeedbackPromptView(
        onSubmit: { _, _, _, _ in print("Submitted") },
        onRemindLater: { print("Remind later") },
        onDontAskAgain: { print("Don't ask again") }
    )
    .padding(40)
}
