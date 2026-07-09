import SwiftUI
import UIKit

extension Color {
    /// Hex initializer (`0xRRGGBB`). Keeps the palette legible and matched to the design tokens.
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

/// The app's dark/neon design tokens.
///
/// Two-tier color model: `accent` is the **brand identity** — used only for app chrome, CTAs,
/// and selected states. It is deliberately set to the same emerald as the `run` semantic so the
/// phone reads as one coherent green (per the user's preference over the prior Electric Lime).
/// The workout-state semantics (`run`/`walk`/`strength`/`hot`) remain a separate language tied to
/// the watch's haptics and learned mid-run (N5); `walk`/`strength`/`hot` are never replaced by the
/// brand accent.
enum Theme {
    // Neutrals
    static let bg = Color(hex: 0x08090B)        // near-black (avoids OLED banding/halation with neon)
    static let surface1 = Color(hex: 0x121317)  // cards / elevated
    static let surface2 = Color(hex: 0x1B1D22)  // inputs, sheets, pressed
    static let hairline = Color(hex: 0x2A2D34)  // borders/dividers (replace shadows on dark)

    static let textPrimary = Color(hex: 0xF4F5F7)   // ~92% white, less halation
    static let textSecondary = Color(hex: 0x9DA3AE) // metadata (AA)
    static let textTertiary = Color(hex: 0x828895)  // sparingly; lightest tier that clears AA (4.5:1) on both surfaces at caption sizes (was 0x6A6F7A ≈ 3.7:1)

    // Brand accent (phone identity only)
    static let accent = Color(hex: 0x34E27A)        // Emerald (matches the run semantic — one coherent green)
    static let accentGlow = Color(hex: 0x1FB85E)    // deeper emerald for glow/outline gradients

    // Workout-state semantics (shared language with the watch)
    static let run = Color(hex: 0x34E27A)       // run / work
    static let recover = Color(hex: 0x3EC5FF)   // walk / recovery (cool blue — matches the watch)
    static let strength = Color(hex: 0x4C8DFF)  // strength type
    static let hot = Color(hex: 0xFF5A4D)       // sustained-high HR / destructive
    static let heat = Color(hex: 0xFFB23E)      // gradient jobs only (over-target gauge; watch zone/rest amber)

    /// Neutral "informational/update" accent for chrome (coach UPDATES badges, import diffs).
    /// Same value as `recover` today, but deliberately a separate token: `recover` is a learned
    /// workout instruction (walk), and chrome must not borrow instruction hues structurally.
    static let info = Color(hex: 0x3EC5FF)

    // Corner radii (one scale; `Card` defaults to radiusCard)
    static let radiusInset: CGFloat = 12   // inset sub-panels, chat bubbles' small siblings
    static let radiusCard: CGFloat = 18    // cards, rows, bubbles
    static let radiusHero: CGFloat = 24    // the glass hero only

    /// The large glyph-anchored metric number (calorie gauge hero, day header total).
    static let metricNumber = Font.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()
}

// MARK: - Motion

extension Theme {
    /// One animation vocabulary (P5). Reduce-Motion is a parameter, not a call-site afterthought:
    /// large-displacement tokens return `nil` (or an opacity-only transition) when it's on.
    enum Motion {
        /// Direct-manipulation feedback: press dim, ± value ticks.
        static let snap = Animation.easeOut(duration: 0.15)
        /// The universal state/content settle — the app's dominant curve.
        static let settle = Animation.easeInOut(duration: 0.28)
        /// Slow progress fills (gauge). Callers gate on Reduce Motion where the fill is large.
        static let gentle = Animation.easeOut(duration: 0.6)
        /// Finger-following settle — swipe rows only. A spring is earned only where a finger was.
        static let gesture = Animation.spring(response: 0.3, dampingFraction: 0.86)

        /// Large-displacement navigation (day slide, toast). Collapses under Reduce Motion.
        static func slide(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : settle
        }
        /// The day-change/toast transition pair: movement normally, opacity-only under Reduce Motion.
        static func slideTransition(_ base: AnyTransition, reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : base
        }
    }
}

// MARK: - Haptics

extension Theme {
    /// The phone's deliberate haptic vocabulary (P5) — five roles, mirroring the watch's
    /// "followable by feel" contract instead of accumulating one-off impacts.
    enum Haptics {
        /// Swipe-row commit threshold armed (lighter than capture — it's a tick, not an event).
        static func commitTick() {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
        }
        /// A capture happened: shutter frozen, barcode locked.
        static func capture() {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        /// A log/save landed (relog, entry saved, meal committed).
        static func success() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        /// Destructive confirm shown or an operation failed.
        static func warning() {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        /// Navigation tick (day change).
        static func selection() {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
