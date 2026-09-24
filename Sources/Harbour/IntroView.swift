import SwiftUI

// MARK: - Palette

/// Night-scene colours shared by the intro and the onboarding steps.
/// Mirrors the landing page (site/index.html): `--beam` is the lamp glow.
enum IntroPalette {
    static let beam      = Color(red: 0xf2/255, green: 0xb2/255, blue: 0x4a/255)
    static let beamLight = Color(red: 0xff/255, green: 0xd9/255, blue: 0x8f/255)
    static let lampCore  = Color(red: 0xff/255, green: 0xf6/255, blue: 0xe0/255)
    static let skyTop    = Color(red: 0x06/255, green: 0x0a/255, blue: 0x14/255)
    static let towerShade = Color(red: 0xe2/255, green: 0xd9/255, blue: 0xc6/255)
}

// MARK: - Intro

/// First-launch intro, Harbour's take on a "first light" reveal:
/// stars fade in, the lamp ignites, bursts into rays that flood the window,
/// the light collapses back into a lighthouse, the wordmark slides in beside it,
/// then the tagline and a glowing "Get started" pill.
///
/// Every frame is a pure function of elapsed time, so skipping (click / Return)
/// just moves the clock to the end state. Reduce Motion gets a plain fade.
struct IntroView: View {
    var onGetStarted: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var foreground: Double = 1
    @State private var wordmarkWidth: CGFloat = 250
    @State private var ctaHovered = false

    /// Seconds until the scene is fully settled (CTA visible).
    static let duration: Double = 4.8

    private let markSize: CGFloat = 84
    /// Negative: the mark's canvas has transparent side padding, so this
    /// still leaves a visible gap of ~36 pt between tower and wordmark.
    private let lockupGap: CGFloat = -10

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
                let t = DemoMode.introTime ?? (reduceMotion
                    ? Self.duration + 1
                    : start.map { max(0, timeline.date.timeIntervalSince($0)) } ?? 0)
                scene(motion: IntroMotion(t: t, reduceMotion: reduceMotion), size: geo.size)
            }
        }
        .background(IntroPalette.skyTop)
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .onAppear {
            if reduceMotion {
                // Straight to the settled scene, faded in.
                start = Date().addingTimeInterval(-Self.duration - 1)
                foreground = 0
                withAnimation(.easeInOut(duration: 0.8)) { foreground = 1 }
            } else {
                start = Date()
            }
        }
    }

    private var isSettled: Bool {
        guard let start else { return false }
        return Date().timeIntervalSince(start) >= Self.duration - 0.6
    }

    /// Jump to the end state with a short fade so the cut never feels abrupt.
    private func skip() {
        guard !isSettled else { return }
        start = Date().addingTimeInterval(-Self.duration)
        foreground = 0
        withAnimation(.easeOut(duration: 0.45)) { foreground = 1 }
    }

    private func primaryAction() {
        if isSettled { onGetStarted() } else { skip() }
    }

    // MARK: Scene

    @ViewBuilder
    private func scene(motion m: IntroMotion, size: CGSize) -> some View {
        let cx = size.width / 2
        let cy = size.height * 0.42
        let slide = CGFloat(m.slide)
        let scale: CGFloat = 1.22 - 0.22 * slide
        // Mark starts centred, then shifts left to make room for the wordmark.
        let markX = cx - (lockupGap + wordmarkWidth) / 2 * slide
        let lamp = CGPoint(x: markX, y: cy + IntroLighthouse.lampOffset * markSize * scale)

        ZStack {
            IntroNightSky(starOpacity: m.stars, animated: !reduceMotion)

            // Flood: painted normally so the navy doesn't tint the light.
            Canvas { ctx, sz in
                IntroLight.drawFlood(in: ctx, size: sz, lamp: lamp, motion: m)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // Light: spark, rays, idle beam. Additive over the sky.
            Canvas { ctx, sz in
                IntroLight.draw(in: ctx, size: sz, lamp: lamp, motion: m)
            }
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            IntroLighthouse(size: markSize, lamp: m.lamp)
                .mask(
                    // Lit from the lamp downward as the light collapses into it.
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: max(0, m.markReveal * 1.3 - 0.3)),
                            .init(color: .clear, location: max(0.001, m.markReveal * 1.3)),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .opacity(m.markOpacity)
                .scaleEffect(scale)
                .position(x: markX, y: cy)
                .accessibilityHidden(true)

            Text("Harbour Control")
                .font(Theme.serif(size: 34, weight: .bold))
                .foregroundStyle(Theme.parchmentWarm)
                .fixedSize()
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: WordmarkWidthKey.self, value: g.size.width)
                    }
                )
                // Revealed left to right, as if emerging from behind the tower.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: max(0, m.slide * 1.25 - 0.25)),
                            .init(color: .clear, location: max(0.001, m.slide * 1.25)),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .opacity(IntroEase.out(max(0, (m.slide - 0.35) / 0.65)))
                .blur(radius: 4 * (1 - m.slide))
                .offset(x: 26 * (1 - m.slide))
                .position(x: cx + (markSize + lockupGap) / 2, y: cy + 4)

            Text("Drop anchor. Get to work.")
                .font(Theme.serif(size: 17, weight: .regular).italic())
                .foregroundStyle(Theme.parchment.opacity(0.62))
                .fixedSize()
                .opacity(m.tagline)
                .offset(y: 8 * (1 - m.tagline))
                .position(x: cx, y: cy + 74)

            ctaButton(motion: m)
                .position(x: cx, y: cy + 148)
        }
        .opacity(foreground)
        .onPreferenceChange(WordmarkWidthKey.self) { wordmarkWidth = $0 }
    }

    private func ctaButton(motion m: IntroMotion) -> some View {
        Button(action: primaryAction) {
            HStack(spacing: 8) {
                Text("Get started")
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .offset(x: ctaHovered ? 3 : 0)
            }
            .font(Theme.sans(size: 15, weight: .semibold))
            .foregroundStyle(Theme.navyDeep)
            .padding(.horizontal, 30)
            .frame(height: 44)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [IntroPalette.beamLight, IntroPalette.beam],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    .blendMode(.overlay)
            )
            .brightness(ctaHovered ? 0.05 : 0)
            // Breathing glow, like the lamp.
            .shadow(color: IntroPalette.beam.opacity(0.5 * m.cta), radius: 14 + 8 * m.breathe)
            .shadow(color: IntroPalette.beam.opacity(0.25 * m.cta), radius: 34 + 10 * m.breathe)
        }
        .buttonStyle(IntroPillButtonStyle())
        .keyboardShortcut(.defaultAction)
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { ctaHovered = h } }
        .opacity(m.cta)
        .scaleEffect(0.94 + 0.06 * m.cta)
        .offset(y: 10 * (1 - m.cta))
        .accessibilityLabel("Get started")
    }
}

private struct WordmarkWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 250
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct IntroPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Timeline

/// All intro progress values for a given elapsed time `t`, each eased into 0...1.
struct IntroMotion {
    let t: Double
    let stars: Double
    let spark: Double
    let burst: Double
    let collapse: Double
    let markReveal: Double
    let markOpacity: Double
    let slide: Double
    let tagline: Double
    let cta: Double
    let beam: Double
    /// Beam angle in radians, sweeping ±16° like the landing page.
    let sweep: Double
    /// Slow 0...1 breathing used by the lamp and the CTA glow.
    let breathe: Double
    let lamp: Double

    init(t: Double, reduceMotion: Bool) {
        self.t = t
        stars       = IntroEase.inOut(Self.progress(t, 0.0, 1.6))
        spark       = IntroEase.out(Self.progress(t, 0.5, 0.55))
        burst       = IntroEase.outCubic(Self.progress(t, 1.05, 0.8))
        collapse    = IntroEase.inOutCubic(Self.progress(t, 2.05, 0.75))
        markReveal  = IntroEase.out(Self.progress(t, 2.3, 0.8))
        markOpacity = IntroEase.out(Self.progress(t, 2.25, 0.45))
        slide       = IntroEase.inOutCubic(Self.progress(t, 3.0, 0.85))
        tagline     = IntroEase.out(Self.progress(t, 3.7, 0.7))
        cta         = IntroEase.out(Self.progress(t, 4.1, 0.7))
        beam        = IntroEase.inOut(Self.progress(t, 3.2, 1.4))

        let idle = max(0, t - 3.2)
        // Tilted up so the right-hand beam passes above the wordmark.
        sweep   = reduceMotion ? -0.26 : -0.26 + 0.14 * sin(idle * 2 * .pi / 7)
        breathe = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(t * 2 * .pi / 3.2)
        lamp    = 0.82 + 0.18 * breathe
    }

    private static func progress(_ t: Double, _ start: Double, _ duration: Double) -> Double {
        min(1, max(0, (t - start) / duration))
    }
}

enum IntroEase {
    static func out(_ x: Double) -> Double { 1 - (1 - x) * (1 - x) }
    static func inOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
    static func outCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func inOutCubic(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
}

// MARK: - Light

/// Draws the spark, the burst of rays, the window-filling flood and the idle beam.
private enum IntroLight {
    struct Ray: Sendable {
        let angle: Double
        let halfWidth: Double
        let length: Double
    }

    static let rays: [Ray] = {
        var rng = IntroRandom(seed: 0x4841_5242_4f55_52)
        let count = 34
        return (0..<count).map { i in
            Ray(
                angle: Double(i) / Double(count) * 2 * .pi + (rng.next() - 0.5) * 0.12,
                halfWidth: 0.012 + rng.next() * 0.03,
                length: 0.55 + rng.next() * 0.45
            )
        }
    }()

    /// Flood: warm, near-white light filling the window at the peak of the burst.
    static func drawFlood(in ctx: GraphicsContext, size: CGSize, lamp: CGPoint, motion m: IntroMotion) {
        let reach = m.burst * (1 - m.collapse)
        guard reach > 0.001 else { return }
        let maxLen = hypot(size.width, size.height) * 1.15
        let a = 0.95 * pow(reach, 0.8)
        // While collapsing, the edges go dark first so the light retreats into
        // the lamp instead of dimming evenly into a brown wash (a radial
        // gradient pads the whole window with its last stop).
        let edge = pow(1 - m.collapse, 2)
        let flood = Gradient(stops: [
            .init(color: IntroPalette.lampCore.opacity(a), location: 0),
            .init(color: IntroPalette.lampCore.opacity(0.95 * a), location: 0.18),
            .init(color: IntroPalette.beamLight.opacity(0.9 * a * (1 - 0.5 * m.collapse)), location: 0.5),
            .init(color: IntroPalette.beamLight.opacity(0.8 * a * edge), location: 1),
        ])
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(flood, center: lamp, startRadius: 0,
                                  endRadius: max(1, maxLen * max(0.05, reach)))
        )
    }

    static func draw(in ctx: GraphicsContext, size: CGSize, lamp: CGPoint, motion m: IntroMotion) {
        let reach = m.burst * (1 - m.collapse)
        let maxLen = hypot(size.width, size.height) * 1.15

        if reach > 0.001 {
            // Rays: each drawn twice (wide + faint, narrow + bright) for soft streaks.
            let rotation = m.t * 0.22
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.5))
                for ray in rays {
                    let length = maxLen * reach * ray.length
                    let angle = ray.angle + rotation
                    for (widen, alpha) in [(1.9, 0.35), (1.0, 0.9)] {
                        let half = ray.halfWidth * widen * (0.6 + 0.4 * m.burst)
                        var p = Path()
                        p.move(to: lamp)
                        p.addLine(to: point(lamp, angle - half, length))
                        p.addLine(to: point(lamp, angle + half, length))
                        p.closeSubpath()
                        let g = Gradient(stops: [
                            .init(color: IntroPalette.lampCore.opacity(alpha * reach), location: 0),
                            .init(color: IntroPalette.beam.opacity(0.75 * alpha * reach), location: 0.3),
                            .init(color: Theme.amber.opacity(0.3 * alpha * reach), location: 0.7),
                            .init(color: .clear, location: 1),
                        ])
                        layer.fill(p, with: .radialGradient(g, center: lamp, startRadius: 0, endRadius: max(1, length)))
                    }
                }
            }

            // Shock ring as the burst leaves the lamp: a soft warm wave, thinning out.
            let ringR = 16 + 320 * m.burst
            let ring = Path(ellipseIn: CGRect(x: lamp.x - ringR, y: lamp.y - ringR, width: ringR * 2, height: ringR * 2))
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 1.5))
                layer.stroke(ring, with: .color(IntroPalette.beamLight.opacity(0.6 * (1 - m.burst))),
                             lineWidth: 3 * (1 - m.burst) + 0.5)
            }
        }

        // Idle beam: two soft wedges sweeping slowly from the lamp.
        if m.beam > 0.001 {
            // Softer once the wordmark is in, so the light never competes with it.
            let dim = 1 - 0.4 * m.slide
            let length = max(size.width, size.height) * 0.95
            for dir in [0.0, Double.pi] {
                let angle = m.sweep + dir
                for (half, alpha) in [(0.17, 0.10), (0.11, 0.12), (0.055, 0.16)] {
                    var p = Path()
                    p.move(to: lamp)
                    p.addLine(to: point(lamp, angle - half, length))
                    p.addLine(to: point(lamp, angle + half, length))
                    p.closeSubpath()
                    let g = Gradient(stops: [
                        .init(color: IntroPalette.beam.opacity(alpha * 2.2 * m.beam * dim), location: 0),
                        .init(color: IntroPalette.beam.opacity(alpha * 0.7 * m.beam * dim), location: 0.45),
                        .init(color: .clear, location: 1),
                    ])
                    ctx.fill(p, with: .linearGradient(g, startPoint: lamp, endPoint: point(lamp, angle, length)))
                }
            }
        }

        // Spark / lamp halo. Flickers while igniting, then breathes.
        if m.spark > 0.001 {
            let flicker = m.spark < 1 ? 0.78 + 0.22 * sin(m.t * 47) : 1
            let r = (6 + 26 * m.spark + 60 * reach) * (0.92 + 0.08 * m.breathe)
            let halo = Gradient(stops: [
                .init(color: IntroPalette.lampCore.opacity(0.95 * m.spark * flicker), location: 0),
                .init(color: IntroPalette.beam.opacity(0.75 * m.spark * flicker), location: 0.22),
                .init(color: Theme.amber.opacity(0.22 * m.spark), location: 0.6),
                .init(color: .clear, location: 1),
            ])
            ctx.fill(
                Path(ellipseIn: CGRect(x: lamp.x - r, y: lamp.y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(halo, center: lamp, startRadius: 0, endRadius: r)
            )
            let core = 1.4 + 2.2 * m.spark
            ctx.fill(
                Path(ellipseIn: CGRect(x: lamp.x - core, y: lamp.y - core, width: core * 2, height: core * 2)),
                with: .color(IntroPalette.lampCore.opacity(m.spark * flicker))
            )
        }
    }

    private static func point(_ origin: CGPoint, _ angle: Double, _ length: Double) -> CGPoint {
        CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length)
    }
}

// MARK: - Night sky

/// Deep navy sky with a deterministic, gently twinkling starfield.
/// Shared by the intro and onboarding so the hand-off between them is seamless.
struct IntroNightSky: View {
    var starOpacity: Double = 1
    var animated: Bool = true

    struct Star: Sendable {
        let x: Double
        let y: Double
        let radius: Double
        let brightness: Double
        let speed: Double
        let phase: Double
    }

    static let stars: [Star] = {
        var rng = IntroRandom(seed: 0x5354_4152_53)
        return (0..<90).map { _ in
            Star(
                x: rng.next(),
                // Denser towards the top of the sky.
                y: pow(rng.next(), 1.5) * 0.92,
                radius: 0.5 + pow(rng.next(), 3) * 1.2,
                brightness: 0.25 + rng.next() * 0.65,
                speed: 0.6 + rng.next() * 1.4,
                phase: rng.next() * 2 * .pi
            )
        }
    }()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [IntroPalette.skyTop, Theme.navyDeep, Theme.navy],
                startPoint: .top, endPoint: .bottom
            )
            // Faint horizon haze.
            RadialGradient(
                colors: [Theme.navyLight.opacity(0.45), .clear],
                center: UnitPoint(x: 0.5, y: 1.1), startRadius: 0, endRadius: 420
            )
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    for star in Self.stars {
                        let twinkle = animated ? 0.6 + 0.4 * sin(time * star.speed + star.phase) : 0.8
                        let alpha = star.brightness * twinkle
                        let c = CGPoint(x: star.x * size.width, y: star.y * size.height)
                        if star.radius > 1.2 {
                            let r = star.radius * 4
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                with: .radialGradient(
                                    Gradient(colors: [Color.white.opacity(0.25 * alpha), .clear]),
                                    center: c, startRadius: 0, endRadius: r
                                )
                            )
                        }
                        let r = star.radius
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                            with: .color(Color.white.opacity(alpha))
                        )
                    }
                }
            }
            .opacity(starOpacity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Lighthouse mark

/// Crisp lighthouse mark drawn from the landing page's 120×120 SVG, with a domed
/// lantern and dark glass so the lamp reads as light rather than paint.
///
/// This is the one tower used everywhere (intro, onboarding, setup tile,
/// active session, confirm and FAQ badges); `LighthouseIcon` only adds beams
/// on top. `lamp` animates, so a change can be wrapped in `withAnimation`.
struct IntroLighthouse: View, Animatable {
    var size: CGFloat = 84
    /// 0 = dark lantern, 1 = fully lit.
    var lamp: Double = 1

    var animatableData: Double {
        get { lamp }
        set { lamp = newValue }
    }

    /// Lamp centre relative to the view centre, as a fraction of `size` (y axis).
    static let lampOffset: CGFloat = (36.5 - 60) / 120
    /// Lamp centre on the 120 grid.
    static let lampPoint = CGPoint(x: 60, y: 36.5)

    var body: some View {
        let lamp = lamp
        Canvas { ctx, sz in
            Self.draw(in: ctx, width: sz.width, lamp: lamp)
        }
        .frame(width: size, height: size)
    }

    /// Draws the tower into a square of side `width` at the context origin.
    static func draw(in ctx: GraphicsContext, width: CGFloat, lamp: Double) {
        let k = width / 120
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * k, y: y * k, width: w * k, height: h * k)
        }

        // Rocks
        var rock = Path()
        rock.move(to: pt(28, 113))
        rock.addQuadCurve(to: pt(92, 113), control: pt(60, 99))
        rock.addLine(to: pt(98, 118))
        rock.addLine(to: pt(22, 118))
        rock.closeSubpath()
        ctx.fill(rock, with: .color(Theme.navyLight))

        // Tower, shaded left-to-right for a little volume
        var tower = Path()
        tower.move(to: pt(49, 53))
        tower.addLine(to: pt(71, 53))
        tower.addLine(to: pt(74, 108))
        tower.addLine(to: pt(46, 108))
        tower.closeSubpath()
        ctx.fill(tower, with: .linearGradient(
            Gradient(colors: [Theme.parchmentWarm, IntroPalette.towerShade]),
            startPoint: pt(52, 0), endPoint: pt(74, 0)
        ))

        // Bands, window and door, clipped to the tower
        ctx.drawLayer { layer in
            layer.clip(to: tower)
            layer.fill(Path(rect(40, 68, 40, 5)), with: .color(Theme.navy.opacity(0.28)))
            layer.fill(Path(rect(40, 86, 40, 5)), with: .color(Theme.navy.opacity(0.28)))
            layer.fill(Path(roundedRect: rect(58.4, 58, 3.2, 5.5), cornerRadius: 1.4 * k),
                       with: .color(Theme.navy.opacity(0.35)))
            layer.fill(Path(roundedRect: rect(56.5, 97, 7, 11), cornerRadius: 3.5 * k),
                       with: .color(Theme.navy.opacity(0.4)))
        }

        // Gallery deck
        ctx.fill(Path(roundedRect: rect(42, 46, 36, 7), cornerRadius: 1.5 * k),
                 with: .color(Theme.parchmentWarm))
        ctx.fill(Path(rect(44, 51.5, 32, 1.5)), with: .color(Theme.navy.opacity(0.18)))

        // Lantern frame + dark glass
        ctx.fill(Path(roundedRect: rect(48, 26, 24, 20), cornerRadius: 2 * k),
                 with: .color(Theme.parchmentWarm))
        let glass = Path(roundedRect: rect(51, 28.5, 18, 15.5), cornerRadius: 1.5 * k)
        ctx.fill(glass, with: .color(Theme.navyDeep))

        // Lamp light inside the glass
        let lampCentre = pt(lampPoint.x, lampPoint.y)
        ctx.fill(glass, with: .radialGradient(
            Gradient(colors: [IntroPalette.beam.opacity(0.9 * lamp), Theme.amber.opacity(0.35 * lamp)]),
            center: lampCentre, startRadius: 0, endRadius: 12 * k
        ))
        ctx.fill(Path(ellipseIn: rect(55.5, 32, 9, 9)), with: .color(IntroPalette.beam.opacity(0.4 + 0.6 * lamp)))
        ctx.fill(Path(ellipseIn: rect(58, 34.5, 4, 4)), with: .color(IntroPalette.lampCore.opacity(0.5 + 0.5 * lamp)))

        // Dome + finial
        var dome = Path()
        dome.move(to: pt(46, 27))
        dome.addQuadCurve(to: pt(74, 27), control: pt(60, 11))
        dome.closeSubpath()
        ctx.fill(dome, with: .color(Theme.parchmentWarm))
        ctx.fill(Path(rect(59.2, 13, 1.6, 7)), with: .color(Theme.parchmentWarm))
        ctx.fill(Path(ellipseIn: rect(58.3, 11, 3.4, 3.4)), with: .color(Theme.parchmentWarm))

        // Soft halo spilling out of the lantern
        var glow = ctx
        glow.blendMode = .plusLighter
        let r = 24 * k
        glow.fill(
            Path(ellipseIn: CGRect(x: lampCentre.x - r, y: lampCentre.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(colors: [IntroPalette.beam.opacity(0.45 * lamp), .clear]),
                center: lampCentre, startRadius: 4 * k, endRadius: r
            )
        )
    }
}

// MARK: - Deterministic randomness

/// Small LCG so star and ray layouts are identical on every launch and every view.
struct IntroRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}
