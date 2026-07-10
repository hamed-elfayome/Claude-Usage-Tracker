import SwiftUI
import Combine

/// A small popover shown when clicking the peak hours icon.
struct PeakHoursPopoverView: View {
    @ObservedObject private var peakService = PeakHoursService.shared
    @State private var now = Date()

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var peakEndDate: Date? {
        guard peakService.isPeakHours else { return nil }
        return PeakHoursService.peakEndDate()
    }

    private var endsAtString: String {
        guard let end = peakEndDate else { return "--" }
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "jmm", options: 0, locale: .current
        ) ?? "h:mm a"
        return formatter.string(from: end)
    }

    private var remainingString: String {
        guard let end = peakEndDate else { return "--" }
        let remaining = end.timeIntervalSince(now)
        guard remaining > 60 else { return "< 1m" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 13))
                Text("Peak Hours Active")
                    .font(.system(size: 13, weight: .semibold))
            }

            Text("Session limits are consumed faster during peak hours (weekdays \(PeakHoursService.localTimeRangeString())).")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // End time & remaining
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ends at")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(endsAtString)
                        .font(.system(size: 13, weight: .medium))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Remaining")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(remainingString)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(14)
        .frame(width: 260)
        .onReceive(refreshTimer) { _ in
            now = Date()
        }
    }
}
