import SwiftUI

// MARK: - Lighthouse

/// Hand-drawn lighthouse SVG-to-SwiftUI. Glows softly when `pulsing` is true.
struct LighthouseIcon: View {
    var size: CGFloat = 120
    var tint: Color = Theme.parchmentWarm
    var beamColor: Color = Theme.amber
    var pulsing: Bool = true

    @State private var pulse = false

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width
            let h = sz.height
            let cx = w / 2

            // Foundation / rocks
            let rock = Path { p in
                p.move(to: CGPoint(x: cx - w*0.32, y: h*0.92))
                p.addQuadCurve(
                    to: CGPoint(x: cx + w*0.32, y: h*0.92),
                    control: CGPoint(x: cx, y: h*0.82)
                )
                p.addLine(to: CGPoint(x: cx + w*0.38, y: h))
                p.addLine(to: CGPoint(x: cx - w*0.38, y: h))
                p.closeSubpath()
            }
            ctx.fill(rock, with: .color(tint.opacity(0.55)))

            // Tower body — tapered
            let tower = Path { p in
                p.move(to: CGPoint(x: cx - w*0.14, y: h*0.87))
                p.addLine(to: CGPoint(x: cx - w*0.09, y: h*0.40))
                p.addLine(to: CGPoint(x: cx + w*0.09, y: h*0.40))
                p.addLine(to: CGPoint(x: cx + w*0.14, y: h*0.87))
                p.closeSubpath()
            }
            ctx.fill(tower, with: .color(tint))

            // Red candy-stripe
            var stripe = Path()
            stripe.addRect(CGRect(x: cx - w*0.115, y: h*0.55, width: w*0.23, height: h*0.06))
            ctx.fill(stripe, with: .color(Theme.danger.opacity(0.75)))

            // Gallery deck
            var gallery = Path()
            gallery.addRect(CGRect(x: cx - w*0.17, y: h*0.36, width: w*0.34, height: h*0.04))
            ctx.fill(gallery, with: .color(tint.opacity(0.95)))

            // Lantern room
            var lantern = Path()
            lantern.addRect(CGRect(x: cx - w*0.11, y: h*0.25, width: w*0.22, height: h*0.11))
            ctx.fill(lantern, with: .color(tint))

            // Glowing bulb
            let glow = Path(ellipseIn: CGRect(
                x: cx - w*0.055, y: h*0.27,
                width: w*0.11, height: h*0.07
            ))
            ctx.fill(glow, with: .color(beamColor))
            ctx.addFilter(.blur(radius: 2))
            ctx.fill(glow, with: .color(beamColor.opacity(0.6)))

            // Roof cap
            let cap = Path { p in
                p.move(to: CGPoint(x: cx - w*0.13, y: h*0.25))
                p.addLine(to: CGPoint(x: cx + w*0.13, y: h*0.25))
                p.addLine(to: CGPoint(x: cx, y: h*0.13))
                p.closeSubpath()
            }
            ctx.fill(cap, with: .color(Theme.danger.opacity(0.9)))

            // Finial
            var finial = Path()
            finial.addRect(CGRect(x: cx - w*0.008, y: h*0.08, width: w*0.016, height: h*0.05))
            ctx.fill(finial, with: .color(tint))
        }
        .frame(width: size, height: size)
        .background(
            Circle()
                .fill(beamColor.opacity(pulse ? 0.25 : 0.08))
                .blur(radius: 24)
                .scaleEffect(pulse ? 1.12 : 1.0)
                .opacity(pulsing ? 1 : 0)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: pulse)
        )
        .onAppear { if pulsing { pulse = true } }
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
