import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Watch design tokens. True black base (power + contrast). Brighter workout-state semantics so
/// they hold at a glance on black, matched 1:1 to the phone's semantics. No brand accent here —
/// the lime is phone-only; the watch speaks only the workout-state language (N5).
enum WatchTheme {
    static let bg = Color.black
    static let surface1 = Color(hex: 0x121317)

    static let run = Color(hex: 0x34E27A)   // work / running
    static let walk = Color(hex: 0xFFB23E)  // recover / walking
    static let hot = Color(hex: 0xFF5A4D)   // sustained-high HR
    static let strength = Color(hex: 0x4C8DFF)

    /// Deep tinted-black fields behind the interval verb — the colored ground telegraphs state
    /// before the word is read.
    static let runField = Color(hex: 0x06180C)
    static let walkField = Color(hex: 0x1A1206)

    static let textSecondary = Color(hex: 0x9DA3AE)
}
