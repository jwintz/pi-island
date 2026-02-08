//
//  UsageNotchView.swift
//  PiIsland
//
//  Usage monitor view for the notch interface
//

import SwiftUI

struct UsageNotchView: View {
    @State private var service = UsageMonitorService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Usage Monitor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                if service.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Button(action: { Task { await service.refreshAll() } }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Provider list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(configuredSnapshots) { snapshot in
                        ProviderUsageCard(snapshot: snapshot)
                            .equatable()
                    }

                    if configuredSnapshots.isEmpty {
                        Text("No providers configured.\nRun 'pi login <provider>' to set up.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 20)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            // Footer
            if let lastUpdate = service.lastRefreshTime {
                Text("Updated \(timeAgo(lastUpdate))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
        .onAppear {
            service.startMonitoring()
        }
        .onDisappear {
            service.stopMonitoring()
        }
    }

    /// Only show providers that have credentials configured
    private var configuredSnapshots: [UsageSnapshot] {
        service.configuredSnapshots
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func timeAgo(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Provider Usage Card

struct ProviderUsageCard: View, Equatable {
    let snapshot: UsageSnapshot

    nonisolated static func == (lhs: ProviderUsageCard, rhs: ProviderUsageCard) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Provider header
            HStack {
                Text(snapshot.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)

                Spacer()

                if let error = snapshot.error {
                    Text(error.code)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                } else if let requests = snapshot.requestsSummary {
                    Text(requests)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            // Usage windows
            if !snapshot.hasError {
                ForEach(snapshot.windows, id: \.label) { window in
                    UsageWindowRow(window: window)
                        .equatable()
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))

    }
}

// MARK: - Usage Window Row

struct UsageWindowRow: View, Equatable {
    let window: RateWindow
    
    nonisolated static func == (lhs: UsageWindowRow, rhs: UsageWindowRow) -> Bool {
        lhs.window == rhs.window
    }

    /// Period information calculated from reset time and label
    private var periodInfo: PeriodInfo? {
        guard let resetAt = window.resetAt else { return nil }

        let now = Date()

        // Determine period duration based on label
        let periodDuration: TimeInterval
        switch window.label.lowercased() {
        case "5h":
            periodDuration = 5 * 60 * 60  // 5 hours
        case "week":
            periodDuration = 7 * 24 * 60 * 60  // 7 days
        case "month", "subscription":
            periodDuration = 30 * 24 * 60 * 60  // ~30 days
        case "day", "tool calls":
            periodDuration = 24 * 60 * 60  // 1 day
        case "search/hr":
            periodDuration = 60 * 60  // 1 hour
        default:
            // Try to infer from reset time - if reset is within 2 hours, assume hourly
            // If within 2 days, assume daily, otherwise assume monthly
            let timeToReset = resetAt.timeIntervalSince(now)
            if timeToReset < 2 * 60 * 60 {
                periodDuration = 60 * 60  // hourly
            } else if timeToReset < 2 * 24 * 60 * 60 {
                periodDuration = 24 * 60 * 60  // daily
            } else {
                periodDuration = 30 * 24 * 60 * 60  // monthly
            }
        }

        let periodStart = resetAt.addingTimeInterval(-periodDuration)
        let elapsed = now.timeIntervalSince(periodStart)
        let remaining = resetAt.timeIntervalSince(now)
        let expectedUsage = max(0, min(100, (elapsed / periodDuration) * 100))

        return PeriodInfo(
            start: periodStart,
            end: resetAt,
            duration: periodDuration,
            elapsed: elapsed,
            remaining: remaining,
            expectedUsage: expectedUsage
        )
    }

    private struct PeriodInfo {
        let start: Date
        let end: Date
        let duration: TimeInterval
        let elapsed: TimeInterval
        let remaining: TimeInterval
        let expectedUsage: Double

        var elapsedFormatted: String {
            formatDuration(elapsed)
        }

        var remainingFormatted: String {
            formatDuration(remaining)
        }

        var startFormatted: String {
            formatDateTime(start)
        }

        var endFormatted: String {
            formatDateTime(end)
        }

        private func formatDuration(_ interval: TimeInterval) -> String {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60

            if hours >= 24 {
                let days = hours / 24
                let remainingHours = hours % 24
                if remainingHours > 0 {
                    return "\(days)d \(remainingHours)h"
                }
                return "\(days)d"
            } else if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }

        private static let dateTimeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, HH:mm"
            return formatter
        }()

        private func formatDateTime(_ date: Date) -> String {
            Self.dateTimeFormatter.string(from: date)
        }
    }

    /// Calculate expected linear usage based on time elapsed in the period
    private var expectedUsage: Double? {
        periodInfo?.expectedUsage
    }

    /// Whether current usage is ahead of linear pace
    private var isAheadOfPace: Bool {
        guard let expected = expectedUsage else { return false }
        return window.usedPercent > expected + 5  // 5% buffer
    }

    /// Whether current usage is behind linear pace (good!)
    private var isBehindPace: Bool {
        guard let expected = expectedUsage else { return false }
        return window.usedPercent < expected - 5  // 5% buffer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label and percentage row
            HStack {
                Text(window.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                if let usage = window.usageDescription {
                    Text(usage)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.trailing, 4)
                }

                // Show comparison to linear if available
                if let expected = expectedUsage {
                    let diff = window.usedPercent - expected
                    HStack(spacing: 2) {
                        if abs(diff) > 5 {
                            Image(systemName: diff > 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 8))
                                .foregroundStyle(diff > 0 ? .orange : .green)
                        }
                        Text("\(Int(window.usedPercent))%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(usageColor)
                    }
                } else {
                    Text("\(Int(window.usedPercent))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(usageColor)
                }
            }

            // Progress bar with linear marker
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))

                    // Usage fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(usageColor)
                        .frame(width: geometry.size.width * CGFloat(window.usedPercent) / 100)

                    // Linear pace marker (if available)
                    if let expected = expectedUsage {
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 1)
                            .offset(x: geometry.size.width * CGFloat(expected) / 100)
                    }
                }
            }
            .frame(height: 4)

            // Period bounds details
            if let info = periodInfo {
                HStack(spacing: 0) {
                    // Start time
                    Text(info.startFormatted)
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.3))

                    Spacer()

                    // Time info: elapsed / remaining
                    HStack(spacing: 4) {
                        Text("\(info.elapsedFormatted) elapsed")
                            .foregroundStyle(.white.opacity(0.35))
                        Text("•")
                            .foregroundStyle(.white.opacity(0.2))
                        Text("\(info.remainingFormatted) left")
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .font(.system(size: 8))

                    Spacer()

                    // End time (reset)
                    Text(info.endFormatted)
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
    }

    private var usageColor: Color {
        switch window.usedPercent {
        case 0..<50: return .green
        case 50..<80: return .yellow
        case 80..<95: return .orange
        default: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    UsageNotchView()
        .frame(width: 300, height: 400)
        .background(Color.black)
}
