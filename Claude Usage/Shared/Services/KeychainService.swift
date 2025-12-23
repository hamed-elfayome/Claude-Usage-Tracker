//
//  KeychainService.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-22.
//

import Foundation
import Security

/// Errors that can occur during Keychain operations
enum KeychainError: LocalizedError {
    case unableToSave(OSStatus)
    case unableToLoad(OSStatus)
    case unableToDelete(OSStatus)
    case dataConversionError

    var errorDescription: String? {
        switch self {
        case .unableToSave(let status):
            return "Unable to save to Keychain: \(status)"
        case .unableToLoad(let status):
            return "Unable to load from Keychain: \(status)"
        case .unableToDelete(let status):
            return "Unable to delete from Keychain: \(status)"
        case .dataConversionError:
            return "Data conversion error"
        }
    }
}

/// Service for securely storing and retrieving sensitive data using macOS Keychain
final class KeychainService {
    static let shared = KeychainService()

    private let service = Bundle.main.bundleIdentifier ?? "com.claudeusagetracker"

    private init() {}

    /// Saves a string value to the Keychain
    /// - Parameters:
    ///   - key: The key to store the value under
    ///   - value: The string value to store
    /// - Throws: KeychainError if the operation fails
    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionError
        }

        // Delete existing item first to avoid duplicates
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave(status)
        }
    }

    /// Loads a string value from the Keychain
    /// - Parameter key: The key to retrieve
    /// - Returns: The stored string value, or nil if not found
    func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    /// Deletes a value from the Keychain
    /// - Parameter key: The key to delete
    /// - Throws: KeychainError if the operation fails (except for item not found)
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status)
        }
    }
}
