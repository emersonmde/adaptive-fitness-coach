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
    /// The tempo step of the zone ladder gradient — between aerobic green and threshold amber.
    /// Gradient-only, like `heat`; never an instruction color.
    static let zoneTempo = Color(hex: 0xFFD23E)
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

    /// Motion tokens. Every animation on the watch speaks one of four verbs, so state changes
    /// settle at the same speed everywhere and motion stays a single meaningful channel
    /// (DESIGN-PRINCIPLES #3 — motion = attention/compliance, so an ad-hoc duration is noise).
    enum Motion {
        /// The app's dominant state-change curve: phase flips, cards advancing, status lines,
        /// pulse resets. If a value just *became* something else, it settles with this.
        static let settle = Animation.easeInOut(duration: 0.28)
        /// Direct-manipulation value ticks (crown detents, ± adjusters) — quick enough to feel
        /// attached to the finger.
        static let snap = Animation.easeOut(duration: 0.15)
        /// A slow, calm ring fill for once-a-second recovery updates (the rest ring).
        static let gentle = Animation.easeOut(duration: 0.6)
        /// A constant-rate tick for a ring that tracks a running clock (the hold ring) —
        /// linear so consecutive one-second steps chain without visible easing seams.
        static func gentleLinear(_ seconds: TimeInterval) -> Animation {
            .linear(duration: seconds)
        }
        /// The compliance channel: an attention throb that repeats until the condition clears
        /// (hot zone, cadence mismatch, imminent switch). Callers gate it on Reduce Motion.
        static let pulse = Animation.easeInOut(duration: 0.55).repeatForever(autoreverses: true)
    }
}

extension View {
    /// Full-bleed workout-field background for a **paged** in-workout screen (a `.page`
    /// TabView child), keeping content inside the safe area. Replaces the old
    /// `ZStack { field.ignoresSafeArea(); content }` idiom, which let the bottom-most control
    /// clip under the watch's bottom inset on real hardware — paged TabView children bleed
    /// past the safe area, and the Simulator underrenders the inset so it slipped through
    /// (build 9). Verified on Series 11 46mm + Ultra 3 49mm.
    func pagedWorkoutBackground(_ field: Color) -> some View {
        containerBackground(field, for: .tabView)
    }

    /// Full-bleed workout-field background for a **full-screen** (non-paged) in-workout or
    /// launch screen, reserving the bottom safe area so edge-justified controls don't clip.
    func fullScreenWorkoutBackground(_ field: Color) -> some View {
        self
            .scenePadding(.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(field.ignoresSafeArea())
    }
}
