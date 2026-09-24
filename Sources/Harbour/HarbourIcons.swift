import SwiftUI
import AppKit

// MARK: - Lighthouse

/// The brand lighthouse (`IntroLighthouse`'s tower) plus its light: lamp
/// bloom, sweeping beams and the ignition flash.
///
/// Everything is drawn in code so the bundle needs no image assets:
/// - the lamp breathes softly when `pulsing`,
/// - soft layered beams sweep ±16° every 6 s when `sweeping` (like the site),
/// - `ignitedAt` plays the "lamp ignites" moment: the lamp warms up and a
///   bright beam flashes across once before the steady sweep fades in.
/// Reduce Motion (or `animated == false`) freezes it in its lit pose.
struct LighthouseIcon: View {
    var size: CGFloat = 120
    var beamColor: Color = Theme.beam
    /// Lamp glow breathes (3 s cycle).
    var pulsing: Bool = true
    /// Lamp on at all. Off reads as a daytime lighthouse.
    var lit: Bool = true
    /// Rotating beam wedges.
    var sweeping: Bool = false
    /// Length of each beam wedge in multiples of `size`. The beam may draw
    /// well outside the icon's frame; layout size is always `size`.
    var beamReach: CGFloat = 0.5
    /// Start of the ignition sequence; nil means "already lit".
    var ignitedAt: Date? = nil
    /// Master switch — pass false while the window is hidden.
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Total length of the ignition sequence.
    static let ignitionDuration: TimeInterval = 1.6

    private var isLive: Bool {
        guard animated, !reduceMotion, lit else { return false }
        if pulsing || sweeping { return true }
        if let ignitedAt { return Date().timeIntervalSince(ignitedAt) < Self.ignitionDuration }
        return false
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isLive)) { context in
            let frame = Frame(date: context.date, view: self)
            ZStack {
                if lit {
                    beamLayer(frame)
                }
                // Lamp level for the shared tower: breathing and the ignition
                // bloom ride on top of the base brightness.
                IntroLighthouse(size: size, lamp: lit ? min(1.2, frame.lamp * frame.glow) : 0.12)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Animation state

    /// Everything that varies over time, sampled once per frame.
    private struct Frame {
        var lamp: Double = 1          // 0 … 1 lamp brightness
        var glow: Double = 1          // breathing multiplier
        var sweep: Double = 0         // radians
        var steadyBeam: Double = 1    // 0 … 1 alpha of the regular sweep
        var flash: Double = 0         // 0 … 1 alpha of the ignition flash
        var flashAngle: Double = 0    // radians

        init(date: Date, view: LighthouseIcon) {
            let still = view.reduceMotion || !view.animated
            let t = date.timeIntervalSinceReferenceDate
            if !still {
                if view.pulsing { glow = 0.85 + 0.15 * (0.5 + 0.5 * sin(t * 2 * .pi / 3)) }
                if view.sweeping { sweep = (16 * .pi / 180) * sin(t * 2 * .pi / 6) }
            }
            guard !still, let start = view.ignitedAt else { return }
            let e = date.timeIntervalSince(start)
            guard e < LighthouseIcon.ignitionDuration else { return }
            lamp = smoothstep(0.05, 0.5, e)
            steadyBeam = smoothstep(0.95, 1.6, e)
            let p = (e - 0.2) / 0.95
            if p > 0 && p < 1 {
                flash = sin(p * .pi)
                let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
                flashAngle = (-70 + 100 * eased) * .pi / 180
            }
            // A soft bloom as the lamp catches.
            glow *= 1 + 0.5 * max(0, sin(min(1, e / 0.9) * .pi))
        }
    }

    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    // MARK: Layers

    /// Glow + beams, centred on the lamp and allowed to overflow the frame.
    private func beamLayer(_ f: Frame) -> some View {
        let s = size / 120
        let lamp = CGPoint(x: IntroLighthouse.lampPoint.x * s, y: IntroLighthouse.lampPoint.y * s)
        let reach = max(size * 0.7, size * beamReach)
        let side = reach * 2
        let color = beamColor
        let showsSweep = sweeping

        return Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            var ctx = ctx
            // Light adds up like the landing page's beams instead of painting over the sky.
            ctx.blendMode = .plusLighter

            // Lamp bloom
            let r = size * 0.42 * f.glow
            ctx.fill(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(0.42 * f.lamp), color.opacity(0)]),
                    center: c, startRadius: 0, endRadius: r
                )
            )

            /// Three nested wedges per side (wide + faint → narrow + bright),
            /// the same soft beam as the intro and the site.
            func beams(angle: Double, scale: Double, alpha: Double) {
                guard alpha > 0.001 else { return }
                var layer = ctx
                layer.translateBy(x: c.x, y: c.y)
                layer.rotate(by: .radians(angle))
                let L = reach
                for (degrees, a) in [(10.0, 0.10), (6.5, 0.12), (3.2, 0.16)] {
                    let hs = L * CGFloat(tan(degrees * scale * .pi / 180))
                    let k = a * alpha
                    for dir in [CGFloat(1), CGFloat(-1)] {
                        var p = Path()
                        p.move(to: .zero)
                        p.addLine(to: CGPoint(x: dir * L, y: -hs))
                        p.addLine(to: CGPoint(x: dir * L, y: hs))
                        p.closeSubpath()
                        layer.fill(p, with: .linearGradient(
                            Gradient(stops: [
                                .init(color: color.opacity(k * 2.2), location: 0),
                                .init(color: color.opacity(k * 0.7), location: 0.45),
                                .init(color: color.opacity(0), location: 1),
                            ]),
                            startPoint: .zero, endPoint: CGPoint(x: dir * L, y: 0)
                        ))
                    }
                }
            }

            if showsSweep {
                beams(angle: f.sweep, scale: 1, alpha: f.steadyBeam * f.lamp)
            }
            // Ignition flash: the same beam, wider and brighter, crossing once.
            beams(angle: f.flashAngle, scale: 1.8, alpha: 2.2 * f.flash)
        }
        .frame(width: side, height: side)
        .offset(x: lamp.x - size / 2, y: lamp.y - size / 2)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - Night scene: stars + sea

/// Twinkling starfield. Stars are placed deterministically so the sky does
/// not reshuffle between launches; each one has its own period and phase.
struct StarfieldView: View {
    var count: Int = 36
    /// Portion of the height (from the top) that stars occupy.
    var heightFraction: CGFloat = 0.62
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let period: Double
        let phase: Double
        let base: Double
    }

    private var stars: [Star] {
        // Tiny LCG — deterministic, no Foundation randomness.
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<count).map { _ in
            let x = CGFloat(next())
            // Denser near the top, thinning toward the horizon.
            let y = CGFloat(pow(next(), 1.4))
            return Star(
                x: x, y: y,
                radius: 0.6 + CGFloat(next()) * 0.9,
                period: 3 + next() * 3.5,
                phase: next(),
                base: 0.25 + next() * 0.45
            )
        }
    }

    var body: some View {
        let live = animated && !reduceMotion
        let stars = stars
        let heightFraction = heightFraction
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !live)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                for s in stars {
                    let alpha = live
                        ? 0.15 + 0.65 * (0.5 + 0.5 * sin((t / s.period + s.phase) * 2 * .pi))
                        : s.base
                    let r = s.radius
                    let p = CGPoint(x: s.x * sz.width, y: s.y * sz.height * heightFraction)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Two slow swells along the bottom edge with a faint lamp reflection,
/// echoing the site's `.sea`.
struct SeaWavesView: View {
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let live = animated && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { context in
            let t = live ? context.date.timeIntervalSinceReferenceDate : 0
            Canvas { ctx, sz in
                let w = sz.width
                let h = sz.height

                // Warm reflection of the lamp on the water: a flattened radial
                // glow that fades out well before the canvas edges.
                ctx.drawLayer { glow in
                    glow.translateBy(x: w / 2, y: h)
                    glow.scaleBy(x: 1, y: h / (w * 0.5))
                    let r = w * 0.5
                    glow.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .radialGradient(
                        Gradient(colors: [Theme.beam.opacity(0.10), Theme.beam.opacity(0)]),
                        center: .zero, startRadius: 0, endRadius: r
                    ))
                }

                func swell(baseline: CGFloat, amplitude: CGFloat, wavelength: CGFloat,
                           period: Double, direction: Double) -> Path {
                    let shift = CGFloat((t / period).truncatingRemainder(dividingBy: 1) * direction)
                    return Path { p in
                        p.move(to: CGPoint(x: 0, y: h))
                        var x: CGFloat = 0
                        while x <= w + 4 {
                            let y = baseline + amplitude * sin((x / wavelength + shift) * 2 * .pi)
                            p.addLine(to: CGPoint(x: x, y: y))
                            x += 4
                        }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.closeSubpath()
                    }
                }

                let back = swell(baseline: h * 0.45, amplitude: 4, wavelength: 190, period: 34, direction: -1)
                ctx.fill(back, with: .color(Theme.navyDeep.opacity(0.28)))
                ctx.stroke(back, with: .color(.white.opacity(0.05)), lineWidth: 1)

                let front = swell(baseline: h * 0.68, amplitude: 5, wavelength: 140, period: 22, direction: 1)
                ctx.fill(front, with: .color(Theme.navyDeep.opacity(0.45)))
                ctx.stroke(front, with: .color(.white.opacity(0.06)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Window visibility

extension View {
    /// Keeps `isVisible` in sync with the hosting window's occlusion state so
    /// ambient animations can pause while the window is hidden, minimised or
    /// on another Space.
    func trackingWindowVisibility(_ isVisible: Binding<Bool>) -> some View {
        background(WindowOcclusionReader(isVisible: isVisible).frame(width: 0, height: 0))
    }
}

private struct WindowOcclusionReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> OcclusionTrackingView {
        let view = OcclusionTrackingView()
        view.onChange = { visible in
            if isVisible != visible { isVisible = visible }
        }
        return view
    }

    func updateNSView(_ nsView: OcclusionTrackingView, context: Context) {}
}

private final class OcclusionTrackingView: NSView {
    var onChange: ((Bool) -> Void)?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let window else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.report() }
        }
        // Defer: this runs inside a SwiftUI layout pass.
        Task { @MainActor [weak self] in self?.report() }
    }

    private func report() {
        onChange?(window?.occlusionState.contains(.visible) ?? false)
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

// MARK: - Ship's wheel

struct ShipsWheelIcon: View {
    var size: CGFloat = 110
    var tint: Color = Theme.navy

    var body: some View {
        ZStack {
            // Outer rim
            Circle()
                .stroke(tint, lineWidth: 3.5)
                .padding(size * 0.13)
            Circle()
                .stroke(tint.opacity(0.4), lineWidth: 1.5)
                .padding(size * 0.2)

            // 8 spokes + handles
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * (.pi / 4)
                let cx = size / 2
                let cy = size / 2
                let inner: CGFloat = size * 0.06
                let outer: CGFloat = size * 0.37
                let handleStart: CGFloat = size * 0.42
                let handleEnd: CGFloat = size * 0.48

                // Spoke
                Path { p in
                    p.move(to: CGPoint(
                        x: cx + CGFloat(cos(angle)) * inner,
                        y: cy + CGFloat(sin(angle)) * inner
                    ))
                    p.addLine(to: CGPoint(
                        x: cx + CGFloat(cos(angle)) * outer,
                        y: cy + CGFloat(sin(angle)) * outer
                    ))
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // Handle grip
                Path { p in
                    p.move(to: CGPoint(
                        x: cx + CGFloat(cos(angle)) * handleStart,
                        y: cy + CGFloat(sin(angle)) * handleStart
                    ))
                    p.addLine(to: CGPoint(
                        x: cx + CGFloat(cos(angle)) * handleEnd,
                        y: cy + CGFloat(sin(angle)) * handleEnd
                    ))
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // End cap
                Circle()
                    .fill(tint)
                    .frame(width: size * 0.045, height: size * 0.045)
                    .position(
                        x: cx + CGFloat(cos(angle)) * handleEnd,
                        y: cy + CGFloat(sin(angle)) * handleEnd
                    )
            }

            // Hub
            Circle().fill(tint).frame(width: size * 0.13, height: size * 0.13)
            Circle().fill(Theme.parchment).frame(width: size * 0.04, height: size * 0.04)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Globe tile + App-grid tile (onboarding step 2)

struct GlobeIcon: View {
    var size: CGFloat = 38
    var tint: Color = Theme.navy

    var body: some View {
        Canvas { ctx, sz in
            let cx = sz.width / 2
            let cy = sz.height / 2
            let r = min(sz.width, sz.height) * 0.38

            // Outer circle
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r*2, height: r*2)),
                       with: .color(tint), lineWidth: 1.8)

            // Vertical meridian ellipse
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - r*0.4, y: cy - r, width: r*0.8, height: r*2)),
                       with: .color(tint), lineWidth: 1.3)

            // Equator
            var eq = Path()
            eq.move(to: CGPoint(x: cx - r, y: cy))
            eq.addLine(to: CGPoint(x: cx + r, y: cy))
            ctx.stroke(eq, with: .color(tint), lineWidth: 1.3)

            // Tropics
            var t1 = Path()
            t1.move(to: CGPoint(x: cx - r*0.85, y: cy - r*0.55))
            t1.addLine(to: CGPoint(x: cx + r*0.85, y: cy - r*0.55))
            ctx.stroke(t1, with: .color(tint.opacity(0.7)), lineWidth: 1.1)

            var t2 = Path()
            t2.move(to: CGPoint(x: cx - r*0.85, y: cy + r*0.55))
            t2.addLine(to: CGPoint(x: cx + r*0.85, y: cy + r*0.55))
            ctx.stroke(t2, with: .color(tint.opacity(0.7)), lineWidth: 1.1)
        }
        .frame(width: size, height: size)
    }
}

struct AppGridIcon: View {
    var size: CGFloat = 38
    var tint: Color = Theme.amber

    var body: some View {
        let s = size * 0.32
        let gap = size * 0.08
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                RoundedRectangle(cornerRadius: 3).stroke(tint, lineWidth: 1.8).frame(width: s, height: s)
                RoundedRectangle(cornerRadius: 3).stroke(tint, lineWidth: 1.8).frame(width: s, height: s)
            }
            HStack(spacing: gap) {
                RoundedRectangle(cornerRadius: 3).stroke(tint, lineWidth: 1.8).frame(width: s, height: s)
                RoundedRectangle(cornerRadius: 3).stroke(tint, lineWidth: 1.8).frame(width: s, height: s)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Soft-tinted rounded tile used in onboarding step 2.
struct IconTile<Content: View>: View {
    var color: Color
    var soft: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(soft)
                .shadow(color: color.opacity(0.18), radius: 12, y: 8)
            content()
                .foregroundStyle(color)
        }
        .frame(width: 72, height: 72)
    }
}
