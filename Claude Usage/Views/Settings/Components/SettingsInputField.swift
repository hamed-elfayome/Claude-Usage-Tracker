//
//  SettingsInputField.swift
//  Claude Usage - Input Field Component
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Unified input field component for settings
/// Supports text, secure, and monospace variants
struct SettingsInputField: View {
    let label: String?
    let placeholder: String
    let helpText: String?
    let isSecure: Bool
    let isMonospaced: Bool
    @Binding var text: String
    @FocusState private var isFocused: Bool

    init(
        label: String? = nil,
        placeholder: String,
        helpText: String? = nil,
        isSecure: Bool = false,
        isMonospaced: Bool = false,
        text: Binding<String>
    ) {
        self.label = label
        self.placeholder = placeholder
        self.helpText = helpText
        self.isSecure = isSecure
        self.isMonospaced = isMonospaced
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Label
            if let label = label {
                Text(label)
                    .font(Typography.label)
                    .foregroundColor(.secondary)
            }

            // Input field
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(SettingsTextFieldStyle(isMonospaced: isMonospaced, isFocused: isFocused))
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(SettingsTextFieldStyle(isMonospaced: isMonospaced, isFocused: isFocused))
                        .focused($isFocused)
                }
            }
            .accessibilityLabel(label ?? placeholder)

            // Help text
            if let helpText = helpText {
                Text(helpText)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Custom Text Field Style

struct SettingsTextFieldStyle: TextFieldStyle {
    let isMonospaced: Bool
    let isFocused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(isMonospaced ? Typography.monospacedInput : Typography.body)
            .padding(Spacing.inputPadding)
            .background(
                RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                    .fill(SettingsColors.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                    .strokeBorder(
                        isFocused ? SettingsColors.primary : SettingsColors.border,
                        lineWidth: isFocused ? 2 : 0.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Convenience Initializers

extension SettingsInputField {
    /// Create a monospaced input field (for API keys, etc.)
    static func monospaced(
        label: String? = nil,
        placeholder: String,
        helpText: String? = nil,
        text: Binding<String>
    ) -> SettingsInputField {
        SettingsInputField(
            label: label,
            placeholder: placeholder,
            helpText: helpText,
            isSecure: false,
            isMonospaced: true,
            text: text
        )
    }

    /// Create a secure input field (for passwords, keys)
    static func secure(
        label: String? = nil,
        placeholder: String,
        helpText: String? = nil,
        text: Binding<String>
    ) -> SettingsInputField {
        SettingsInputField(
            label: label,
            placeholder: placeholder,
            helpText: helpText,
            isSecure: true,
            isMonospaced: false,
            text: text
        )
    }

    /// Create a secure monospaced input field
    static func secureMonospaced(
        label: String? = nil,
        placeholder: String,
        helpText: String? = nil,
        text: Binding<String>
    ) -> SettingsInputField {
        SettingsInputField(
            label: label,
            placeholder: placeholder,
            helpText: helpText,
            isSecure: true,
            isMonospaced: true,
            text: text
        )
    }
}

// MARK: - Previews

#Preview("Basic Input") {
    SettingsInputField(
        placeholder: "Enter your name",
        text: .constant("")
    )
    .padding()
}

#Preview("Input with Label") {
    SettingsInputField(
        label: "Username",
        placeholder: "Enter username",
        text: .constant("hamed")
    )
    .padding()
}

#Preview("Input with Help Text") {
    SettingsInputField(
        label: "Email",
        placeholder: "you@example.com",
        helpText: "We'll never share your email with anyone",
        text: .constant("")
    )
    .padding()
}

#Preview("Monospaced Input (API Key)") {
    SettingsInputField.monospaced(
        label: "Session Key",
        placeholder: "sk-ant-api03-...",
        helpText: "Your session key from claude.ai",
        text: .constant("sk-ant-api03-AbCdEf1234567890")
    )
    .padding()
}

#Preview("Secure Input") {
    SettingsInputField.secure(
        label: "Password",
        placeholder: "Enter password",
        text: .constant("password123")
    )
    .padding()
}

#Preview("Secure Monospaced (API Key)") {
    SettingsInputField.secureMonospaced(
        label: "API Key",
        placeholder: "sk-ant-api03-...",
        helpText: "Keep this key secure and never share it",
        text: .constant("sk-ant-api03-secret")
    )
    .padding()
}

#Preview("Form Example") {
    VStack(spacing: Spacing.formRowSpacing) {
        SettingsInputField(
            label: "Name",
            placeholder: "Enter your name",
            text: .constant("Claude")
        )

        SettingsInputField(
            label: "Email",
            placeholder: "you@example.com",
            text: .constant("")
        )

        SettingsInputField.monospaced(
            label: "Session Key",
            placeholder: "sk-ant-api03-...",
            helpText: "Get this from your Claude.ai settings",
            text: .constant("")
        )
    }
    .padding()
}
