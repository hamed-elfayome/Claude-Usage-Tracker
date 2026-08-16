import Darwin
import Foundation

private enum WidgetSnapshotError: Error {
    case invalidSnapshot
    case snapshotTooLarge
}

/// Lightweight usage snapshot shared with the WidgetKit extension.
///
/// The main app writes this file after every successful usage refresh and the
/// widget extension reads it from its sandbox (granted read-only access to the
/// snapshot file). No App Groups are used — see the contribution
/// guidelines: App Group entitlements trigger Keychain prompts for Developer
/// ID distribution, so data is shared through a plain JSON file instead,
/// following the same pattern as the statusline usage cache.
struct WidgetSnapshot: Codable {
    struct ProfileEntry: Codable, Identifiable {
        enum Provider: String, Codable {
            case claude
            case codex
            case zai
        }

        let id: UUID
        let name: String
        let provider: Provider
        let isActive: Bool
        /// Whether the profile is selected for menu bar display. The active
        /// profile is always included in the snapshot even when deselected
        /// (the small widget needs it); the overview widget shows only
        /// displayed profiles.
        let isDisplayed: Bool
        let sessionPercentage: Double
        let sessionResetTime: Date?
        let weeklyPercentage: Double?
        let weeklyResetTime: Date?
        /// When this profile's usage was last fetched. Can lag behind
        /// `generatedAt`: the single-profile refresh path only updates the
        /// active profile, so per-profile staleness must use this value.
        let lastUpdated: Date

        func isStale(at date: Date, interval: TimeInterval) -> Bool {
            date.timeIntervalSince(lastUpdated) >= interval
        }

        init(
            id: UUID,
            name: String,
            provider: Provider = .claude,
            isActive: Bool,
            isDisplayed: Bool,
            sessionPercentage: Double,
            sessionResetTime: Date?,
            weeklyPercentage: Double?,
            weeklyResetTime: Date?,
            lastUpdated: Date
        ) {
            self.id = id
            self.name = name
            self.provider = provider
            self.isActive = isActive
            self.isDisplayed = isDisplayed
            self.sessionPercentage = sessionPercentage
            self.sessionResetTime = sessionResetTime
            self.weeklyPercentage = weeklyPercentage
            self.weeklyResetTime = weeklyResetTime
            self.lastUpdated = lastUpdated
        }
    }

    /// Bump when the on-disk format changes so an old widget build can
    /// detect a snapshot written by a newer app (and vice versa).
    /// `load` rejects snapshots whose version doesn't match.
    static let currentSchemaVersion = 3
    static let maximumFileSize = 128 * 1024
    static let maximumProfileCount = 64
    static let maximumProfileNameLength = 64

    var schemaVersion: Int = WidgetSnapshot.currentSchemaVersion
    let generatedAt: Date
    let profiles: [ProfileEntry]

    func isStale(at date: Date, interval: TimeInterval) -> Bool {
        date.timeIntervalSince(generatedAt) >= interval
    }

    // MARK: - Location

    /// Directory holding the snapshot:
    /// `~/Library/Application Support/Claude Usage/widget/`
    ///
    /// Resolved against the *real* user home (via `getpwuid`) rather than
    /// `NSHomeDirectory()`, because inside the sandboxed widget extension the
    /// latter points at the container, not the path covered by the read-only
    /// exception entitlement.
    static var snapshotDirectory: URL {
        let home: String
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = String(cString: dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Claude Usage/widget", isDirectory: true)
    }

    static var snapshotURL: URL {
        snapshotDirectory.appendingPathComponent("snapshot.json")
    }

    // MARK: - Coding

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func write(to url: URL = Self.snapshotURL) throws {
        guard isValid else {
            throw WidgetSnapshotError.invalidSnapshot
        }
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        // The snapshot intentionally lives outside a sandbox container so the
        // widget can read it. Keep it private to the current macOS account.
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let data = try Self.encoder.encode(self)
        guard data.count <= Self.maximumFileSize else {
            throw WidgetSnapshotError.snapshotTooLarge
        }
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    static func load(from url: URL = snapshotURL) -> WidgetSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // Treat this cross-sandbox file as untrusted input. A bounded read
        // prevents a replaced or corrupted snapshot from exhausting the
        // widget process before decoding can fail safely.
        guard let data = try? handle.read(upToCount: maximumFileSize + 1),
              data.count <= maximumFileSize,
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion == currentSchemaVersion,
              snapshot.isValid else { return nil }
        return snapshot
    }

    private var isValid: Bool {
        guard profiles.count <= Self.maximumProfileCount,
              generatedAt.timeIntervalSinceReferenceDate.isFinite else {
            return false
        }

        var profileIDs = Set<UUID>()
        return profiles.allSatisfy { profile in
            guard profileIDs.insert(profile.id).inserted,
                  profile.name.count <= Self.maximumProfileNameLength,
                  profile.sessionPercentage.isFinite,
                  (0...10_000).contains(profile.sessionPercentage),
                  profile.lastUpdated.timeIntervalSinceReferenceDate.isFinite else {
                return false
            }

            if let percentage = profile.weeklyPercentage,
               !percentage.isFinite || !(0...10_000).contains(percentage) {
                return false
            }
            return [profile.sessionResetTime, profile.weeklyResetTime]
                .compactMap { $0 }
                .allSatisfy { $0.timeIntervalSinceReferenceDate.isFinite }
        }
    }
}
