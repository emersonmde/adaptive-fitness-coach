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
    /// Recover / walking — a cool cyan-leaning sky blue. Deliberately the far side of the hue
    /// wheel from `run` (green↔amber is the axis that fails first under sunlight, motion blur,
    /// and red-green color deficiency — a real-run glance misread amber WALK as RUN). Warm =
    /// effort, cool = recover; cyan-leaning so it never reads as `strength`'s royal blue.
    static let recover = Color(hex: 0x3EC5FF)
    /// Heat amber. Not a phase color — it serves *gradient* jobs only: the zone ladder's
    /// threshold step and the strength rest ring. (Named `heat`, not `walk`, so nobody
    /// reaches for it as the walk-phase color again.)
    static let heat = Color(hex: 0xFFB23E)
    static let hot = Color(hex: 0xFF5A4D)   // sustained-high HR
    static let strength = Color(hex: 0x4C8DFF)

    /// Deep tinted-black fields behind the interval verb — the colored ground telegraphs state
    /// before the word is read.
    static let runField = Color(hex: 0x06180C)
    /// Recover's colored ground — a deep cool-blue lift of true black, matching `recover`.
    static let recoverField = Color(hex: 0x061520)
    /// Strength's colored ground — a deep blue lift of true black, matching `strength`.
    static let strengthField = Color(hex: 0x070E1C)

    static let textSecondary = Color(hex: 0x9DA3AE)
}
