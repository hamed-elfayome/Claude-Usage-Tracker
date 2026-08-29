//
//  KeychainService.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-28.
//

import Foundation
import Security

/// Service for secure storage and retrieval of sensitive data using macOS Keychain
class KeychainService {
    static let shared = KeychainService()

    private init() {}

    /// Keychain item identifiers
    enum KeychainKey: String {
        case apiSessionKey = "com.claudeusagetracker.api-session-key"
        case claudeSessionKey = "com.claudeusagetracker.claude-session-key"

        var service: String {
            return rawValue
        }

        var account: String {
            return "session-key"
        }
    }

    // MARK: - Public Methods

    /// Saves a string value to the Keychain
    /// - Parameters:
    ///   - value: The string value to save
    ///   - key: The keychain key identifier
    /// - Throws: KeychainError if save fails
    func save(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // First, try to update existing item
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.service,
            kSecAttrAccount as String: key.account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            LoggingService.shared.log("Keychain: Updated \(key.service)")
            return
        }

        // If update fails because item doesn't exist, add new item
        if updateStatus == errSecItemNotFound {
            // Create access control that doesn't require password
            var accessControlError: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlocked,
                [],
                &accessControlError
            ) else {
                if let error = accessControlError?.takeRetainedValue() {
                    LoggingService.shared.log("Failed to create access control: \(error)")
                }
                throw KeychainError.saveFailed(status: errSecParam)
            }

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: key.service,
                kSecAttrAccount as String: key.account,
                kSecValueData as String: data,
                kSecAttrAccessControl as String: accessControl,
                kSecAttrSynchronizable as String: false
            ]

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            if addStatus == errSecSuccess {
                LoggingService.shared.log("Keychain: Added \(key.service)")
                return
            } else {
                throw KeychainError.saveFailed(status: addStatus)
            }
        } else {
            throw KeychainError.saveFailed(status: updateStatus)
        }
    }

    /// Loads a string value from the Keychain
    /// - Parameter key: The keychain key identifier
    /// - Returns: The stored string value, or nil if not found
    /// - Throws: KeychainError if load fails (other than item not found)
    func load(for key: KeychainKey) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.service,
            kSecAttrAccount as String: key.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            LoggingService.shared.log("Keychain: Loaded \(key.service)")
            return value
        } else if status == errSecItemNotFound {
            LoggingService.shared.log("Keychain: Item not found \(key.service)")
            return nil
        } else {
            throw KeychainError.loadFailed(status: status)
        }
    }

    /// Deletes a value from the Keychain
    /// - Parameter key: The keychain key identifier
    /// - Throws: KeychainError if delete fails (ignores item not found)
    func delete(for key: KeychainKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.service,
            kSecAttrAccount as String: key.account
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess {
            LoggingService.shared.log("Keychain: Deleted \(key.service)")
        } else if status == errSecItemNotFound {
            // Item not found is not an error for delete
            LoggingService.shared.log("Keychain: Item not found for deletion \(key.service)")
        } else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    /// Checks if a value exists in the Keychain
    /// - Parameter key: The keychain key identifier
    /// - Returns: true if the item exists, false otherwise
    func exists(for key: KeychainKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.service,
            kSecAttrAccount as String: key.account,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Per-Profile Credential Storage (#267 / GHSA-mfxh-xpwm-23c7)

    /// Per-profile credential fields stored in the Keychain instead of the
    /// `profiles_v3` UserDefaults plist (which is cleartext on disk).
    enum ProfileSecretField: String, CaseIterable {
        case claudeSessionKey = "claude-session-key"
        case apiSessionKey = "api-session-key"
        case cliCredentialsJSON = "cli-credentials"
        case codexCredentialsJSON = "codex-credentials"
    }

    /// Single service for all per-profile secrets; the account encodes profile + field.
    private static let profileSecretsService = "com.claudeusagetracker.profile-credentials"

    /// In-memory cache: `loadProfiles()` runs on hot paths (every switch/sync/refresh),
    /// so avoid a SecItemCopyMatching round-trip per field per profile per load.
    /// Single-process app; the cache is kept coherent by save/delete below.
    private var profileSecretCache: [String: String] = [:]
    private let cacheLock = NSLock()

    private func profileSecretAccount(_ profileId: UUID, _ field: ProfileSecretField) -> String {
        "\(profileId.uuidString).\(field.rawValue)"
    }

    /// Saves (or deletes, when `value` is nil) a per-profile secret.
    /// Returns true when the Keychain now reflects the requested state.
    @discardableResult
    func saveProfileSecret(_ value: String?, profileId: UUID, field: ProfileSecretField) -> Bool {
        let account = profileSecretAccount(profileId, field)
        guard let value = value else {
            let ok = deleteItem(service: Self.profileSecretsService, account: account)
            if ok {
                cacheLock.lock(); profileSecretCache.removeValue(forKey: account); cacheLock.unlock()
            }
            return ok
        }

        cacheLock.lock()
        let cached = profileSecretCache[account]
        cacheLock.unlock()
        if cached == value { return true }

        do {
            try saveItem(value, service: Self.profileSecretsService, account: account)
            cacheLock.lock(); profileSecretCache[account] = value; cacheLock.unlock()
            return true
        } catch {
            LoggingService.shared.logError("Keychain: failed to save profile secret \(field.rawValue)", error: error)
            return false
        }
    }

    /// Loads a per-profile secret. Returns nil when absent or unreadable.
    func loadProfileSecret(profileId: UUID, field: ProfileSecretField) -> String? {
        let account = profileSecretAccount(profileId, field)
        cacheLock.lock()
        let cached = profileSecretCache[account]
        cacheLock.unlock()
        if let cached = cached { return cached }

        // `try?` flattens the String?? to String? — nil covers both errors and not-found.
        guard let value = try? loadItem(service: Self.profileSecretsService, account: account) else {
            return nil
        }
        cacheLock.lock(); profileSecretCache[account] = value; cacheLock.unlock()
        return value
    }

    /// Reads a profile secret DIRECTLY from the keychain (bypassing the in-memory
    /// cache) and compares it to the expected value. Used to verify a write truly
    /// landed before the caller scrubs the plaintext copy — a phantom write must
    /// never cost the user their credentials.
    func verifyProfileSecret(_ expected: String, profileId: UUID, field: ProfileSecretField) -> Bool {
        let account = profileSecretAccount(profileId, field)
        guard let onDisk = try? loadItem(service: Self.profileSecretsService, account: account) else {
            return false
        }
        return onDisk == expected
    }

    /// Removes all Keychain secrets belonging to a profile (call on profile deletion).
    func deleteAllProfileSecrets(profileId: UUID) {
        for field in ProfileSecretField.allCases {
            _ = saveProfileSecret(nil, profileId: profileId, field: field)
        }
    }

    // MARK: - Generic SecItem Helpers (data-protection keychain, file-based fallback)
    //
    // Per-profile secrets PREFER the DATA-PROTECTION keychain
    // (`kSecUseDataProtectionKeychain`). Unlike the classic file-based login
    // keychain, it has NO ACL password dialogs — access is granted silently by
    // app identity and denied silently otherwise — so users can never see a
    // scary "wants to use your confidential information" prompt. But it
    // requires an application-identifier entitlement that only provisioned
    // builds carry; builds without it (ad-hoc dev builds AND the shipped
    // Developer ID builds — #292) get errSecMissingEntitlement on every call.
    // Those builds fall back to the FILE-BASED login keychain, which needs no
    // entitlement, instead of abandoning the keychain entirely — the old
    // behavior stranded credentials in the cleartext profiles_v3 plist, which
    // is exactly what #267 / GHSA-mfxh-xpwm-23c7 set out to eliminate. Reads
    // check the data-protection store first and fall through to the file-based
    // store, so secrets survive moving between entitled and unentitled builds.
    // The fallback is additionally gated on `fileBasedFallbackAllowed`: only
    // stably-signed builds may touch the login keychain (see that property).

    /// Set to true after any operation returns errSecMissingEntitlement so we
    /// stop retrying the data-protection keychain on every call.
    private var dataProtectionUnavailable = false

    /// The file-based fallback is only safe for builds with a STABLE signing
    /// identity (a Team ID: Developer ID / App Store). Login-keychain item ACLs
    /// match on the app's designated requirement, which survives updates for
    /// stably-signed builds — but ad-hoc dev/test builds get a fresh identity on
    /// every rebuild, so the very next build reading an item the previous one
    /// wrote throws the "wants to use your confidential information" password
    /// dialog. Ad-hoc builds therefore skip the file-based store entirely and
    /// keep the legacy plist fallback (pre-#292 behavior, zero prompts).
    private lazy var fileBasedFallbackAllowed: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code = code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode = staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        guard let teamId = dict[kSecCodeInfoTeamIdentifier as String] as? String, !teamId.isEmpty else {
            LoggingService.shared.log("Keychain: ad-hoc signing identity — file-based login keychain fallback disabled to avoid ACL password prompts")
            return false
        }
        return true
    }()

    /// Whether per-profile secret storage is usable in this build.
    /// Probes with a throwaway item; with the file-based fallback this only
    /// fails when BOTH keychains reject us.
    var isProfileSecretStorageAvailable: Bool {
        let probeAccount = "availability-probe"
        do {
            try saveItem("probe", service: Self.profileSecretsService, account: probeAccount)
            _ = deleteItem(service: Self.profileSecretsService, account: probeAccount)
            return true
        } catch {
            return false
        }
    }

    private func noteStatus(_ status: OSStatus) {
        if status == errSecMissingEntitlement {
            if !dataProtectionUnavailable {
                LoggingService.shared.log("Keychain: data-protection keychain unavailable (no application-identifier entitlement) — using file-based login keychain")
            }
            dataProtectionUnavailable = true
        }
    }

    private func saveItem(_ value: String, service: String, account: String) throws {
        if !dataProtectionUnavailable {
            do {
                try saveItem(value, service: service, account: account, dataProtection: true)
                return
            } catch KeychainError.saveFailed(let status)
                where status == errSecMissingEntitlement && fileBasedFallbackAllowed {
                // noteStatus flagged the store; retry below file-based so the
                // FIRST save already lands in a keychain, not the plist.
            }
        }
        guard fileBasedFallbackAllowed else {
            throw KeychainError.saveFailed(status: errSecMissingEntitlement)
        }
        try saveItem(value, service: service, account: account, dataProtection: false)
    }

    private func saveItem(_ value: String, service: String, account: String, dataProtection: Bool) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        var updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if dataProtection { updateQuery[kSecUseDataProtectionKeychain as String] = true }
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        noteStatus(updateStatus)

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.saveFailed(status: updateStatus)
        }

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: false
        ]
        if dataProtection {
            // AfterFirstUnlock: the app is a login-item menu bar app and must be
            // able to read credentials when launched right at login. (Accessibility
            // classes only apply to the data-protection keychain.)
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            addQuery[kSecUseDataProtectionKeychain as String] = true
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            noteStatus(addStatus)
            throw KeychainError.saveFailed(status: addStatus)
        }
    }

    private func loadItem(service: String, account: String) throws -> String? {
        if !dataProtectionUnavailable {
            do {
                if let value = try loadItem(service: service, account: account, dataProtection: true) {
                    return value
                }
            } catch KeychainError.loadFailed(let status) where status == errSecMissingEntitlement {
                // noteStatus flagged the store; fall through to file-based.
            }
            // Fall through on not-found too: secrets written by an unentitled
            // build must stay readable if this build gained the entitlement.
        }
        guard fileBasedFallbackAllowed else { return nil }
        return try loadItem(service: service, account: account, dataProtection: false)
    }

    private func loadItem(service: String, account: String, dataProtection: Bool) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return value
        }
        if status == errSecItemNotFound { return nil }
        noteStatus(status)
        throw KeychainError.loadFailed(status: status)
    }

    /// Returns true when the item is gone (deleted or was never there) from
    /// every store this build can reach.
    private func deleteItem(service: String, account: String) -> Bool {
        var goneFromDataProtection = true
        if !dataProtectionUnavailable {
            goneFromDataProtection = deleteItem(service: service, account: account, dataProtection: true)
        }
        guard fileBasedFallbackAllowed else {
            // No file-based store in play; without a reachable store there is
            // nothing this build could be holding (pre-fallback behavior).
            return dataProtectionUnavailable ? false : goneFromDataProtection
        }
        let goneFromFileBased = deleteItem(service: service, account: account, dataProtection: false)
        return goneFromDataProtection && goneFromFileBased
    }

    private func deleteItem(service: String, account: String, dataProtection: Bool) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return true }
        noteStatus(status)
        // An unreachable store cannot be holding the item.
        if status == errSecMissingEntitlement { return true }
        LoggingService.shared.logError("Keychain: failed to delete item (status: \(status))",
                                       error: KeychainError.deleteFailed(status: status))
        return false
    }
}

// MARK: - KeychainError

enum KeychainError: Error, LocalizedError {
    case invalidData
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid data format for Keychain storage"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        }
    }
}
