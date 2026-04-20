import SwiftUI

/// Harbour design system — navy + parchment + New York serif (system, no bundled fonts).
enum Theme {
    // Core palette
    static let navy        = Color(red: 0x1a/255, green: 0x2a/255, blue: 0x44/255)
    static let navyDeep    = Color(red: 0x11/255, green: 0x1c/255, blue: 0x30/255)
    static let navyLight   = Color(red: 0x2b/255, green: 0x40/255, blue: 0x66/255)
    static let navySoft    = Color(red: 0xe9/255, green: 0xee/255, blue: 0xf7/255)

    static let parchment   = Color(red: 0xf4/255, green: 0xf1/255, blue: 0xea/255)
    static let parchmentWarm = Color(red: 0xfd/255, green: 0xf6/255, blue: 0xe9/255)
    static let cream       = Color(red: 0xf0/255, green: 0xec/255, blue: 0xe2/255)
    static let creamBorder = Color(red: 0xd8/255, green: 0xd0/255, blue: 0xbd/255)
    static let creamBorderSoft = Color(red: 0xe6/255, green: 0xde/255, blue: 0xc9/255)

    static let textPrimary = Color(red: 0x1a/255, green: 0x2a/255, blue: 0x44/255)
    static let textSecondary = Color(red: 0x5a/255, green: 0x6b/255, blue: 0x85/255)
    static let textTertiary = Color(red: 0x8a/255, green: 0x95/255, blue: 0xa8/255)

    static let amber       = Color(red: 0xc9/255, green: 0x7a/255, blue: 0x4a/255)   // accent for lighthouse beam
    static let success     = Color(red: 0x34/255, green: 0xc7/255, blue: 0x59/255)
    static let warning     = Color(red: 0xff/255, green: 0x95/255, blue: 0x00/255)
    static let danger      = Color(red: 0xff/255, green: 0x3b/255, blue: 0x30/255)

    // Gradients
    static let setupBackground = LinearGradient(
        colors: [parchment, navySoft],
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
