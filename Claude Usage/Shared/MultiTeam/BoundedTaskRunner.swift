import Foundation

private enum RunnerEvent<Result: Sendable>: Sendable { case done(Int, Result), timedOut }

/// Runs async work with a global and a per-key concurrency limit.
enum BoundedTaskRunner {
    /// Returns every item in input order; the result is nil when the overall `timeout`
    /// elapsed (or the calling task was cancelled) before that item finished.
    static func run<Item: Sendable, Result: Sendable>(
        _ items: [Item], key: (Item) -> UUID, maxConcurrent: Int, maxPerKey: Int,
        timeout: TimeInterval? = nil, body: @escaping @Sendable (Item) async -> Result
    ) async -> [(Item, Result?)] {
        var results = [Result?](repeating: nil, count: items.count)
        guard !items.isEmpty else { return [] }
        let keys = items.map(key)
        let globalLimit = max(1, maxConcurrent)
        let keyLimit = max(1, maxPerKey)

        await withTaskGroup(of: RunnerEvent<Result>.self) { group in
            var pending = Array(items.indices)
            var running = 0
            var perKey: [UUID: Int] = [:]
            var timerRunning = false
            var expired = false

            if let timeout {
                timerRunning = true
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                    return .timedOut
                }
            }

            func launch() {
                var i = 0
                while i < pending.count, running < globalLimit {
                    let idx = pending[i]
                    if perKey[keys[idx], default: 0] < keyLimit {
                        pending.remove(at: i)
                        running += 1
                        perKey[keys[idx], default: 0] += 1
                        let item = items[idx]
                        group.addTask { .done(idx, await body(item)) }
                    } else {
                        i += 1
                    }
                }
            }

            launch()
            while running > 0 {
                guard let event = await group.next() else { break }
                switch event {
                case .done(let idx, let value):
                    if !expired { results[idx] = value }
                    running -= 1
                    perKey[keys[idx], default: 1] -= 1
                    if Task.isCancelled {
                        group.cancelAll()
                        pending.removeAll()
                    } else {
                        launch()
                    }
                case .timedOut:
                    timerRunning = false
                    expired = true
                    pending.removeAll()
                    group.cancelAll()
                }
            }
            if timerRunning { group.cancelAll() }
        }
        return zip(items, results).map { ($0, $1) }
    }
}
