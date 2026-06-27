import SwiftUI

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
/// Two-tier color model: `accent` (Electric Lime) is the **brand identity** — used only for
/// app chrome, CTAs, and selected states. The workout-state semantics (`run`/`walk`/`strength`/
/// `hot`) are a separate language tied to the watch's haptics and learned mid-run (N5); they are
/// never replaced by the brand accent.
enum Theme {
    // Neutrals
    static let bg = Color(hex: 0x08090B)        // near-black (avoids OLED banding/halation with neon)
    static let surface1 = Color(hex: 0x121317)  // cards / elevated
    static let surface2 = Color(hex: 0x1B1D22)  // inputs, sheets, pressed
    static let hairline = Color(hex: 0x2A2D34)  // borders/dividers (replace shadows on dark)

    static let textPrimary = Color(hex: 0xF4F5F7)   // ~92% white, less halation
    static let textSecondary = Color(hex: 0x9DA3AE) // metadata (AA)
    static let textTertiary = Color(hex: 0x6A6F7A)  // sparingly, >= 13pt only

    // Brand accent (phone identity only)
    static let accent = Color(hex: 0xC6FF3D)        // Electric Lime
    static let accentGlow = Color(hex: 0xA8E000)

    // Workout-state semantics (shared language with the watch)
    static let run = Color(hex: 0x34E27A)       // run / work
    static let walk = Color(hex: 0xFFB23E)      // walk / recovery
    static let strength = Color(hex: 0x4C8DFF)  // strength type
    static let hot = Color(hex: 0xFF5A4D)       // sustained-high HR / destructive
}
