import SwiftUI
import AppKit
import HarbourCore

struct ContentView: View {
    @ObservedObject var manager: BlockManager

    var body: some View {
        Group {
            if manager.isActive {
                ActiveView(manager: manager)
            } else {
                SetupView(manager: manager)
            }
        }
        .frame(width: 520)
    }
}

// MARK: - Setup

struct SetupView: View {
    @ObservedObject var manager: BlockManager
    @State private var newDomain = ""
    @State private var showAppPicker = false
    @State private var showFAQ = false
    @State private var showConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.setupBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    Hero(onHelp: { showFAQ = true })
                        .padding(.top, 18)

                    DomainSection(
                        manager: manager,
                        newDomain: $newDomain
                    )

                    AppsSection(
                        manager: manager,
                        onAddTap: { showAppPicker = true }
                    )

                    DurationSection(manager: manager)

                    if let error = errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    PrimaryButton(
                        title: "Start block",
                        enabled: canStart,
                        action: { showConfirm = true }
                    )
                    .padding(.top, 2)

                    Text("Requires admin password to start. Cannot be cancelled.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 18)
                }
                .padding(.horizontal, 22)
            }
            .frame(height: 640)
        }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(
                alreadyAdded: Set(manager.config.apps.map(\.path)),
                onPick: { app in
                    if !manager.config.apps.contains(where: { $0.path == app.path }) {
                        manager.config.apps.append(app)
                        manager.saveConfig()
                    }
                },
                onCancel: { showAppPicker = false }
            )
        }
        .sheet(isPresented: $showFAQ) {
            FAQView(onClose: { showFAQ = false })
        }
        .sheet(isPresented: $showConfirm) {
            ConfirmView(
                durationMinutes: manager.config.durationMinutes,
                domainCount: manager.config.domains.count,
                appCount: manager.config.apps.count,
                riskyDomains: Safety.riskyEntries(from: manager.config.domains),
                onCancel: { showConfirm = false },
                onConfirm: {
                    showConfirm = false
                    startBlock()
                }
            )
        }
    }

    private var canStart: Bool {
        manager.config.durationMinutes > 0
            && !(manager.config.domains.isEmpty && manager.config.apps.isEmpty)
    }

    private func startBlock() {
        do {
            try manager.startBlock()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Hero

private struct Hero: View {
    let onHelp: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                Text("Start a block")
                    .font(Theme.serif(size: 32, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Pick what to block. Harbour Control keeps it locked until the timer ends.")
                    .font(Theme.sans(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Spacer()
                Button(action: onHelp) {
                    Image(systemName: "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("How Harbour Control works")
            }
        }
    }
}

// MARK: - Section container

private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.sans(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textSecondary)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.creamBorder, lineWidth: 0.5)
                )
                .shadow(color: Theme.navy.opacity(0.05), radius: 8, y: 2)
        )
    }
}

// MARK: - Domains

private struct DomainSection: View {
    @ObservedObject var manager: BlockManager
    @Binding var newDomain: String
    @State private var presetsOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Domains")
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        TextField("twitter.com", text: $newDomain)
                            .textFieldStyle(.plain)
                            .font(Theme.sans(size: 13))
                            .onSubmit(add)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Theme.cream.opacity(0.6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(Theme.creamBorderSoft, lineWidth: 0.5)
                                    )
                            )
                        Button("Add", action: add)
                            .buttonStyle(HarbourSecondaryButtonStyle())
                            .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                            .keyboardShortcut(.defaultAction)
                        Menu {
                            ForEach(DomainPreset.allCases) { p in
                                Button {
                                    addPreset(p)
                                } label: {
                                    Label(p.rawValue, systemImage: p.symbol)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet")
                                Text("Presets")
                                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(10)

                    Divider().background(Theme.creamBorderSoft)

                    if manager.config.domains.isEmpty {
                        Text("No domains yet. Add one above or pick a preset.")
                            .font(Theme.sans(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(manager.config.domains, id: \.self) { domain in
                                    DomainRow(domain: domain, onRemove: {
                                        manager.config.domains.removeAll { $0 == domain }
                                        manager.saveConfig()
                                    })
                                    if domain != manager.config.domains.last {
                                        Divider().background(Theme.creamBorderSoft.opacity(0.5))
                                            .padding(.leading, 40)
                                    }
                                }
                            }
                        }
                        .frame(height: 120)
                    }
                }
            }
        }
    }

    private func add() {
        var d = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
        d = d.replacingOccurrences(of: "https://", with: "")
        d = d.replacingOccurrences(of: "http://", with: "")
        d = d.components(separatedBy: "/").first ?? d
        guard !d.isEmpty, !manager.config.domains.contains(d) else { newDomain = ""; return }
        manager.config.domains.append(d)
        manager.saveConfig()
        newDomain = ""
    }

    private func addPreset(_ p: DomainPreset) {
        var changed = false
        for d in p.domains where !manager.config.domains.contains(d) {
            manager.config.domains.append(d)
            changed = true
        }
        if changed { manager.saveConfig() }
    }
}

private struct DomainRow: View {
    let domain: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(domain: domain, size: 20)
            Text(domain)
                .font(Theme.sans(size: 13))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
    }
}

// MARK: - Apps

private struct AppsSection: View {
    @ObservedObject var manager: BlockManager
    let onAddTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Apps")
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: onAddTap) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add app…")
                        }
                        .font(Theme.sans(size: 13, weight: .medium))
                        .foregroundStyle(Theme.navy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    .buttonStyle(.plain)

                    Divider().background(Theme.creamBorderSoft)

                    if manager.config.apps.isEmpty {
                        Text("No apps blocked.")
                            .font(Theme.sans(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(manager.config.apps) { app in
                                    AppRow(app: app, onRemove: {
                                        manager.config.apps.removeAll { $0.path == app.path }
                                        manager.saveConfig()
                                    })
                                    if app.path != manager.config.apps.last?.path {
                                        Divider().background(Theme.creamBorderSoft.opacity(0.5))
                                            .padding(.leading, 40)
                                    }
                                }
                            }
                        }
                        .frame(height: 110)
                    }
                }
            }
        }
    }
}

private struct AppRow: View {
    let app: BlockedApp
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable().interpolation(.high)
                .frame(width: 20, height: 20)
            Text(app.name)
                .font(Theme.sans(size: 13))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
    }
}

// MARK: - Duration

private struct DurationSection: View {
    @ObservedObject var manager: BlockManager

    private let presets: [(String, Int)] = [
        ("15m", 15), ("30m", 30), ("1h", 60), ("2h", 120),
        ("4h", 240), ("8h", 480), ("24h", 1440),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Duration")

            HStack(spacing: 6) {
                ForEach(presets, id: \.0) { label, min in
                    let selected = manager.config.durationMinutes == min
                    Button {
                        manager.config.durationMinutes = min
                        manager.saveConfig()
                    } label: {
                        Text(label)
                            .font(Theme.sans(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Theme.parchmentWarm : Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(selected ? AnyShapeStyle(Theme.navy) : AnyShapeStyle(Color.white.opacity(0.7)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .strokeBorder(
                                                selected ? Color.clear : Theme.creamBorder,
                                                lineWidth: 0.5
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                DurationSpinner(
                    label: "HOURS",
                    value: manager.config.durationMinutes / 60,
                    format: "%d",
                    onMinus: { nudge(hours: -1) },
                    onPlus:  { nudge(hours: 1) },
                    canMinus: manager.config.durationMinutes > 5 && manager.config.durationMinutes >= 60,
                    canPlus:  manager.config.durationMinutes + 60 <= 1440
                )
                Text(":")
                    .font(Theme.serif(size: 36, weight: .light))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    .padding(.top, -4)
                DurationSpinner(
                    label: "MINUTES",
                    value: manager.config.durationMinutes % 60,
                    format: "%02d",
                    onMinus: { nudge(minutes: -5) },
                    onPlus:  { nudge(minutes: 5) },
                    canMinus: manager.config.durationMinutes > 5,
                    canPlus:  manager.config.durationMinutes < 1440
                )
            }
        }
    }

    private func nudge(hours: Int = 0, minutes: Int = 0) {
        let total = manager.config.durationMinutes + hours * 60 + minutes
        manager.config.durationMinutes = max(5, min(1440, total))
        manager.saveConfig()
    }
}

private struct DurationSpinner: View {
    let label: String
    let value: Int
    let format: String
    let onMinus: () -> Void
    let onPlus: () -> Void
    let canMinus: Bool
    let canPlus: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: format, value))
                .font(Theme.serif(size: 42, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(Theme.sans(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                SpinnerButton(symbol: "minus", action: onMinus, enabled: canMinus)
                SpinnerButton(symbol: "plus",  action: onPlus,  enabled: canPlus)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.creamBorder, lineWidth: 0.5)
                )
        )
    }
}

private struct SpinnerButton: View {
    let symbol: String
    let action: () -> Void
    let enabled: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? Theme.navy : Theme.textTertiary)
                .frame(width: 26, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(enabled ? Theme.navySoft : Theme.cream.opacity(0.6))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Primary + Secondary buttons

struct PrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.sans(size: 15, weight: .semibold))
                .foregroundStyle(Theme.parchmentWarm)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(enabled ? AnyShapeStyle(Theme.primaryButton) : AnyShapeStyle(Color.gray.opacity(0.3)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                        .blendMode(.overlay)
                )
                .shadow(color: Theme.navy.opacity(enabled ? 0.25 : 0), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct HarbourSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(size: 12, weight: .semibold))
            .foregroundStyle(Theme.navy)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Theme.navySoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.navy.opacity(0.15), lineWidth: 0.5)
                    )
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Active

struct ActiveView: View {
    @ObservedObject var manager: BlockManager
    @State private var showFAQ = false
    @State private var showAppPicker = false
    @State private var expanded = false
    @State private var newDomain = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.activeBackground.ignoresSafeArea()
            StarfieldView().opacity(0.7)

            ScrollView {
                VStack(spacing: 18) {
                    Spacer(minLength: 12)

                    LighthouseIcon(size: 128)

                    VStack(spacing: 4) {
                        Text("Blocking")
                            .font(Theme.serif(size: 30, weight: .bold))
                            .foregroundStyle(Theme.parchmentWarm)
                        Text("You're in a focused session.")
                            .font(Theme.sans(size: 13))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }

                    Text(formatRemaining(manager.remainingSeconds))
                        .font(Theme.serif(size: 56, weight: .semibold))
                        .foregroundStyle(Theme.parchmentWarm)
                        .monospacedDigit()
                        .padding(.top, 4)

                    ProgressTrack(progress: progress)
                        .frame(height: 6)
                        .padding(.horizontal, 42)

                    if let state = manager.currentState {
                        HStack(spacing: 26) {
                            ActiveStat(symbol: "globe",
                                       text: "\(manager.effectiveDomains.count) \(manager.effectiveDomains.count == 1 ? "site" : "sites")")
                            ActiveStat(symbol: "square.grid.2x2.fill",
                                       text: "\(manager.effectiveApps.count) \(manager.effectiveApps.count == 1 ? "app" : "apps")")
                        }
                        .padding(.top, 6)

                        Text("Ends \(formatEnds(state.endTime))")
                            .font(Theme.sans(size: 12))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }

                    // Blocklist manager
                    BlocklistSection(
                        manager: manager,
                        expanded: $expanded,
                        newDomain: $newDomain,
                        onAddApp: { showAppPicker = true }
                    )
                    .padding(.top, 4)

                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
            }

            Button {
                showFAQ = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .frame(width: 520, height: 640)
        .sheet(isPresented: $showFAQ) { FAQView(onClose: { showFAQ = false }) }
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(
                alreadyAdded: Set(manager.effectiveApps.map(\.path)),
                onPick: { manager.addAppLive($0) },
                onCancel: { showAppPicker = false }
            )
        }
    }

    private var progress: Double {
        guard let state = manager.currentState else { return 0 }
        let total = state.endTime.timeIntervalSince(state.startTime)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(state.startTime)
        return min(1, max(0, elapsed / total))
    }

    private func formatRemaining(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    private func formatEnds(_ d: Date) -> String {
        let time = d.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
        let date = d.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "en_US")))
        return "\(time) · \(date)"
    }
}

// MARK: - Blocklist section (active block — can only add, never remove)

private struct BlocklistSection: View {
    @ObservedObject var manager: BlockManager
    @Binding var expanded: Bool
    @Binding var newDomain: String
    let onAddApp: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Disclosure header
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Text("Manage blocklist")
                        .font(Theme.sans(size: 12, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.7))
                    Spacer()
                    Text("add only · no take-backs")
                        .font(Theme.sans(size: 10))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 10) {
                    addControls
                    listBody
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }

    private var addControls: some View {
        HStack(spacing: 8) {
            TextField("new-site.com", text: $newDomain)
                .textFieldStyle(.plain)
                .font(Theme.sans(size: 12))
                .foregroundStyle(Theme.parchmentWarm)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
                .onSubmit(addDomainAction)

            Button("Add site", action: addDomainAction)
                .buttonStyle(AddButtonStyle())
                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)

            Button(action: onAddApp) {
                HStack(spacing: 4) {
                    Image(systemName: "app.badge.fill")
                    Text("Add app")
                }
            }
            .buttonStyle(AddButtonStyle())
        }
    }

    private func addDomainAction() {
        manager.addDomainLive(newDomain)
        newDomain = ""
    }

    private var listBody: some View {
        VStack(spacing: 6) {
            let domains = manager.effectiveDomains
            let apps = manager.effectiveApps

            if !domains.isEmpty {
                VStack(spacing: 2) {
                    ForEach(domains, id: \.self) { d in
                        BlocklistRow(icon: .domain(d), label: d)
                    }
                }
            }

            if !apps.isEmpty {
                VStack(spacing: 2) {
                    ForEach(apps) { app in
                        BlocklistRow(icon: .app(app.path), label: app.name)
                    }
                }
            }

            if domains.isEmpty && apps.isEmpty {
                Text("Blocklist is empty.")
                    .font(Theme.sans(size: 12))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(.vertical, 10)
            }
        }
        .padding(.top, 2)
    }
}

private enum BlocklistIcon {
    case domain(String)
    case app(String)
}

private struct BlocklistRow: View {
    let icon: BlocklistIcon
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 18, height: 18)
            Text(label)
                .font(Theme.sans(size: 12))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.25))
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.04))
        )
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .domain(let d):
            FaviconView(domain: d, size: 18)
        case .app(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable().interpolation(.high)
                .frame(width: 18, height: 18)
        }
    }
}

private struct AddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.sans(size: 11, weight: .semibold))
            .foregroundStyle(Theme.parchmentWarm)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.25 : 0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct ProgressTrack: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.1))
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Theme.amber, Theme.amber.opacity(0.6)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, geo.size.width * progress))
                    .animation(.linear(duration: 0.5), value: progress)
            }
        }
    }
}

private struct ActiveStat: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(Theme.sans(size: 12, weight: .medium))
        }
        .foregroundStyle(Color.white.opacity(0.7))
    }
}

private struct StarfieldView: View {
    struct Star: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let opacity: Double
        let delay: Double
    }
    @State private var stars: [Star] = Self.makeStars()

    private static func makeStars() -> [Star] {
        (0..<28).map { i -> Star in
            let x: CGFloat = CGFloat((i * 53) % 100) / 100.0
            let y: CGFloat = CGFloat((i * 37) % 40 + 2) / 100.0
            let opacity: Double = 0.25 + Double(i % 5) * 0.14
            let delay: Double = Double(i % 7) * 0.4
            return Star(x: x, y: y, opacity: opacity, delay: delay)
        }
    }
    @State private var twinkle = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(stars) { s in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 2, height: 2)
                        .opacity(twinkle ? s.opacity : s.opacity * 0.3)
                        .position(x: geo.size.width * s.x, y: geo.size.height * s.y)
                        .animation(
                            .easeInOut(duration: 2.8)
                                .repeatForever(autoreverses: true)
                                .delay(s.delay),
                            value: twinkle
                        )
                }
            }
            .onAppear { twinkle = true }
        }
    }
}
