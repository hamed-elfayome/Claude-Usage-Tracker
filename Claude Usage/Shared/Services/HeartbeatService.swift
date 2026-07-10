import Foundation

/// Sends an anonymous heartbeat ping every 24 hours to track active app usage.
///
/// Endpoint: claude-usage-tracker.hamedelfayome.workers.dev?type=heartbeat
/// This is the same Cloudflare Worker used by FeedbackPromptView (?type=improve)
/// and MobileAppView (?type=mobile). No PII, no credentials — just the app version.
final class HeartbeatService {
    static let shared = HeartbeatService()

    private let endpoint = "https://claude-usage-tracker.hamedelfayome.workers.dev?type=heartbeat"
    private let lastPingKey = "heartbeat.lastPingDate"
    private let interval: TimeInterval = 86_400 // 24 hours
    private var timer: Timer?

    private init() {}

    /// Call once from AppDelegate. Sends immediately if 24h elapsed, schedules repeating timer.
    func start() {
        sendIfNeeded()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sendIfNeeded()
        }
        timer?.tolerance = 3600 // 1hr tolerance for energy efficiency
    }

    private func sendIfNeeded() {
        let lastPing = UserDefaults.standard.object(forKey: lastPingKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastPing) >= interval else { return }

        Task {
            guard let url = URL(string: endpoint) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 15

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let payload = ["version": version]
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               (200...299).contains(http.statusCode) {
                UserDefaults.standard.set(Date(), forKey: lastPingKey)
            }
        }
    }
}
