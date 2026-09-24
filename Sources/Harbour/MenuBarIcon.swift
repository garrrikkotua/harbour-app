import SwiftUI
import AppKit

// MARK: - Lighthouse glyph geometry

/// A small, flat lighthouse silhouette designed to stay legible at 16–18 pt.
/// One source of truth for the menu bar image (via `cgPath`) and the SwiftUI
/// glyph in the popover, so both read as the same mark.
///
/// All coordinates are fractions of the tower rect (aspect ~0.62:1). The lamp
/// window is punched out of the lantern so an unlit lighthouse reads as
/// "dark", and the lit state simply fills that window with light.
enum LighthouseGlyphGeometry {
    /// Width / height of the tower rect.
    static let aspect: CGFloat = 0.62

    /// Tower, gallery, lantern frame, cap and finial, with the lamp window and
    /// a single stripe cut out. Fill with even-odd.
    static func body(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
        }
        // Tower edge x at a given y (trapezoid from y 0.45 to 0.93).
        func left(_ y: CGFloat) -> CGFloat { 0.30 - (y - 0.45) / 0.48 * 0.12 }
        func right(_ y: CGFloat) -> CGFloat { 1 - left(y) }

        var path = Path()

        // Ground
        path.addRoundedRect(
            in: CGRect(origin: p(0.04, 0.93), size: CGSize(width: r.width * 0.92, height: r.height * 0.07)),
            cornerSize: CGSize(width: r.width * 0.035, height: r.width * 0.035)
        )

        // Tower (trapezoid) with a stripe cut out of it
        path.move(to: p(left(0.93), 0.93))
        path.addLine(to: p(left(0.45), 0.45))
        path.addLine(to: p(right(0.45), 0.45))
        path.addLine(to: p(right(0.93), 0.93))
        path.closeSubpath()

        let s0: CGFloat = 0.61, s1: CGFloat = 0.68
        path.move(to: p(left(s0), s0))
        path.addLine(to: p(right(s0), s0))
        path.addLine(to: p(right(s1), s1))
        path.addLine(to: p(left(s1), s1))
        path.closeSubpath()

        // Gallery deck
        path.addRect(CGRect(origin: p(0.12, 0.395), size: CGSize(width: r.width * 0.76, height: r.height * 0.06)))

        // Lantern frame, window punched out (even-odd)
        path.addRect(CGRect(origin: p(0.25, 0.225), size: CGSize(width: r.width * 0.50, height: r.height * 0.17)))
        path.addRect(windowRect(in: r))

        // Cap
        path.move(to: p(0.16, 0.235))
        path.addLine(to: p(0.84, 0.235))
        path.addLine(to: p(0.50, 0.075))
        path.closeSubpath()

        // Finial
        let fr = r.width * 0.055
        path.addEllipse(in: CGRect(x: r.midX - fr, y: r.minY + r.height * 0.045 - fr, width: fr * 2, height: fr * 2))

        return path
    }

    static func windowRect(in r: CGRect) -> CGRect {
        CGRect(x: r.minX + r.width * 0.35, y: r.minY + r.height * 0.255,
               width: r.width * 0.30, height: r.height * 0.11)
    }

    /// The lamp itself: fills the lantern window.
    static func lamp(in r: CGRect) -> Path {
        Path(windowRect(in: r).insetBy(dx: -r.width * 0.01, dy: -r.height * 0.005))
    }

    static func lampCenter(in r: CGRect) -> CGPoint {
        let w = windowRect(in: r)
        return CGPoint(x: w.midX, y: w.midY)
    }

    /// Two tapered beams leaving the lantern to the left and right, reaching
    /// `reach` points past the tower rect.
    static func beams(in r: CGRect, reach: CGFloat) -> Path {
        let c = lampCenter(in: r)
        let w = windowRect(in: r)
        let spread = r.height * 0.13
        var path = Path()
        for dir in [-1.0, 1.0] as [CGFloat] {
            let startX = dir < 0 ? r.minX + r.width * 0.2 : r.maxX - r.width * 0.2
            let endX = dir < 0 ? r.minX - reach : r.maxX + reach
            path.move(to: CGPoint(x: startX, y: c.y - w.height * 0.28))
            path.addLine(to: CGPoint(x: endX, y: c.y - spread))
            path.addLine(to: CGPoint(x: endX, y: c.y + spread * 0.7))
            path.addLine(to: CGPoint(x: startX, y: c.y + w.height * 0.28))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - SwiftUI glyph

/// The same lighthouse mark as the menu bar icon, for use inside the popover.
struct LighthouseGlyph: View {
    var height: CGFloat = 40
    var lit: Bool = false
    var tint: Color = Theme.navy
    var lampColor: Color = MenuBarIcon.lampColor
    /// Beam/glow intensity, 0...1. Drive it from a TimelineView for a slow pulse.
    var glow: Double = 1
    /// Unlit only: a faint lamp left burning in the lantern window (0...1),
    /// so "quiet" still reads as a lighthouse rather than a hole.
    var ember: Double = 0

    var body: some View {
        Canvas { ctx, size in
            let rh = size.height
            let rw = rh * LighthouseGlyphGeometry.aspect
            let r = CGRect(x: (size.width - rw) / 2, y: 0, width: rw, height: rh)

            if lit {
                let c = LighthouseGlyphGeometry.lampCenter(in: r)
                // Halo
                let haloR = rh * 0.42
                ctx.fill(
                    Path(ellipseIn: CGRect(x: c.x - haloR, y: c.y - haloR, width: haloR * 2, height: haloR * 2)),
                    with: .radialGradient(
                        Gradient(colors: [lampColor.opacity(0.55 * glow), lampColor.opacity(0)]),
                        center: c, startRadius: 0, endRadius: haloR
                    )
                )
                // Beams
                let reach = (size.width - rw) / 2
                ctx.fill(
                    LighthouseGlyphGeometry.beams(in: r, reach: reach),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: lampColor.opacity(0.0), location: 0),
                            .init(color: lampColor.opacity(0.35 * glow), location: 0.38),
                            .init(color: lampColor.opacity(0.35 * glow), location: 0.62),
                            .init(color: lampColor.opacity(0.0), location: 1),
                        ]),
                        startPoint: CGPoint(x: 0, y: c.y),
                        endPoint: CGPoint(x: size.width, y: c.y)
                    )
                )
                ctx.fill(LighthouseGlyphGeometry.lamp(in: r), with: .color(lampColor))
            } else if ember > 0 {
                ctx.fill(LighthouseGlyphGeometry.lamp(in: r), with: .color(lampColor.opacity(ember)))
            }
            ctx.fill(LighthouseGlyphGeometry.body(in: r), with: .color(tint), style: FillStyle(eoFill: true))
        }
        .frame(width: lit ? height * 1.9 : height * LighthouseGlyphGeometry.aspect, height: height)
    }
}

// MARK: - Menu bar images

/// Pre-rendered NSImages for the status item. The lit icon is one steady
/// frame: a status item that pulses for hours reads as an alert, so the
/// breathing lamp lives in the popover's night card instead.
@MainActor
enum MenuBarIcon {
    /// Warm lamp glow (#f2b24a) — the landing page's lit lantern.
    nonisolated static let lampColor = Color(red: 0xf2/255, green: 0xb2/255, blue: 0x4a/255)
    nonisolated static let lampNSColor = NSColor(red: 0xf2/255, green: 0xb2/255, blue: 0x4a/255, alpha: 1)

    static let height: CGFloat = 18

    private static let towerHeight: CGFloat = 16
    private static let beamReach: CGFloat = 4
    /// Idle and lit share one canvas width so the status item never shifts
    /// its neighbours when a block starts or ends.
    private static let canvasWidth: CGFloat =
        ceil(towerHeight * LighthouseGlyphGeometry.aspect + beamReach * 2) + 1

    /// Template image: dark lantern, adapts to any menu bar appearance.
    static let idle: NSImage = {
        let rh = towerHeight
        let rw = rh * LighthouseGlyphGeometry.aspect
        let size = NSSize(width: canvasWidth, height: height)
        let image = NSImage(size: size, flipped: true) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let r = CGRect(x: (bounds.width - rw) / 2, y: (bounds.height - rh) / 2, width: rw, height: rh)
            ctx.addPath(LighthouseGlyphGeometry.body(in: r).cgPath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Harbour Control — no active block"
        return image
    }()

    /// Lit lamp. The tower is drawn in `labelColor` inside a drawing
    /// handler, so it re-resolves against the menu bar's appearance
    /// (light/dark/tinted) every time it's drawn.
    static let lit: NSImage = makeLit(glow: 0.9, tower: nil)

    /// The same lit icon with a fixed light tower, for illustrations that
    /// draw their own dark menu bar (onboarding).
    static let litOnDark: NSImage = makeLit(glow: 0.9, tower: NSColor.white.withAlphaComponent(0.92))

    private static func makeLit(glow: CGFloat, tower: NSColor?) -> NSImage {
        let rh = towerHeight
        let rw = rh * LighthouseGlyphGeometry.aspect
        let reach = beamReach
        let size = NSSize(width: canvasWidth, height: height)
        let lamp = lampNSColor
        let image = NSImage(size: size, flipped: true) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let r = CGRect(x: (bounds.width - rw) / 2, y: (bounds.height - rh) / 2, width: rw, height: rh)
            let c = LighthouseGlyphGeometry.lampCenter(in: r)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!

            // Soft halo around the lantern
            if let halo = CGGradient(colorsSpace: space, colors: [
                lamp.withAlphaComponent(0.7 * glow).cgColor,
                lamp.withAlphaComponent(0).cgColor,
            ] as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(halo, startCenter: c, startRadius: 0,
                                       endCenter: c, endRadius: rh * 0.36, options: [])
            }

            // Beams, fading out towards the edges
            ctx.saveGState()
            ctx.addPath(LighthouseGlyphGeometry.beams(in: r, reach: reach).cgPath)
            ctx.clip()
            if let beam = CGGradient(colorsSpace: space, colors: [
                lamp.withAlphaComponent(0).cgColor,
                lamp.withAlphaComponent(0.95 * glow).cgColor,
                lamp.withAlphaComponent(0.95 * glow).cgColor,
                lamp.withAlphaComponent(0).cgColor,
            ] as CFArray, locations: [0, 0.4, 0.6, 1]) {
                ctx.drawLinearGradient(beam, start: CGPoint(x: bounds.minX, y: c.y),
                                       end: CGPoint(x: bounds.maxX, y: c.y), options: [])
            }
            ctx.restoreGState()

            // Lamp
            ctx.addPath(LighthouseGlyphGeometry.lamp(in: r).cgPath)
            ctx.setFillColor(lamp.cgColor)
            ctx.fillPath()

            // Tower in the menu bar's text colour
            ctx.addPath(LighthouseGlyphGeometry.body(in: r).cgPath)
            ctx.setFillColor((tower ?? NSColor.labelColor).cgColor)
            ctx.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Harbour Control — block active"
        return image
    }

    /// Compact countdown for the menu bar, always with units so it can't be
    /// misread: "45s" in the last minute, "14m" under an hour, "1h 05m" above.
    /// Minutes round up, so "1m" means "less than a minute or so to go" and
    /// the label only changes once a minute until the final one.
    nonisolated static func compactTime(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)s" }
        let minutes = (s + 59) / 60
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    /// Full spoken form for VoiceOver, e.g. "1 hour, 5 minutes".
    nonisolated static func spokenTime(_ seconds: Int) -> String {
        let f = DateComponentsFormatter()
        let s = max(0, seconds)
        f.allowedUnits = s >= 60 ? [.hour, .minute] : [.second]
        f.unitsStyle = .full
        // Match the label: minutes round up.
        let shown = s >= 60 ? (s + 59) / 60 * 60 : s
        return f.string(from: TimeInterval(shown)) ?? ""
    }
}
