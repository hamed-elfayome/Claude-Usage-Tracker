import Darwin
import Foundation

/// Lightweight usage snapshot shared with the WidgetKit extension.
///
/// The main app writes this file after every successful usage refresh and the
/// widget extension reads it from its sandbox (granted read-only access to the
/// snapshot directory). No App Groups are used — see the contribution
/// guidelines: App Group entitlements trigger Keychain prompts for Developer
/// ID distribution, so data is shared through a plain JSON file instead,
/// following the same pattern as the statusline usage cache.
struct WidgetSnapshot: Codable {
    struct ProfileEntry: Codable, Identifiable {
        let id: UUID
        let name: String
        let isActive: Bool
        let sessionPercentage: Double
        let sessionResetTime: Date
        let weeklyPercentage: Double
        let weeklyResetTime: Date
        let lastUpdated: Date
    }

    /// Bump when the on-disk format changes so an old widget build can
    /// detect a snapshot written by a newer app (and vice versa).
    var schemaVersion: Int = 1
    let generatedAt: Date
    let profiles: [ProfileEntry]

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
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL = snapshotURL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
