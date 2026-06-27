import SwiftUI
import AdaptiveCore

/// `mm:ss` formatting for interval/session timers.
extension TimeInterval {
    var clockString: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Semantic colors shared across the in-workout UI: green = work (run), amber = recover (walk).
/// Brighter tokens (matched to the phone) so they hold at a glance on black.
enum WorkoutColors {
    static func tint(for phase: IntervalPhase?) -> Color {
        (phase?.isRun ?? false) ? WatchTheme.run : WatchTheme.walk
    }

    /// Deep tinted-black field behind the verb — telegraphs state before the word is read.
    static func field(for phase: IntervalPhase?) -> Color {
        (phase?.isRun ?? false) ? WatchTheme.runField : WatchTheme.walkField
    }
}

/// Live heart rate with a beating heart glyph. The heart pulses with each reading (a literal
/// heartbeat); shows "--" until the first sample arrives (N6). `symbolEffect` respects Reduce Motion.
struct HeartRateView: View {
    let bpm: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .foregroundStyle(WatchTheme.hot)
                .font(.caption)
                .symbolEffect(.pulse, options: .repeating, isActive: bpm > 0)
            Text(bpm > 0 ? "\(Int(bpm))" : "--")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityLabel("Heart rate")
        .accessibilityValue(bpm > 0 ? "\(Int(bpm)) beats per minute" : "no reading")
    }
}

/// A five-segment zone bar with the current zone highlighted and the aerobic target band
/// underlined. Steady when in zone; the active segment pulses only when drifting **hot** (above
/// target) — motion draws the eye exactly when something needs attention (N5). Reduce-Motion aware.
///
/// Inputs are already-normalized **1-based zone positions** (see `WorkoutBackend`), so the
/// mapping to a 0-based display slot is a plain `position - 1`, no base guessing.
struct ZoneBarView: View {
    /// Current 1-based zone position, or nil before the first zone update.
    let currentZoneIndex: Int?
    /// The aerobic target zone position (marked as the "good" band).
    let targetZoneIndex: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hotPulse = false

    private let zoneCount = 5

    private func color(for slot: Int) -> Color {
        switch slot {
        case 0: WatchTheme.strength      // recovery / low
        case 1: WatchTheme.run           // aerobic
        case 2: Color(hex: 0xFFD23E)     // tempo
        case 3: WatchTheme.walk          // threshold
        default: WatchTheme.hot          // max
        }
    }

    private func slot(forPosition position: Int) -> Int {
        max(0, min(zoneCount - 1, position - 1))
    }

    private var activeSlot: Int? { currentZoneIndex.map(slot(forPosition:)) }
    private var targetSlot: Int { slot(forPosition: targetZoneIndex) }
    private var isHot: Bool { (activeSlot ?? 0) > targetSlot }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<zoneCount, id: \.self) { slot in
                VStack(spacing: 2) {
                    Capsule()
                        .fill(color(for: slot).opacity(slot == activeSlot ? 1.0 : 0.25))
                        .frame(height: slot == activeSlot ? 7 : 5)
                        .scaleEffect(y: slot == activeSlot && isHot && hotPulse ? 1.35 : 1.0, anchor: .bottom)
                    // Underline the aerobic target band so "where I should be" is legible.
                    Capsule()
                        .fill(.white.opacity(slot == targetSlot ? 0.5 : 0))
                        .frame(height: 2)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: activeSlot)
        .onChange(of: isHot) { _, hot in
            if hot && !reduceMotion {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { hotPulse = true }
            } else {
                withAnimation(.default) { hotPulse = false }
            }
        }
        .accessibilityHidden(true)
    }
}
