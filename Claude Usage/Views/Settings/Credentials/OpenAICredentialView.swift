import SwiftUI

struct OpenAICredentialView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var profileManager = ProfileManager.shared

    let providerType: ProfileProviderType
    @State private var name: String = ""
    @State private var apiKey: String = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var validationSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(providerType == .openaiAPI ? "Add OpenAI API" : "Add Codex")
                .font(.headline)

            TextField("Display Name", text: $name)
                .textFieldStyle(.roundedBorder)

            SecureField(
                providerType == .openaiAPI ? "Admin API Key (sk-admin-...)" : "API Key (sk-...)",
                text: $apiKey
            )
            .textFieldStyle(.roundedBorder)

            if providerType == .openaiAPI {
                Text("Requires an Admin API key from platform.openai.com/settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tracks API rate limits via probe requests. This is NOT your Codex subscription quota.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if validationSuccess {
                Text("Connected successfully!")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Validate & Save") {
                    Task { await validateAndSave() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.isEmpty || name.isEmpty || isValidating)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            name = providerType == .openaiAPI ? "OpenAI API" : "Codex"
        }
    }

    private func validateAndSave() async {
        isValidating = true
        validationError = nil
        validationSuccess = false

        let profile: Profile
        if providerType == .openaiAPI {
            profile = Profile(name: name, providerType: .openaiAPI, openaiAdminKey: apiKey)
        } else {
            profile = Profile(name: name, providerType: .codex, openaiApiKey: apiKey)
        }

        let provider = UsageProviderFactory.makeProvider(for: profile)
        do {
            let isValid = try await provider.validateCredentials(for: profile)
            if isValid {
                if providerType == .openaiAPI {
                    _ = profileManager.createOpenAIAPIProfile(name: name, adminKey: apiKey)
                } else {
                    _ = profileManager.createCodexProfile(name: name, apiKey: apiKey)
                }
                validationSuccess = true
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            } else {
                validationError = "Credentials are invalid. Check your API key."
            }
        } catch {
            validationError = error.localizedDescription
        }
        isValidating = false
    }
}
