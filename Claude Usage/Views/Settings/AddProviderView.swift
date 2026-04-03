import SwiftUI

struct AddProviderView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedType: ProfileProviderType?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Service")
                .font(.headline)

            Text("Choose what you want to track:")
                .foregroundStyle(.secondary)

            ForEach(ProfileProviderType.allCases, id: \.self) { type in
                Button(action: { selectedType = type }) {
                    HStack(spacing: 12) {
                        Image(systemName: type.iconSystemName)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(type.displayName)
                                .fontWeight(.medium)
                            Text(typeDescription(type))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(selectedType == type ? Color.accentColor.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 400)
        .sheet(item: $selectedType) { type in
            switch type {
            case .claudeMax:
                SetupWizardView()
                    .frame(minWidth: 500, minHeight: 400)
            case .claudeAPI:
                APIBillingView()
                    .frame(minWidth: 500, minHeight: 400)
            case .openaiAPI:
                OpenAICredentialView(providerType: .openaiAPI)
            case .codex:
                OpenAICredentialView(providerType: .codex)
            }
        }
    }

    private func typeDescription(_ type: ProfileProviderType) -> String {
        switch type {
        case .claudeMax: return "Track Claude subscription session and weekly limits"
        case .claudeAPI: return "Track Anthropic API billing and spend"
        case .openaiAPI: return "Track OpenAI API billing and spend (requires Admin key)"
        case .codex: return "Track OpenAI API rate limits via probe requests"
        }
    }
}

extension ProfileProviderType: Identifiable {
    var id: String { rawValue }
}
