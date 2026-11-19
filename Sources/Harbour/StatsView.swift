import SwiftUI
import Charts
import AppKit
import HarbourCore

/// History of blocked open attempts: how often you reached for a blocked site
/// or app, per day and per target. Read from the daemon's stats file.
struct StatsView: View {
    @ObservedObject var manager: BlockManager
    let onClose: () -> Void

    enum Range: String, CaseIterable, Identifiable {
        case week = "7 days"
        case month = "30 days"
        case year = "12 months"
        var id: String { rawValue }
    }

    @State private var range: Range = .week

    private var stats: AttemptStats { manager.attemptStats }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    if stats.lifetimeTotal == 0 {
                        emptyState
                    } else {
                        tiles
                        chartCard
                        topCard
                    }
                    Text("Counted on this Mac only and never sent anywhere. Each burst counts once: a page load or an app relaunch within a few seconds is one attempt. Browsers using their own secure DNS or a VPN can skip the count, but the block still applies.")
                        .font(Theme.sans(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: 488, height: 580)
        .background(Theme.setupBackground)
        .environment(\.colorScheme, .light)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.beam)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.activeBackground))

            VStack(alignment: .leading, spacing: 1) {
                Text("Attempts stopped")
                    .font(Theme.serif(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Every time you reached for something you blocked.")
                    .font(Theme.sans(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            CircleIconButton(symbol: "xmark", tint: Theme.textSecondary, hoverFill: Theme.navySoft,
                             help: "Close", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.parchmentWarm)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.creamBorderSoft).frame(height: 1)
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        HStack(spacing: 10) {
            if manager.isActive {
                StatTile(value: manager.sessionAttempts, label: "This block", highlighted: true)
            }
            StatTile(value: stats.counts(lastDays: 1).total, label: "Today")
            StatTile(value: stats.counts(lastDays: 7).total, label: "7 days")
            // Lifetime total: unlike the per-day detail it is never pruned.
            StatTile(value: stats.lifetimeTotal, label: "All time")
        }
    }

    // MARK: Chart

    private struct DayBar: Identifiable {
        let day: Date
        let kind: String
        let count: Int
        var id: String { "\(day.timeIntervalSince1970)-\(kind)" }
    }

    private var chartData: [DayBar] {
        let keys = stats.dayKeys(lastDays: 14)
        let parser = DateFormatter()
        // Day keys are Gregorian whatever calendar the user prefers.
        parser.calendar = AttemptStats.storageCalendar
        parser.timeZone = .current
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return keys.flatMap { key -> [DayBar] in
            guard let day = parser.date(from: key) else { return [] }
            let c = stats.days[key] ?? AttemptStats.Counts()
            return [
                DayBar(day: day, kind: "Websites", count: c.sites.values.reduce(0, +)),
                DayBar(day: day, kind: "Apps", count: c.apps.values.reduce(0, +)),
            ]
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 14 days")
                .font(Theme.sans(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Chart(chartData) { bar in
                BarMark(
                    x: .value("Day", bar.day, unit: .day),
                    y: .value("Attempts", bar.count)
                )
                .foregroundStyle(by: .value("Kind", bar.kind))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale(["Websites": Theme.navyLight, "Apps": Theme.amber])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                        .font(Theme.sans(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.creamBorderSoft)
                    AxisValueLabel().font(Theme.sans(size: 10))
                }
            }
            .chartLegend(position: .top, alignment: .trailing)
            .frame(height: 150)
            .accessibilityLabel("Attempts per day for the last 14 days")
        }
        .padding(14)
        .background(CardBackground(radius: 12))
    }

    // MARK: Top targets

    private struct Target: Identifiable {
        enum Kind { case site, app }
        let kind: Kind
        let key: String
        let count: Int
        var id: String { (kind == .site ? "site:" : "app:") + key }
        var name: String {
            switch kind {
            case .site: return key
            case .app: return (key as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            }
        }
    }

    private var rangeCounts: AttemptStats.Counts {
        switch range {
        case .week: return stats.counts(lastDays: 7)
        case .month: return stats.counts(lastDays: 30)
        case .year: return stats.counts(lastDays: 365)
        }
    }

    private var topTargets: [Target] {
        let c = rangeCounts
        let all = c.sites.map { Target(kind: .site, key: $0.key, count: $0.value) }
            + c.apps.map { Target(kind: .app, key: $0.key, count: $0.value) }
        return Array(all.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }.prefix(8))
    }

    private var topCard: some View {
        let targets = topTargets
        let maxCount = max(1, targets.first?.count ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Most tried")
                    .font(Theme.sans(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            if targets.isEmpty {
                Text("No attempts in this period.")
                    .font(Theme.sans(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 8) {
                    ForEach(targets) { t in
                        TargetRow(target: t, fraction: Double(t.count) / Double(maxCount))
                    }
                }
            }
        }
        .padding(14)
        .background(CardBackground(radius: 12))
    }

    private struct TargetRow: View {
        let target: Target
        let fraction: Double

        var body: some View {
            HStack(spacing: 10) {
                Group {
                    switch target.kind {
                    case .site:
                        // Cache only: history must not reach the favicon service.
                        FaviconView(domain: target.key, size: 16, allowsNetwork: false)
                    case .app:
                        Image(nsImage: NSWorkspace.shared.icon(forFile: target.key))
                            .resizable()
                            .interpolation(.high)
                    }
                }
                .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(target.name)
                        .font(Theme.sans(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    GeometryReader { geo in
                        Capsule()
                            .fill(target.kind == .site ? Theme.navyLight.opacity(0.75) : Theme.amber.opacity(0.85))
                            .frame(width: max(4, geo.size.width * fraction), height: 4)
                    }
                    .frame(height: 4)
                }

                Text("\(target.count)")
                    .font(Theme.sans(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(target.name), \(target.count) \(target.count == 1 ? "attempt" : "attempts")")
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.amber)
            Text("Nothing to count yet")
                .font(Theme.serif(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("During a block, each time you try to open a blocked website or app shows up here.")
                .font(Theme.sans(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(CardBackground(radius: 12))
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    var highlighted = false

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(Theme.serif(size: 26, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(highlighted ? Theme.nightText : Theme.textPrimary)
                .numericTransition()
            Text(label)
                .font(Theme.sans(size: 11, weight: .medium))
                .foregroundStyle(highlighted ? Theme.nightSecondary : Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.activeBackground)
            } else {
                CardBackground(radius: 12)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
