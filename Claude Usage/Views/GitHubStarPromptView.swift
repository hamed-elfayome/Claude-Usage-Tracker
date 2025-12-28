import SwiftUI

/// A minimal, professional prompt asking users to star the GitHub repository
struct GitHubStarPromptView: View {
    let onStar: () -> Void
    let onMaybeLater: () -> Void
    let onDontAskAgain: () -> Void

    @State private var isHoveringStarButton = false
    @State private var isHoveringLaterButton = false
    @State private var isHoveringDontAskButton = false

    var body: some View {
        VStack(spacing: 16) {
            // Header with icon and message
            HStack(spacing: 12) {
                Image("HeaderLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text("github.enjoy_app".localized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("github.star_description".localized)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Action buttons
            HStack(spacing: 8) {
                // Maybe Later button
                Button(action: onMaybeLater) {
                    Text("github.maybe_later".localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isHoveringLaterButton ? Color.secondary.opacity(0.12) : Color.secondary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringLaterButton = hovering
                }

                // Star on GitHub button (primary)
                Button(action: onStar) {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .medium))

                        Text("github.star_button".localized)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHoveringStarButton ? Color.accentColor.opacity(0.85) : Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringStarButton = hovering
                }
            }
            .padding(.horizontal, 16)

            // Don't Ask Again link
            Button(action: onDontAskAgain) {
                Text("github.never_show".localized)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.7))
                    .underline()
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .frame(width: 300)
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
}

// MARK: - Preview

#Preview {
    GitHubStarPromptView(
        onStar: { print("Star clicked") },
        onMaybeLater: { print("Maybe Later clicked") },
        onDontAskAgain: { print("Don't Ask Again clicked") }
    )
    .padding(40)
}
