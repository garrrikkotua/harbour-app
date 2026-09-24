import SwiftUI

/// Harbour design system — navy + parchment + New York serif (system, no bundled fonts).
///
/// The app draws its own palette on every surface, so colours here are fixed
/// (they never flip with the system appearance). Views that host AppKit
/// controls pin `colorScheme` so text fields and menus match: parchment
/// screens are `.light`, night screens are `.dark`.
enum Theme {
    // Core palette
    static let navy        = Color(red: 0x1a/255, green: 0x2a/255, blue: 0x44/255)
    static let navyDeep    = Color(red: 0x11/255, green: 0x1c/255, blue: 0x30/255)
    static let navyLight   = Color(red: 0x2b/255, green: 0x40/255, blue: 0x66/255)
    /// Warm sand for quiet fills on parchment (hover rows, chips). Kept warm
    /// on purpose: blue belongs to the night scenes only.
    static let navySoft    = Color(red: 0xec/255, green: 0xe6/255, blue: 0xda/255)

    static let parchment   = Color(red: 0xf4/255, green: 0xf1/255, blue: 0xea/255)
    static let parchmentWarm = Color(red: 0xfd/255, green: 0xf6/255, blue: 0xe9/255)
    static let cream       = Color(red: 0xf0/255, green: 0xec/255, blue: 0xe2/255)
    static let creamBorder = Color(red: 0xd8/255, green: 0xd0/255, blue: 0xbd/255)
    static let creamBorderSoft = Color(red: 0xe6/255, green: 0xde/255, blue: 0xc9/255)

    static let textPrimary = Color(red: 0x1a/255, green: 0x2a/255, blue: 0x44/255)
    static let textSecondary = Color(red: 0x5a/255, green: 0x6b/255, blue: 0x85/255)
    static let textTertiary = Color(red: 0x8a/255, green: 0x95/255, blue: 0xa8/255)

    static let amber       = Color(red: 0xc9/255, green: 0x7a/255, blue: 0x4a/255)   // accent for lighthouse beam
    static let beam        = Color(red: 0xf2/255, green: 0xb2/255, blue: 0x4a/255)   // lamp glow (site's --beam)
    static let amberSoft   = Color(red: 0xf6/255, green: 0xe6/255, blue: 0xd2/255)   // amber-tinted callout fill
    static let ember       = Color(red: 0xb4/255, green: 0x45/255, blue: 0x2f/255)   // irreversible actions
    static let emberDeep   = Color(red: 0x8e/255, green: 0x32/255, blue: 0x22/255)
    static let success     = Color(red: 0x34/255, green: 0xc7/255, blue: 0x59/255)
    static let warning     = Color(red: 0xff/255, green: 0x95/255, blue: 0x00/255)
    static let danger      = Color(red: 0xff/255, green: 0x3b/255, blue: 0x30/255)

    // Night-scene text (on navy)
    static let nightText      = parchmentWarm
    static let nightSecondary = Color.white.opacity(0.58)
    static let nightTertiary  = Color.white.opacity(0.4)

    // Gradients
    static let parchmentDeep = Color(red: 0xef/255, green: 0xe9/255, blue: 0xdd/255)

    static let setupBackground = LinearGradient(
        colors: [parchment, parchmentDeep],
        startPoint: .top,
        endPoint: .bottom
    )
    static let activeBackground = LinearGradient(
        colors: [navyDeep, navy, navyLight],
        startPoint: .top,
        endPoint: .bottom
    )
    static let primaryButton = LinearGradient(
        colors: [navyLight, navy],
        startPoint: .top,
        endPoint: .bottom
    )
    static let destructiveButton = LinearGradient(
        colors: [ember, emberDeep],
        startPoint: .top,
        endPoint: .bottom
    )
    static let progressFill = LinearGradient(
        colors: [amber, beam],
        startPoint: .leading,
        endPoint: .trailing
    )

    // Metrics
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 8

    // Typography — Apple's New York serif ships with macOS and reads close to Fraunces.
    static func serif(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Shared surfaces

/// White parchment card with the site's soft cream border.
struct CardBackground: View {
    var radius: CGFloat = Theme.cardRadius

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.creamBorderSoft, lineWidth: 1)
            )
            .shadow(color: Theme.navy.opacity(0.06), radius: 10, y: 3)
    }
}

/// Small uppercase eyebrow with the glowing amber dot from the landing page.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.amber
    var glow: Bool = true

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Theme.beam)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.beam.opacity(glow ? 0.8 : 0), radius: 4)
            Text(text.uppercased())
                .font(Theme.sans(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(color)
        }
    }
}

extension View {
    /// `.contentTransition(.numericText())` where the OS supports it
    /// (rolling digits); a plain swap elsewhere.
    @ViewBuilder
    func numericTransition(countsDown: Bool = false) -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.numericText(countsDown: countsDown))
        } else {
            self
        }
    }
}
