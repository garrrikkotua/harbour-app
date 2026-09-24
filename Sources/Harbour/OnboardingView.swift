import SwiftUI

/// First-launch flow: the cinematic intro, then four short steps on a parchment
/// sheet under the night sky. Step 3 ("There is no undo") must be acknowledged
/// before the user can continue.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // HARBOUR_DEMO_STEP (QA only, see DemoMode) opens a step directly.
    @State private var showIntro = DemoMode.onboardingStep == nil
    @State private var introLeaving = false
    @State private var showSteps = DemoMode.onboardingStep != nil
    @State private var sheetShown = false
    @State private var step = DemoMode.onboardingStep ?? 0
    @State private var forward = true
    @State private var acknowledged = false

    static let recoveryURL = URL(string: "https://github.com/garrrikkotua/harbour-app/blob/main/docs/RELEASING.md#recovery")!

    private static let width: CGFloat = 520
    private static let height: CGFloat = 640
    private static let skyHeight: CGFloat = 236

    var body: some View {
        ZStack {
            IntroNightSky(animated: !reduceMotion)

            if showSteps {
                steps
            }

            // The intro stays on top while it fades, then leaves the hierarchy.
            if showIntro {
                IntroView(onGetStarted: beginSteps)
                    // Let the light burst flood under the hidden title bar too.
                    .ignoresSafeArea()
                    .opacity(introLeaving ? 0 : 1)
                    .scaleEffect(introLeaving && !reduceMotion ? 1.03 : 1)
                    .allowsHitTesting(!introLeaving)
                    .disabled(introLeaving)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .background(IntroPalette.skyTop)
    }

    private func beginSteps() {
        guard !introLeaving else { return }
        let fade = reduceMotion ? 0.4 : 0.5
        showSteps = true
        withAnimation(.easeInOut(duration: fade)) { introLeaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.05) { showIntro = false }
    }

    /// Raised from `onAppear` so the sheet is first laid out lowered, then springs up.
    private func raiseSheet() {
        guard !sheetShown else { return }
        let sheet: Animation = reduceMotion
            ? .easeInOut(duration: 0.4)
            : .spring(response: 0.7, dampingFraction: 0.86).delay(0.15)
        withAnimation(sheet) { sheetShown = true }
    }

    // MARK: Steps

    private var steps: some View {
        VStack(spacing: 0) {
            // Night-sky illustration for the current step.
            ZStack {
                illustration(for: step)
                    .id(step)
                    .transition(stepTransition(distance: 24))
            }
            .frame(width: Self.width, height: Self.skyHeight)
            .clipped()
            .opacity(sheetShown ? 1 : 0)

            sheet
                .offset(y: sheetShown ? 0 : (reduceMotion ? 0 : Self.height - Self.skyHeight + 40))
                .opacity(reduceMotion ? (sheetShown ? 1 : 0) : 1)
        }
        .onAppear(perform: raiseSheet)
    }

    private var sheet: some View {
        let s = Self.content[step]
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                stepText(s)
                    .id(step)
                    .transition(stepTransition(distance: 36))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: Self.width, height: Self.height - Self.skyHeight)
        .background(
            TopRoundedRectangle(radius: 26)
                .fill(LinearGradient(colors: [Theme.parchmentWarm, Theme.parchment],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    TopRoundedRectangle(radius: 26)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.8), .clear],
                                               startPoint: .top, endPoint: .center),
                                lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 26, y: -6)
                .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private func stepText(_ s: StepContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(s.eyebrow)
                .font(Theme.sans(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(s.caution ? Theme.amber : Theme.textTertiary)

            Text(s.title)
                .font(Theme.serif(size: 27, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 6)

            if let body = s.body {
                Text(body)
                    .font(Theme.sans(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(s.points.enumerated()), id: \.offset) { i, point in
                    PointRow(point: point, caution: s.caution)
                        .modifier(StaggerIn(index: i, reduceMotion: reduceMotion))
                }
            }
            .padding(.top, 16)

            if s.caution {
                Toggle(isOn: $acknowledged) {
                    Text("I understand Harbour won't let me end a block early.")
                        .font(Theme.sans(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .toggleStyle(AcknowledgeToggleStyle())
                .padding(.top, 16)
                .modifier(StaggerIn(index: s.points.count, reduceMotion: reduceMotion))

                RecoveryFootnote()
                    .padding(.top, 9)
                    .padding(.leading, 2)
                    .modifier(StaggerIn(index: s.points.count + 1, reduceMotion: reduceMotion))
            }
        }
    }

    private var footer: some View {
        let isLast = step == Self.content.count - 1
        let canContinue = !Self.content[step].caution || acknowledged
        return HStack(spacing: 14) {
            PageDots(count: Self.content.count, current: step)

            Spacer()

            Button { go(to: step - 1) } label: {
                Text("Back")
                    .font(Theme.sans(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(height: 38)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .opacity(step == 0 ? 0 : 1)
            .disabled(step == 0)

            Button {
                if isLast { onFinish() } else { go(to: step + 1) }
            } label: {
                HStack(spacing: 7) {
                    Text(isLast ? "Start using Harbour" : "Continue")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .buttonStyle(NightPillButtonStyle(enabled: canContinue))
            .disabled(!canContinue)
            .keyboardShortcut(.defaultAction)
            .animation(.easeOut(duration: 0.25), value: canContinue)
        }
    }

    private func go(to next: Int) {
        guard next >= 0, next < Self.content.count, next != step else { return }
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.25)
            : .spring(response: 0.55, dampingFraction: 0.88)
        let isForward = next > step
        if isForward == forward {
            withAnimation(animation) { step = next }
        } else {
            // Let the new direction reach the outgoing view before it transitions away.
            forward = isForward
            DispatchQueue.main.async { withAnimation(animation) { step = next } }
        }
    }

    private func stepTransition(distance: CGFloat) -> AnyTransition {
        if reduceMotion { return .opacity }
        let d = forward ? distance : -distance
        return .asymmetric(
            insertion: .modifier(active: SlideFade(x: d, opacity: 0), identity: SlideFade(x: 0, opacity: 1)),
            removal: .modifier(active: SlideFade(x: -d, opacity: 0), identity: SlideFade(x: 0, opacity: 1))
        )
    }

    @ViewBuilder
    private func illustration(for step: Int) -> some View {
        switch step {
        case 0: WelcomeIllustration()
        case 1: ChooseIllustration()
        case 2: NoUndoIllustration(acknowledged: acknowledged)
        default: PermissionIllustration()
        }
    }

    // MARK: Copy

    struct StepContent: Sendable {
        let eyebrow: String
        let title: String
        let body: String?
        let points: [Point]
        var caution = false
    }

    struct Point: Sendable {
        let symbol: String
        let text: String
    }

    static let content: [StepContent] = [
        StepContent(
            eyebrow: "WELCOME",
            title: "Welcome to Harbour Control",
            body: "A focus app with no off switch. Choose what pulls you off course, set a timer, and Harbour keeps it out of reach until the time is up.",
            points: [
                Point(symbol: "globe", text: "Blocks websites for the whole Mac, not just one browser."),
                Point(symbol: "square.grid.2x2.fill", text: "Keeps chosen apps closed for the entire session."),
                Point(symbol: "timer", text: "No willpower required. The timer decides when it ends."),
            ]
        ),
        StepContent(
            eyebrow: "HOW IT WORKS",
            title: "Choose what to block",
            body: nil,
            points: [
                Point(symbol: "globe", text: "**Websites.** Type a domain, or add a preset like Social Media or Video & Streaming."),
                Point(symbol: "square.grid.2x2.fill", text: "**Apps.** Pick any app from your Mac. It stays closed while the block runs."),
                Point(symbol: "timer", text: "**Duration.** Anything from 1 minute to 24 hours."),
                Point(symbol: "checkmark.circle.fill", text: "**Start.** Review the summary, confirm, and get to work."),
            ]
        ),
        StepContent(
            eyebrow: "BEFORE YOU START",
            title: "There is no undo",
            body: nil,
            points: [
                Point(symbol: "lock.fill", text: "Once a block starts, it runs until the timer ends."),
                Point(symbol: "power", text: "Quitting, restarting, or deleting the app won't stop it."),
                Point(symbol: "exclamationmark.triangle.fill", text: "Blocked apps close within about a second. Save your work first."),
                Point(symbol: "plus.circle.fill", text: "During a block you can add sites and apps, but never remove them."),
            ],
            caution: true
        ),
        StepContent(
            eyebrow: "ONE LAST THING",
            title: "Your password, once per block",
            body: nil,
            points: [
                Point(symbol: "key.fill", text: "Each time you start a block, macOS asks for an administrator password in its own window."),
                Point(symbol: "lock.shield.fill", text: "That installs the system rules that enforce the block. Your password is never stored."),
                Point(symbol: "menubar.rectangle", text: "While a block runs, the lighthouse in the menu bar shows the time left."),
            ]
        ),
    ]
}

// MARK: - Sheet pieces

private struct PointRow: View {
    let point: OnboardingView.Point
    let caution: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(caution ? OnboardingColors.amberSoft : Theme.amberSoft)
                Image(systemName: point.symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(caution ? Theme.amber : Theme.navy)
            }
            .frame(width: 26, height: 26)

            Text(LocalizedStringKey(point.text))
                .font(Theme.sans(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 26, alignment: .leading)
        }
    }
}

private enum OnboardingColors {
    static let amberSoft = Color(red: 0xf4/255, green: 0xea/255, blue: 0xdb/255)
    static let amberWash = Color(red: 0xfb/255, green: 0xef/255, blue: 0xdc/255)
}

/// Rows fade and rise in one after another when a step appears.
private struct StaggerIn: ViewModifier {
    let index: Int
    let reduceMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45).delay(0.12 + 0.07 * Double(index))) { shown = true }
            }
    }
}

private struct SlideFade: ViewModifier {
    let x: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.offset(x: x).opacity(opacity)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(Theme.navy.opacity(0.18)))
                    .frame(width: i == current ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

private struct NightPillButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        NightPill(label: configuration.label, isPressed: configuration.isPressed, enabled: enabled)
    }
}

/// Separate view so hover state lives in a real view, not in the style.
/// Disabled reads as "waiting" (the same navy, dimmed), not as broken grey;
/// enabling pops it in with a small scale.
private struct NightPill<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var pop: CGFloat = 1

    var body: some View {
        label
            .font(Theme.sans(size: 13.5, weight: .semibold))
            .foregroundStyle(Theme.parchmentWarm.opacity(enabled ? 1 : 0.7))
            .padding(.horizontal, 20)
            .frame(height: 38)
            .background(Capsule().fill(Theme.primaryButton))
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            .opacity(enabled ? 1 : 0.38)
            .shadow(color: Theme.navy.opacity(enabled ? (hovered ? 0.35 : 0.24) : 0), radius: hovered ? 12 : 8, y: 4)
            .brightness(enabled && hovered ? 0.04 : 0)
            .scaleEffect((isPressed ? 0.97 : 1) * pop)
            .animation(.easeOut(duration: 0.14), value: isPressed)
            .animation(.easeOut(duration: 0.18), value: hovered)
            .animation(.easeOut(duration: 0.25), value: enabled)
            .onHover { hovered = $0 }
            .onChange(of: enabled) { isOn in
                guard isOn, !reduceMotion else { return }
                pop = 1.03
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pop = 1 }
            }
    }
}

/// Checkbox card for the "no undo" acknowledgement. The tick draws itself in.
private struct AcknowledgeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(on
                              ? AnyShapeStyle(LinearGradient(colors: [IntroPalette.beam, Theme.amber],
                                                             startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.white))
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(on ? Color.clear : Theme.creamBorder, lineWidth: 1.5)
                    CheckmarkShape()
                        .trim(from: 0, to: on ? 1 : 0)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 10, height: 8)
                }
                .frame(width: 20, height: 20)
                .scaleEffect(on ? 1 : 0.94)
                .shadow(color: IntroPalette.beam.opacity(on ? 0.5 : 0), radius: 6)

                configuration.label
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(on ? OnboardingColors.amberWash : Color.white.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(on ? Theme.amber.opacity(0.45) : Theme.creamBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// The honest version of "no undo": the app has no exit, an administrator
/// does. Quiet on purpose; the recovery path is for malfunctions.
private struct RecoveryFootnote: View {
    private var text: AttributedString {
        var s = AttributedString("No button in Harbour can end a block. If something breaks, an administrator can stop it from Terminal. See the ")
        var link = AttributedString("recovery guide")
        link.link = OnboardingView.recoveryURL
        link.underlineStyle = .single
        s.append(link)
        s.append(AttributedString("."))
        return s
    }

    var body: some View {
        Text(text)
            .font(Theme.sans(size: 11.5))
            .foregroundStyle(Theme.textSecondary)
            .tint(Theme.navy)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Rectangle with only the top corners rounded (UnevenRoundedRectangle is macOS 14+).
private struct TopRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Illustrations

/// Step 1: the lighthouse on its rock, beam sweeping over a gently moving sea.
private struct WelcomeIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let markSize: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let markCentre = CGPoint(x: w / 2, y: h - markSize / 2 - 4)
            let lamp = CGPoint(x: markCentre.x, y: markCentre.y + IntroLighthouse.lampOffset * markSize)

            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let sweep = reduceMotion ? 0 : 0.28 * sin(t * 2 * .pi / 7)
                let breathe = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(t * 2 * .pi / 3.2)

                ZStack {
                    Canvas { ctx, size in
                        drawBeam(ctx, lamp: lamp, angle: sweep, length: size.width * 0.7)
                        drawSea(ctx, size: size, t: reduceMotion ? 0 : t)
                    }
                    .blendMode(.plusLighter)

                    IntroLighthouse(size: markSize, lamp: 0.82 + 0.18 * breathe)
                        .position(markCentre)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func drawBeam(_ ctx: GraphicsContext, lamp: CGPoint, angle: Double, length: Double) {
        for dir in [0.0, Double.pi] {
            let a = angle + dir
            for (half, alpha) in [(0.17, 0.10), (0.11, 0.12), (0.055, 0.16)] {
                var p = Path()
                p.move(to: lamp)
                p.addLine(to: CGPoint(x: lamp.x + cos(a - half) * length, y: lamp.y + sin(a - half) * length))
                p.addLine(to: CGPoint(x: lamp.x + cos(a + half) * length, y: lamp.y + sin(a + half) * length))
                p.closeSubpath()
                let tip = CGPoint(x: lamp.x + cos(a) * length, y: lamp.y + sin(a) * length)
                ctx.fill(p, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: IntroPalette.beam.opacity(alpha * 2.2), location: 0),
                        .init(color: IntroPalette.beam.opacity(alpha * 0.7), location: 0.45),
                        .init(color: .clear, location: 1),
                    ]),
                    startPoint: lamp, endPoint: tip
                ))
            }
        }
    }

    private func drawSea(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        for (i, (y, alpha)) in [(size.height - 16, 0.10), (size.height - 7, 0.16)].enumerated() {
            var p = Path()
            let phase = t * (0.5 + 0.2 * Double(i)) + Double(i)
            p.move(to: CGPoint(x: 0, y: y))
            for x in stride(from: 0.0, through: Double(size.width), by: 6) {
                p.addLine(to: CGPoint(x: x, y: y + 2.2 * sin(x / 34 + phase)))
            }
            ctx.stroke(p, with: .color(Theme.parchment.opacity(alpha)), lineWidth: 1)
        }
    }
}

/// Step 2: websites, apps and a duration dial, bobbing gently like buoys.
private struct ChooseIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .top, spacing: 38) {
                tile(0, t: t, label: "Websites") {
                    GlobeIcon(size: 36, tint: Theme.parchmentWarm)
                }
                tile(1, t: t, label: "Apps") {
                    AppGridIcon(size: 34, tint: IntroPalette.beam)
                }
                tile(2, t: t, label: "1 min – 24 h") {
                    DurationDial(progress: dialProgress(t))
                }
            }
            .offset(y: 8)
        }
        .onAppear { appeared = true }
        .accessibilityHidden(true)
    }

    private func dialProgress(_ t: Double) -> Double {
        if reduceMotion { return 0.62 }
        let phase = (t / 9).truncatingRemainder(dividingBy: 1)
        let tri = phase < 0.5 ? phase * 2 : 2 - phase * 2
        return IntroEase.inOutCubic(tri)
    }

    private func tile<C: View>(_ i: Int, t: Double, label: String, @ViewBuilder content: () -> C) -> some View {
        let bob = reduceMotion ? 0 : 3 * sin(t * 1.3 + Double(i) * 1.1)
        return VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                content()
            }
            .frame(width: 82, height: 82)
            .shadow(color: Color.black.opacity(0.3), radius: 14, y: 8)
            .offset(y: bob)

            Text(label)
                .font(Theme.sans(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.parchment.opacity(0.62))
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 14)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.08 * Double(i) + 0.1), value: appeared)
    }
}

/// Ring dial that sweeps between 1 minute and 24 hours on a log scale.
private struct DurationDial: View {
    let progress: Double

    var body: some View {
        let minutes = Int(exp(log(1440.0) * progress).rounded())
        let label = minutes < 60 ? "\(minutes)m" : "\(Int((Double(minutes) / 60).rounded()))h"
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(
                    LinearGradient(colors: [IntroPalette.beamLight, IntroPalette.beam],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: IntroPalette.beam.opacity(0.6), radius: 4)
            Text(label)
                .font(Theme.mono(size: 11, weight: .semibold))
                .foregroundStyle(Theme.parchmentWarm)
                .monospacedDigit()
        }
        .frame(width: 48, height: 48)
    }
}

/// Step 3: a padlock that clicks shut inside a timer ring. Glows once acknowledged.
private struct NoUndoIllustration: View {
    let acknowledged: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var locked = false
    @State private var ringFill = 0.0
    @State private var pulse = false

    private let ringSize: CGFloat = 132

    var body: some View {
        ZStack {
            // Warm glow behind the lock, brighter once the user acknowledges.
            Circle()
                .fill(IntroPalette.beam.opacity(acknowledged ? 0.3 : 0.12))
                .frame(width: ringSize, height: ringSize)
                .blur(radius: 30)

            // Clock ticks
            ForEach(0..<60, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i % 5 == 0 ? 0.32 : 0.12))
                    .frame(width: 1.5, height: i % 5 == 0 ? 7 : 4)
                    .offset(y: -ringSize / 2 + 2)
                    .rotationEffect(.degrees(Double(i) * 6))
            }

            // Time remaining
            Circle()
                .trim(from: 0, to: ringFill)
                .stroke(
                    LinearGradient(colors: [IntroPalette.beamLight, Theme.amber],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: ringSize - 26, height: ringSize - 26)
                .shadow(color: IntroPalette.beam.opacity(0.55), radius: 5)

            // Click pulse when the shackle closes
            Circle()
                .stroke(IntroPalette.beam.opacity(pulse ? 0 : 0.55), lineWidth: 2)
                .frame(width: 60, height: 60)
                .scaleEffect(pulse ? 1.9 : 0.8)

            Padlock(locked: locked, glowing: acknowledged)
        }
        .offset(y: 10)
        .onAppear {
            if reduceMotion {
                locked = true
                ringFill = 0.72
                pulse = true
                return
            }
            withAnimation(.easeInOut(duration: 1.2).delay(0.1)) { ringFill = 0.72 }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55).delay(0.45)) { locked = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.55)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

private struct Padlock: View {
    let locked: Bool
    let glowing: Bool

    var body: some View {
        ZStack {
            Shackle()
                .stroke(Theme.parchmentWarm, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 22, height: 22)
                .offset(y: locked ? -15 : -24)

            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [Theme.parchmentWarm, IntroPalette.towerShade],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 40, height: 32)
                .offset(y: 5)
                .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)

            // Keyhole
            VStack(spacing: -1) {
                Circle().frame(width: 7, height: 7)
                RoundedRectangle(cornerRadius: 1).frame(width: 3, height: 7)
            }
            .foregroundStyle(glowing ? IntroPalette.beam : Theme.navy.opacity(0.7))
            .shadow(color: IntroPalette.beam.opacity(glowing ? 0.9 : 0), radius: 5)
            .offset(y: 5)
            .animation(.easeInOut(duration: 0.35), value: glowing)
        }
        .frame(width: 60, height: 70)
    }
}

private struct Shackle: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

/// Step 4: the macOS password prompt being filled in, and the lighthouse
/// counting down in a miniature menu bar.
private struct PermissionIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            VStack(spacing: 22) {
                menuBar(t: t)
                authPrompt(t: t)
            }
            .offset(y: 4)
        }
        .accessibilityHidden(true)
    }

    /// The real status item: the same lit image and the same formatter.
    private func menuBar(t: Double) -> some View {
        let remaining = 5048 - Int(t) % 5048
        return HStack(spacing: 14) {
            Spacer()
            HStack(spacing: 2) {
                Image(nsImage: MenuBarIcon.litOnDark)
                Text(MenuBarIcon.compactTime(remaining))
                    .font(Theme.sans(size: 12, weight: .medium))
                    .monospacedDigit()
            }
            Image(systemName: "wifi")
            Image(systemName: "battery.75")
            Image(systemName: "magnifyingglass")
            Text("9:41")
                .font(Theme.sans(size: 11.5, weight: .medium))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.parchmentWarm.opacity(0.9))
        .padding(.horizontal, 14)
        .frame(width: 420, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        )
    }

    private func authPrompt(t: Double) -> some View {
        // 5 s loop: type eight dots, pause, press Allow, clear.
        let phase = reduceMotion ? 3.0 : t.truncatingRemainder(dividingBy: 5)
        let dots = min(8, max(0, Int((phase - 0.4) / 0.18)))
        let allowLit = phase > 2.3 && phase < 4.4

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(OnboardingColors.amberSoft)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.amber)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Harbour Control wants to make changes.")
                        .font(Theme.sans(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Enter an administrator password to allow this.")
                        .font(Theme.sans(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(0..<8, id: \.self) { i in
                            Circle()
                                .fill(Theme.navy)
                                .frame(width: 5, height: 5)
                                .opacity(i < dots ? 1 : 0)
                                .scaleEffect(i < dots ? 1 : 0.4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 126, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.creamBorder, lineWidth: 1))
                    )
                    .animation(.easeOut(duration: 0.12), value: dots)

                    Text("Allow")
                        .font(Theme.sans(size: 10.5, weight: .semibold))
                        .foregroundStyle(allowLit ? Theme.parchmentWarm : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background(
                            Capsule().fill(allowLit ? AnyShapeStyle(Theme.primaryButton) : AnyShapeStyle(Theme.cream))
                        )
                        .animation(.easeInOut(duration: 0.25), value: allowLit)
                }
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.parchmentWarm)
                .shadow(color: Color.black.opacity(0.4), radius: 18, y: 10)
        )
    }
}
