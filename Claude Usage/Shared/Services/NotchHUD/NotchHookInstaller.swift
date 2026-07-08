//
//  NotchHookInstaller.swift
//  Claude Usage
//
//  Installs/removes the notch HUD's Claude Code hooks in ~/.claude/settings.json.
//  Follows the app's read-merge-write-one-key discipline (see StatuslineService):
//  only hook entries whose URL points at our listener are ever touched — all
//  user/foreign hooks and settings are preserved verbatim.
//

import Foundation

final class NotchHookInstaller {
    static let shared = NotchHookInstaller()

    /// The 8 passive hook events the HUD observes. Deliberately excludes
    /// PermissionRequest/SubagentStart (the abandoned branch's invasive hooks).
    static let events: [(event: String, suffix: String)] = [
        ("SessionStart", "session-start"),
        ("SessionEnd", "session-end"),
        ("UserPromptSubmit", "user-prompt-submit"),
        ("PreToolUse", "pre-tool-use"),
        ("PostToolUse", "post-tool-use"),
        ("PostToolUseFailure", "post-tool-use-failure"),
        ("Stop", "stop"),
        ("Notification", "notification"),
    ]

    private let settingsURL: URL
    private let pathToken: () -> String

    /// Injectable for tests.
    init(settingsURL: URL = Constants.ClaudePaths.claudeDirectory.appendingPathComponent("settings.json"),
         pathToken: @escaping () -> String = { SharedDataStore.shared.notchHUDPathToken() }) {
        self.settingsURL = settingsURL
        self.pathToken = pathToken
    }

    private func hookURL(for suffix: String) -> String {
        "\(Constants.NotchHUD.baseURL)/hook/\(pathToken())/\(suffix)"
    }

    private var currentURLs: Set<String> {
        Set(Self.events.map { hookURL(for: $0.suffix) })
    }

    // MARK: - Status

    enum InstallStatus: Equatable {
        case installed
        case partial
        case notInstalled
        /// Hooks pointing at our listener exist that don't match the current
        /// 8-event configuration (e.g. the abandoned branch's 10-hook set).
        case legacyDetected
        case error(String)
    }

    func checkStatus() -> InstallStatus {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return .notInstalled
        }
        do {
            let data = try Data(contentsOf: settingsURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hooks = json["hooks"] as? [String: Any] else {
                return .notInstalled
            }

            let expected = currentURLs
            var installedCount = 0
            var hasLegacy = false

            for (_, value) in hooks {
                guard let matcherGroups = value as? [[String: Any]] else { continue }
                for group in matcherGroups {
                    guard let hookList = group["hooks"] as? [[String: Any]] else { continue }
                    for hook in hookList {
                        guard let url = hook["url"] as? String,
                              url.hasPrefix(Constants.NotchHUD.baseURL) else { continue }
                        if expected.contains(url) {
                            installedCount += 1
                        } else {
                            hasLegacy = true
                        }
                    }
                }
            }

            if installedCount == Self.events.count { return hasLegacy ? .legacyDetected : .installed }
            if hasLegacy { return .legacyDetected }
            if installedCount > 0 { return .partial }
            return .notInstalled
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Install / Uninstall

    /// Installs the 8 passive hooks, first stripping ANY hook pointing at our
    /// listener from EVERY event key — this removes legacy entries (including
    /// the abandoned branch's blocking PermissionRequest hook) in the same pass.
    @discardableResult
    func install() -> Result<Void, Error> {
        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            var settings: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                let data = try Data(contentsOf: settingsURL)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    settings = json
                }
            }

            var hooks = stripOurHooks(from: settings["hooks"] as? [String: Any] ?? [:])

            for (event, suffix) in Self.events {
                let entry: [String: Any] = [
                    "matcher": "",
                    "hooks": [["type": "http", "url": hookURL(for: suffix), "timeout": 3]],
                ]
                var matcherGroups = hooks[event] as? [[String: Any]] ?? []
                matcherGroups.append(entry)
                hooks[event] = matcherGroups
            }

            settings["hooks"] = hooks
            let output = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: settingsURL, options: .atomic)
            LoggingService.shared.log("NotchHookInstaller: installed \(Self.events.count) hooks")
            return .success(())
        } catch {
            LoggingService.shared.logError("NotchHookInstaller: install failed", error: error)
            return .failure(error)
        }
    }

    /// Removes every hook pointing at our listener (any event key, any vintage),
    /// preserving all foreign hooks and settings.
    @discardableResult
    func uninstall() -> Result<Void, Error> {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return .success(())
        }
        do {
            let data = try Data(contentsOf: settingsURL)
            guard var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let existingHooks = settings["hooks"] as? [String: Any] else {
                return .success(())
            }

            let hooks = stripOurHooks(from: existingHooks)
            if hooks.isEmpty {
                settings.removeValue(forKey: "hooks")
            } else {
                settings["hooks"] = hooks
            }

            let output = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: settingsURL, options: .atomic)
            LoggingService.shared.log("NotchHookInstaller: hooks removed")
            return .success(())
        } catch {
            LoggingService.shared.logError("NotchHookInstaller: uninstall failed", error: error)
            return .failure(error)
        }
    }

    /// Removes any hook whose URL points at our listener from every event key.
    /// Matcher groups that end up empty are dropped; foreign hooks are kept.
    private func stripOurHooks(from hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for key in Array(result.keys) {
            guard var matcherGroups = result[key] as? [[String: Any]] else { continue }
            matcherGroups = matcherGroups.compactMap { group in
                guard var hookList = group["hooks"] as? [[String: Any]] else { return group }
                hookList.removeAll { hook in
                    (hook["url"] as? String)?.hasPrefix(Constants.NotchHUD.baseURL) == true
                }
                if hookList.isEmpty { return nil }
                var updated = group
                updated["hooks"] = hookList
                return updated
            }
            if matcherGroups.isEmpty {
                result.removeValue(forKey: key)
            } else {
                result[key] = matcherGroups
            }
        }
        return result
    }
}
