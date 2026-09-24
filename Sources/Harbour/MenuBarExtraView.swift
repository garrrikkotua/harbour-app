import SwiftUI
import AppKit
import HarbourCore

// MARK: - Menu bar label

/// The status item itself. Idle: a template lighthouse. Active: the lamp is
/// lit (one steady frame) and the time left sits next to it with units
/// ("14m", "1h 05m"), so it only changes once a minute.
struct MenuBarLabel: View {
    @ObservedObject var manager: BlockManager

    var body: some View {
        if manager.isActive {
            HStack(spacing: 2) {
                Image(nsImage: MenuBarIcon.lit)
                Text(MenuBarIcon.compactTime(manager.remainingSeconds))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Harbour Control, \(MenuBarIcon.spokenTime(manager.remainingSeconds)) remaining")
        } else {
            Image(nsImage: MenuBarIcon.idle)
                .accessibilityLabel("Harbour Control")
        }
    }
}

// MARK: - Popover

struct MenuBarExtraView: View {
    @ObservedObject var manager: BlockManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if manager.isActive {
                    ActiveMenuPanel(manager: manager, onOpen: openMain)
                        .transition(.opacity)
                } else {
                    IdleMenuPanel(manager: manager, onStart: openMain)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: manager.isActive)

            Divider()
                .padding(.horizontal, 12)

            QuitFooter(isActive: manager.isActive)
        }
        .frame(width: 300)
    }

    private func openMain() {
        openWindow(id: MainWindow.id)
        NSApp.activate(ignoringOtherApps: true)
        // Bring the main window forward even if it was merely behind others.
        for window in NSApp.windows where window.identifier?.rawValue == MainWindow.id {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Idle

private struct IdleMenuPanel: View {
    @ObservedObject var manager: BlockManager
    let onStart: () -> Void

    private var sites: Int { manager.config.domains.count }
    private var apps: Int { manager.config.apps.count }
    private var hasSelection: Bool { sites + apps > 0 }
    private var duration: String { DurationText.short(manager.config.durationMinutes) }

    /// What the next block would cover, from the saved setup.
    private var summary: String {
        guard hasSelection else { return "Nothing selected yet" }
        let s = "\(sites) \(sites == 1 ? "site" : "sites")"
        let a = "\(apps) \(apps == 1 ? "app" : "apps")"
        return "\(s) · \(a) · \(duration)"
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.activeBackground)
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    // Lamp banked low: lit vs. quiet reads at a glance.
                    LighthouseGlyph(height: 26, lit: false, tint: Theme.parchmentWarm.opacity(0.9), ember: 0.4)
                        .offset(y: 1)
                }
                .frame(width: 44, height: 44)
                .shadow(color: Theme.navy.opacity(0.25), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Harbour is quiet")
                        .font(Theme.serif(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(Theme.sans(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            // Opens the main window (and its confirm step); never starts a
            // block from here.
            Button(action: onStart) {
                HStack(spacing: 6) {
                    Text(hasSelection ? "Start a \(duration) block…" : "Set up a block…")
                        .font(Theme.sans(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.8)
                }
                .foregroundStyle(Theme.parchmentWarm)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.primaryButton)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }
}

// MARK: - Active

private struct ActiveMenuPanel: View {
    @ObservedObject var manager: BlockManager
    let onOpen: () -> Void

    private let previewLimit = 4

    var body: some View {
        VStack(spacing: 12) {
            NightCard(manager: manager)

            counts

            blocklistPreview

            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11, weight: .medium))
                    Text("Open Harbour Control")
                        .font(Theme.sans(size: 12.5, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
            }
            .buttonStyle(PressableStyle())
        }
        .padding(10)
    }

    private var counts: some View {
        let sites = manager.effectiveDomains.count
        let apps = manager.effectiveApps.count
        return HStack(spacing: 8) {
            Label {
                Text("\(sites) \(sites == 1 ? "site" : "sites")")
            } icon: {
                Image(systemName: "globe")
            }
            Text("·").foregroundStyle(.tertiary)
            Label {
                Text("\(apps) \(apps == 1 ? "app" : "apps")")
            } icon: {
                Image(systemName: "square.grid.2x2")
            }
            Spacer(minLength: 0)
            Text("add-only")
                .font(Theme.sans(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .labelStyle(CompactLabelStyle())
        .font(Theme.sans(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private enum Item: Identifiable {
        case app(BlockedApp)
        case domain(String)
        var id: String {
            switch self {
            case .app(let a): return "app:" + a.path
            case .domain(let d): return "web:" + d
            }
        }
    }

    private var blocklistPreview: some View {
        // Apps first — there are usually fewer and their icons read instantly.
        let all: [Item] = manager.effectiveApps.map(Item.app) + manager.effectiveDomains.map(Item.domain)
        let shown = Array(all.prefix(previewLimit))
        let more = all.count - shown.count
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 9) {
                    switch item {
                    case .app(let app):
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 18, height: 18)
                        Text(app.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    case .domain(let domain):
                        FaviconView(domain: domain, size: 16)
                            .frame(width: 18, height: 18)
                        Text(domain)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .font(Theme.sans(size: 12.5))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                if index < shown.count - 1 || more > 0 {
                    Divider().padding(.leading, 37).opacity(0.6)
                }
            }
            if more > 0 {
                HStack {
                    Text("+\(more) more")
                        .font(Theme.sans(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.leading, 27)
                .frame(height: 26)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Night card

/// Deep-navy card with a twinkling sky, a sweeping beam and the lit
/// lighthouse above a serif countdown. Mirrors the landing page hero.
private struct NightCard: View {
    @ObservedObject var manager: BlockManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.navyDeep, Theme.navy, Theme.navyLight.opacity(0.95)],
                startPoint: .top, endPoint: .bottom
            )

            // Sky + beam + lighthouse share one clock. Paused under Reduce
            // Motion (a still, softly lit scene instead).
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .top) {
                    NightSky(time: t)
                    LighthouseGlyph(
                        height: 40,
                        lit: true,
                        tint: Theme.parchmentWarm,
                        glow: reduceMotion ? 1 : 0.82 + 0.18 * sin(t * 1.4)
                    )
                    .padding(.top, 14)
                }
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer().frame(height: 60)

                CountdownText(seconds: manager.remainingSeconds)

                Text("until the harbour opens")
                    .font(Theme.sans(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.top, 1)

                GlowProgressBar(progress: manager.progress, animated: !reduceMotion)
                    .frame(height: 5)
                    .padding(.top, 14)

                HStack {
                    if let state = manager.currentState {
                        Text("Started \(shortTime(state.startTime))")
                        Spacer()
                        Text("Ends \(shortTime(state.endTime))")
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }
                .font(Theme.sans(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Theme.navyDeep.opacity(0.35), radius: 10, y: 4)
    }

    private func shortTime(_ d: Date) -> String {
        d.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
    }
}

/// Big serif HH:MM:SS. Digits roll on macOS 14+.
private struct CountdownText: View {
    let seconds: Int

    var body: some View {
        let text = Text(Self.format(seconds))
            .font(Theme.serif(size: 38, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.parchmentWarm)
            .shadow(color: MenuBarIcon.lampColor.opacity(0.18), radius: 10)
            .accessibilityLabel(Self.spoken(seconds))
        if #available(macOS 14, *) {
            text
                .contentTransition(.numericText(countsDown: true))
                .animation(.smooth(duration: 0.35), value: seconds)
        } else {
            text
        }
    }

    static func format(_ s: Int) -> String {
        String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    static func spoken(_ s: Int) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .full
        return (f.string(from: TimeInterval(s)) ?? "") + " remaining"
    }
}

/// Thin track with an amber fill and a glowing head, like a lamp moving
/// along the horizon.
private struct GlowProgressBar: View {
    let progress: Double
    let animated: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let x: CGFloat = max(h, w * CGFloat(progress))
            let head: CGFloat = h + 3
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Theme.amber.opacity(0.75), MenuBarIcon.lampColor],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: x)
                Circle()
                    .fill(MenuBarIcon.lampColor)
                    .frame(width: head, height: head)
                    .shadow(color: MenuBarIcon.lampColor.opacity(0.9), radius: 4)
                    .offset(x: x - head / 2 - 1)
            }
            .animation(animated ? .linear(duration: 1) : nil, value: progress)
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// Stars that twinkle on their own phases plus a lighthouse beam that sweeps
/// around the lamp (foreshortened, as if seen from the sea).
private struct NightSky: View {
    let time: Double

    private struct Star {
        let x: CGFloat, y: CGFloat, r: CGFloat, base: Double, speed: Double, phase: Double
    }

    private static let stars: [Star] = (0..<34).map { i in
        // Deterministic scatter — golden-ratio walk keeps it even but organic.
        let fx = (Double(i) * 0.618_034).truncatingRemainder(dividingBy: 1)
        let fy = (Double(i) * 0.414_214 + 0.13).truncatingRemainder(dividingBy: 1)
        return Star(
            x: CGFloat(fx),
            y: CGFloat(fy * fy),                 // denser near the top
            r: i % 7 == 0 ? 1.1 : (i % 3 == 0 ? 0.8 : 0.6),
            base: 0.25 + Double(i % 5) * 0.12,
            speed: 0.6 + Double(i % 4) * 0.35,
            phase: Double(i) * 1.7
        )
    }

    var body: some View {
        Canvas { ctx, size in
            for s in Self.stars {
                let twinkle = 0.55 + 0.45 * sin(time * s.speed + s.phase)
                let rect = CGRect(x: s.x * size.width - s.r, y: s.y * size.height - s.r,
                                  width: s.r * 2, height: s.r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(s.base * twinkle)))
            }

            // Beam: rotates about the vertical axis; its visible length and
            // brightness follow |cos θ| and it flips side each half turn.
            let lamp = CGPoint(x: size.width / 2, y: 14 + 40 * 0.31)
            let theta = time * 0.45
            let facing = cos(theta)
            let length = size.width * 0.62 * abs(facing)
            guard length > 4 else { return }
            let dir: CGFloat = facing >= 0 ? 1 : -1
            let spread: CGFloat = 5 + 14 * CGFloat(abs(facing))
            var beam = Path()
            beam.move(to: CGPoint(x: lamp.x, y: lamp.y - 1.5))
            beam.addLine(to: CGPoint(x: lamp.x + dir * length, y: lamp.y - spread))
            beam.addLine(to: CGPoint(x: lamp.x + dir * length, y: lamp.y + spread * 0.8))
            beam.addLine(to: CGPoint(x: lamp.x, y: lamp.y + 1.5))
            beam.closeSubpath()
            ctx.fill(beam, with: .linearGradient(
                Gradient(colors: [MenuBarIcon.lampColor.opacity(0.28 * abs(facing)), MenuBarIcon.lampColor.opacity(0)]),
                startPoint: lamp,
                endPoint: CGPoint(x: lamp.x + dir * length, y: lamp.y)
            ))
        }
    }
}

// MARK: - Footer

private struct QuitFooter: View {
    let isActive: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Text("Quit Harbour Control")
                    Spacer()
                    Text("⌘Q").foregroundStyle(.tertiary)
                }
                .font(Theme.sans(size: 12.5))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : .clear)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .onHover { hovering = $0 }

            if isActive {
                Text("The block keeps running after you quit.")
                    .font(Theme.sans(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }
}

// MARK: - Styles

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10.5, weight: .medium))
            configuration.title
        }
    }
}
