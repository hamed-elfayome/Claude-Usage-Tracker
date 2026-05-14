//
//  ClaudeAPIService+WebHeaders.swift
//  Claude Usage
//
//  Adds stable anthropic-* web client headers to every .claudeAISession request.
//  DO NOT apply to .cliOAuth or .consoleAPISession paths.
//

import Foundation

extension ClaudeAPIService {

    // MARK: — Stable identifier helpers

    /// Returns the persisted anonymous ID (format: "claudeai.v1.<uuid>"),
    /// creating and saving one to Keychain if it does not already exist.
    func getOrCreateAnonymousId() -> String {
        if let existing = try? KeychainService.shared.load(for: .anthropicAnonymousId),
           !existing.isEmpty {
            return existing
        }
        let newId = "claudeai.v1.\(UUID().uuidString.lowercased())"
        try? KeychainService.shared.save(newId, for: .anthropicAnonymousId)
        return newId
    }

    /// Returns the persisted device ID (bare lowercase UUID),
    /// creating and saving one to Keychain if it does not already exist.
    func getOrCreateDeviceId() -> String {
        if let existing = try? KeychainService.shared.load(for: .anthropicDeviceId),
           !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString.lowercased()
        try? KeychainService.shared.save(newId, for: .anthropicDeviceId)
        return newId
    }

    // MARK: — Header injection

    /// Applies all five Anthropic web-client headers to `request`.
    /// Call this only for requests made under `.claudeAISession` authentication.
    func applyAnthropicWebHeaders(to request: inout URLRequest) {
        request.setValue(getOrCreateAnonymousId(),
                         forHTTPHeaderField: "anthropic-anonymous-id")
        request.setValue(getOrCreateDeviceId(),
                         forHTTPHeaderField: "anthropic-device-id")
        request.setValue("web_claude_ai",
                         forHTTPHeaderField: "anthropic-client-platform")
        request.setValue("1.0.0",
                         forHTTPHeaderField: "anthropic-client-version")
        request.setValue("94c2428a9a33a4d3867c4bc900e2ec8fec3c6dcb",
                         forHTTPHeaderField: "anthropic-client-sha")
    }
}
