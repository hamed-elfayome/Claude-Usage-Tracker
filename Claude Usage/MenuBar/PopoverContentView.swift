import SwiftUI

/// Smart, minimal, and professional popover interface
struct PopoverContentView: View {
    @ObservedObject var manager: MenuBarManager
    let onRefresh: () -> Void
    let onPreferences: () -> Void
    let onQuit: () -> Void
    
    @State private var isRefreshing = false
    @State private var showInsights = false

    var body: some View {
        VStack(spacing: 0) {
            // Smart Header with Status
            SmartHeader(
                usage: manager.usage,
                isRefreshing: isRefreshing,
                onRefresh: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isRefreshing = true
                    }
                    onRefresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isRefreshing = false
                        }
                    }
                }
            )

            // Intelligent Usage Dashboard
            SmartUsageDashboard(usage: manager.usage)
            
            // Contextual Insights
            if showInsights {
                ContextualInsights(usage: manager.usage)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }

            // Smart Footer with Actions
            SmartFooter(
                usage: manager.usage,
                showInsights: $showInsights,
                onPreferences: onPreferences,
                onQuit: onQuit
            )
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
        .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 10)
    }
}

// MARK: - Smart Header Component
struct SmartHeader: View {
    let usage: ClaudeUsage
    let isRefreshing: Bool
    let onRefresh: () -> Void
    
    
    var body: some View {
        HStack(spacing: 12) {
            // App Logo
            HStack(spacing: 8) {
                Image("HeaderLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude Usage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    // Subtle creator link
                    Button(action: {
                        if let url = URL(string: "https://github.com/hamed-elfayome") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("by Hamed Elfayome")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Created by Hamed Elfayome")
                }
            }
            
            Spacer()
            
            // Smart Refresh Button
            Button(action: onRefresh) {
                HStack(spacing: 4) {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundColor(.secondary)
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }
}

// MARK: - Smart Usage Dashboard
struct SmartUsageDashboard: View {
    let usage: ClaudeUsage
    
    var body: some View {
        VStack(spacing: 16) {
            // Primary Usage Card
            SmartUsageCard(
                title: "Session Usage",
                subtitle: "5-hour rolling window",
                percentage: usage.sessionPercentage,
                resetTime: usage.sessionResetTime,
                isPrimary: true
            )
            
            // Secondary Usage Cards
            HStack(spacing: 12) {
                SmartUsageCard(
                    title: "Weekly",
                    subtitle: "All models",
                    percentage: usage.weeklyPercentage,
                    resetTime: usage.weeklyResetTime,
                    isPrimary: false
                )
                
                if usage.opusWeeklyTokensUsed > 0 {
                    SmartUsageCard(
                        title: "Opus",
                        subtitle: "Weekly",
                        percentage: usage.opusWeeklyPercentage,
                        resetTime: nil,
                        isPrimary: false
                    )
                }
            }
            
            // Monthly Cost Card (New)
            if let used = usage.costUsed, let limit = usage.costLimit, let currency = usage.costCurrency, limit > 0 {
                let percentage = (used / limit) * 100.0
                SmartUsageCard(
                    title: "Monthly Cost",
                    subtitle: String(format: "%.2f / %.2f %@", used / 100.0, limit / 100.0, currency),
                    percentage: percentage,
                    resetTime: nil,
                    isPrimary: false
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Smart Usage Card
struct SmartUsageCard: View {
    let title: String
    let subtitle: String
    let percentage: Double
    let resetTime: Date?
    let isPrimary: Bool
    
    private var statusColor: Color {
        switch percentage {
        case 0..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
    
    private var statusIcon: String {
        switch percentage {
        case 0..<50: return "checkmark.circle.fill"
        case 50..<80: return "exclamationmark.triangle.fill"
        default: return "xmark.circle.fill"
        }
    }
    
    var body: some View {
        VStack(spacing: isPrimary ? 12 : 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: isPrimary ? 13 : 11, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: isPrimary ? 10 : 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: isPrimary ? 12 : 10, weight: .medium))
                        .foregroundColor(statusColor)
                    
                    Text("\(Int(percentage))%")
                        .font(.system(size: isPrimary ? 16 : 14, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor)
                }
            }
            
            // Progress visualization
            VStack(spacing: 6) {
                // Animated progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [statusColor, statusColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * min(percentage / 100.0, 1.0))
                    }
                    .animation(.easeInOut(duration: 0.8), value: percentage)
                }
                .frame(height: isPrimary ? 8 : 6)
                
                // Reset time information
                if let reset = resetTime {
                    HStack {
                        Spacer()
                        Text("Resets \(reset.resetTimeString())")
                            .font(.system(size: isPrimary ? 9 : 8, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(isPrimary ? 16 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }
}

// MARK: - Contextual Insights
struct ContextualInsights: View {
    let usage: ClaudeUsage
    
    private var insights: [Insight] {
        var result: [Insight] = []
        
        // Session insights
        if usage.sessionPercentage > 80 {
            result.append(Insight(
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                title: "High Session Usage",
                description: "Consider taking a break to reset your session window"
            ))
        }
        
        // Weekly insights
        if usage.weeklyPercentage > 90 {
            result.append(Insight(
                icon: "clock.fill",
                color: .red,
                title: "Weekly Limit Approaching",
                description: "You're close to your weekly token limit"
            ))
        }
        
        // Efficiency insights
        if usage.sessionPercentage < 20 && usage.weeklyPercentage < 30 {
            result.append(Insight(
                icon: "checkmark.circle.fill",
                color: .green,
                title: "Efficient Usage",
                description: "Great job managing your token consumption!"
            ))
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(insights, id: \.title) { insight in
                HStack(spacing: 10) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(insight.color)
                        .frame(width: 16)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(insight.description)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(insight.color.opacity(0.08))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct Insight {
    let icon: String
    let color: Color
    let title: String
    let description: String
}

// MARK: - Smart Footer
struct SmartFooter: View {
    let usage: ClaudeUsage
    @Binding var showInsights: Bool
    let onPreferences: () -> Void
    let onQuit: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)
            
            // Action buttons
            HStack(spacing: 8) {
                SmartActionButton(
                    icon: "gearshape.fill",
                    title: "Settings",
                    action: onPreferences
                )
                
                SmartActionButton(
                    icon: "power",
                    title: "Quit",
                    isDestructive: true,
                    action: onQuit
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Smart Action Button
struct SmartActionButton: View {
    let icon: String
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .secondary)
                    .frame(width: 14)
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isHovered 
                        ? (isDestructive ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                        : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
