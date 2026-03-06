import Foundation

/// Persists usage snapshots for burn-up chart rendering.
/// Each metric maintains its own history, auto-pruned to the metric's window duration.
final class UsageHistoryStore {

    static let shared = UsageHistoryStore()

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.claudeusagetracker.history", qos: .utility)
    private var cache: [UsageMetric: [UsageSnapshot]] = [:]
    private var loaded = false

    /// Directory where history JSON files are stored
    private let storageDirectory: URL

    // MARK: - Initialization

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storageDirectory = appSupport.appendingPathComponent("Claude Usage").appendingPathComponent("History")
    }

    /// Testable initializer that uses an isolated storage directory
    init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
    }

    // MARK: - Public Methods

    /// Record a new snapshot for a metric
    func record(_ percentage: Double, for metric: UsageMetric, at date: Date = Date()) {
        queue.sync {
            ensureLoaded()
            guard shouldRecord(percentage, for: metric) else { return }
            let snapshot = UsageSnapshot(date: date, percentage: percentage)
            cache[metric, default: []].append(snapshot)
            prune(metric: metric)
        }
        persistAsync(metric: metric)
    }

    /// Record all metrics from a usage update at once
    func recordAll(from usage: ClaudeUsage, at date: Date = Date()) {
        var changed: [UsageMetric] = []

        queue.sync {
            ensureLoaded()

            let metrics: [(UsageMetric, Double)] = [
                (.session, usage.sessionPercentage),
                (.weekly, usage.weeklyPercentage),
                (.opus, usage.opusWeeklyPercentage),
                (.sonnet, usage.sonnetWeeklyPercentage),
            ]

            for (metric, percentage) in metrics {
                guard shouldRecord(percentage, for: metric) else { continue }
                let snapshot = UsageSnapshot(date: date, percentage: percentage)
                cache[metric, default: []].append(snapshot)
                prune(metric: metric)
                changed.append(metric)
            }
        }

        // Persist only changed metrics, off the main thread
        for metric in changed {
            persistAsync(metric: metric)
        }
    }

    /// Get snapshots for a metric, sorted by date ascending
    func snapshots(for metric: UsageMetric) -> [UsageSnapshot] {
        queue.sync {
            ensureLoaded()
            return cache[metric] ?? []
        }
    }

    /// Block until all pending writes complete (for testing)
    func flush() {
        queue.sync {}
    }

    /// Remove all history (for testing or reset)
    func clearAll() {
        queue.sync {
            cache = [:]
            loaded = true
            for metric in UsageMetric.allCases {
                try? fileManager.removeItem(at: fileURL(for: metric))
            }
        }
    }

    // MARK: - Private Methods

    /// Skip recording when the percentage matches the last snapshot
    private func shouldRecord(_ percentage: Double, for metric: UsageMetric) -> Bool {
        guard let last = cache[metric]?.last else { return true }
        return last.percentage != percentage
    }

    private func windowDuration(for metric: UsageMetric) -> TimeInterval {
        switch metric {
        case .session: return Constants.sessionWindow
        case .weekly, .opus, .sonnet: return Constants.weeklyWindow
        }
    }

    private func prune(metric: UsageMetric) {
        let cutoff = Date().addingTimeInterval(-windowDuration(for: metric))
        cache[metric]?.removeAll { $0.date < cutoff }
    }

    private func fileURL(for metric: UsageMetric) -> URL {
        storageDirectory.appendingPathComponent("\(metric.rawValue)_history.json")
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        for metric in UsageMetric.allCases {
            cache[metric] = loadFromDisk(metric: metric)
        }
    }

    private func loadFromDisk(metric: UsageMetric) -> [UsageSnapshot] {
        let url = fileURL(for: metric)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageSnapshot].self, from: data)) ?? []
    }

    /// Persist asynchronously to avoid blocking the main thread on file I/O.
    /// Safe to read `cache` here: this runs on the same serial queue used by
    /// record()/recordAll(), so mutations are always complete before this block executes.
    private func persistAsync(metric: UsageMetric) {
        queue.async { [self] in
            let url = fileURL(for: metric)
            do {
                try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(cache[metric] ?? [])
                try data.write(to: url, options: .atomic)
            } catch {
                LoggingService.shared.logError("UsageHistoryStore: Failed to persist \(metric.rawValue): \(error)")
            }
        }
    }
}
