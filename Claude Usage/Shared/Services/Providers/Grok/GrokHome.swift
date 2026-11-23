import Foundation

/// A Grok account is identified by its CLI data directory, not by the active tracker profile.
/// The directory need not exist yet: `grok login` can create it after profile creation.
enum GrokHome {
    static func resolve(_ path: String?) -> URL? {
        var path = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if path.isEmpty {
            path = ProcessInfo.processInfo.environment["GROK_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "~/.grok"
        }
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), path.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        let candidate = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        // realpath needs an existing directory. Resolve the existing prefix, then
        // append the not-yet-created suffix (which may be below a symlink).
        var parent = candidate
        var suffix: [String] = []
        var directory: ObjCBool = false
        while !FileManager.default.fileExists(atPath: parent.path, isDirectory: &directory) {
            guard parent.path != "/", (try? FileManager.default.destinationOfSymbolicLink(atPath: parent.path)) == nil else { return nil }
            suffix.append(parent.lastPathComponent)
            parent.deleteLastPathComponent()
        }
        guard directory.boolValue else { return nil }
        var home = parent.resolvingSymlinksInPath()
        for component in suffix.reversed() { home.appendPathComponent(component, isDirectory: true) }
        return home
    }

    static func sameDirectory(_ lhs: URL, _ rhs: URL) -> Bool {
        if lhs.path == rhs.path { return true }
        guard lhs.path.caseInsensitiveCompare(rhs.path) == .orderedSame else { return false }
        var parent = lhs
        while !FileManager.default.fileExists(atPath: parent.path), parent.path != "/" { parent.deleteLastPathComponent() }
        return (try? parent.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames) != true
    }

    static func available(for id: UUID?, path: String?, in profiles: [Profile]) -> URL? {
        guard let home = resolve(path) else { return nil }
        for other in profiles where other.provider == .grok && other.id != id {
            if let claimed = resolve(other.grokHomePath), sameDirectory(claimed, home) { return nil }
        }
        return home
    }

    static func suggestedPath(in profiles: [Profile], excluding id: UUID? = nil) -> String {
        if available(for: id, path: nil, in: profiles) != nil { return "" }
        var number = 2
        while true {
            let path = "~/.grok-\(number)"
            if available(for: id, path: path, in: profiles) != nil { return path }
            number += 1
        }
    }
}
