import Foundation

/// A single point-in-time usage measurement for burn-up chart rendering
struct UsageSnapshot: Codable, Equatable, Identifiable {
    let date: Date
    let percentage: Double

    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}

/// Identifies which usage metric a snapshot belongs to
enum UsageMetric: String, Codable, CaseIterable {
    case session
    case weekly
    case opus
    case sonnet
}
