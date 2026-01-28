//
//  DebugNetworkLogView.swift
//  Claude Usage
//
//  Created by Claude on 2026-01-29.
//

import SwiftUI
import Combine

struct DebugNetworkLogView: View {
    @StateObject private var loggerService = NetworkLoggerService.shared
    @State private var selectedDuration: LoggingDuration = .fifteenMinutes
    @State private var selectedLog: NetworkRequestLog?
    @State private var showClearConfirmation = false
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Header
                SettingsPageHeader(
                    title: "Debug Tools",
                    subtitle: "Log network requests for troubleshooting and diagnostics"
                )

                // Controls Card
                SettingsSectionCard(
                    title: "Network Request Logger",
                    subtitle: "Capture all API requests with detailed information"
                ) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                        // Duration Picker
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            Text("Logging Duration")
                                .font(DesignTokens.Typography.bodyMedium)

                            Picker("", selection: $selectedDuration) {
                                ForEach(LoggingDuration.allCases) { duration in
                                    Text(duration.displayName).tag(duration)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(loggerService.session.isActive)
                        }

                        Divider()

                        // Status Indicator
                        HStack(spacing: DesignTokens.Spacing.iconText) {
                            Circle()
                                .fill(loggerService.session.isActive ? Color.green : Color.gray)
                                .frame(width: DesignTokens.StatusDot.standard,
                                       height: DesignTokens.StatusDot.standard)

                            if loggerService.session.isActive {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Logging Active")
                                        .font(DesignTokens.Typography.bodyMedium)
                                        .foregroundColor(.green)

                                    if let remaining = loggerService.remainingTime {
                                        Text("Stops in \(formatTimeRemaining(remaining))")
                                            .font(DesignTokens.Typography.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Text("Logging Inactive")
                                    .font(DesignTokens.Typography.bodyMedium)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        Divider()

                        // Action Buttons
                        HStack(spacing: DesignTokens.Spacing.medium) {
                            if loggerService.session.isActive {
                                SettingsButton(
                                    title: "Stop Logging",
                                    icon: "stop.fill",
                                    style: .destructive
                                ) {
                                    loggerService.stopLogging()
                                }
                            } else {
                                SettingsButton(
                                    title: "Start Logging",
                                    icon: "play.fill",
                                    style: .primary
                                ) {
                                    loggerService.startLogging(duration: selectedDuration.rawValue)
                                }
                            }

                            SettingsButton(
                                title: "Clear Logs",
                                icon: "trash"
                            ) {
                                showClearConfirmation = true
                            }
                            .disabled(loggerService.session.logs.isEmpty)
                        }
                    }
                }
                .alert("Clear All Logs?", isPresented: $showClearConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Clear", role: .destructive) {
                        loggerService.clearLogs()
                    }
                } message: {
                    Text("This will permanently delete all logged network requests.")
                }

                // Logs List Card
                SettingsSectionCard(
                    title: "Captured Requests",
                    subtitle: "\(loggerService.session.logs.count) requests logged"
                ) {
                    if loggerService.session.logs.isEmpty {
                        Text("No requests logged yet")
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, DesignTokens.Spacing.cardPadding)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(loggerService.session.logs.reversed()) { log in
                                NetworkLogRow(log: log) {
                                    selectedLog = log
                                }

                                if log.id != loggerService.session.logs.first?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .sheet(item: $selectedLog) { log in
            NetworkLogDetailView(log: log)
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60

        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}

// MARK: - Log Row

struct NetworkLogRow: View {
    let log: NetworkRequestLog
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignTokens.Spacing.medium) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                // Main content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // Method badge
                        Text(log.method)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(methodColor)
                            .cornerRadius(4)

                        // Status code
                        if let status = log.statusCode {
                            Text("\(status)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        // Duration
                        if let duration = log.duration {
                            Text(String(format: "%.2fs", duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Timestamp
                        Text(formatTime(log.timestamp))
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                    }

                    // URL
                    Text(log.url)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        if let status = log.statusCode {
            switch status {
            case 200..<300: return .green
            case 400..<500: return .orange
            case 500...: return .red
            default: return .gray
            }
        }
        return log.errorMessage != nil ? .red : .gray
    }

    private var methodColor: Color {
        switch log.method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        default: return .gray
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Log Detail View

struct NetworkLogDetailView: View {
    let log: NetworkRequestLog
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Request Details")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Basic Info
                    DetailSection(title: "Basic Information") {
                        DetailRow(label: "URL", value: log.url)
                        DetailRow(label: "Method", value: log.method)
                        if let status = log.statusCode {
                            DetailRow(label: "Status Code", value: "\(status)")
                        }
                        if let duration = log.duration {
                            DetailRow(label: "Duration", value: String(format: "%.3f seconds", duration))
                        }
                        DetailRow(label: "Timestamp", value: formatFullTimestamp(log.timestamp))
                    }

                    // Request Body
                    if let requestBody = log.requestBody {
                        DetailSection(title: "Request Body") {
                            Text(requestBody)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(6)
                        }
                    }

                    // Response Preview
                    if let response = log.responsePreview {
                        DetailSection(title: "Response (Preview)") {
                            VStack(alignment: .leading, spacing: 8) {
                                if let size = log.fullResponseSize {
                                    Text("Full size: \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text(response)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .cornerRadius(6)
                            }
                        }
                    }

                    // Error
                    if let error = log.errorMessage {
                        DetailSection(title: "Error") {
                            Text(error)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.red)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }

    private func formatFullTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            content
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Preview

#Preview {
    DebugNetworkLogView()
        .frame(width: 520, height: 600)
}
