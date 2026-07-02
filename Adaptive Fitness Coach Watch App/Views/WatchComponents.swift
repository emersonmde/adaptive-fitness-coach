import SwiftUI
import AdaptiveCore

/// `mm:ss` formatting for interval/session timers.
extension TimeInterval {
    var clockString: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Semantic colors shared across the in-workout UI: green = work (run), cool blue = recover
/// (walk). Green vs blue is glance-safe where green vs amber wasn't (sunlight, motion, CVD).
enum WorkoutColors {
    static func tint(for phase: IntervalPhase?) -> Color {
        (phase?.isRun ?? false) ? WatchTheme.run : WatchTheme.recover
    }

    /// Deep tinted-black field behind the verb — telegraphs state before the word is read.
    static func field(for phase: IntervalPhase?) -> Color {
        (phase?.isRun ?? false) ? WatchTheme.runField : WatchTheme.recoverField
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

/// Session elapsed time, glyph-anchored like `HeartRateView` (stopwatch : elapsed as heart :
/// HR). Full weight, not secondary — it's a primary metric, and the glyph plus its top-LEFT
/// placement keep it from ever being read as the system clock in the opposite corner (the
/// "two clocks" confusion a real run surfaced).
struct SessionClockView: View {
    let elapsed: TimeInterval

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "stopwatch.fill")
                .foregroundStyle(WatchTheme.textSecondary)
                .font(.caption)
            Text(elapsed.clockString)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityLabel("Workout time")
        .accessibilityValue(elapsed.clockString)
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
    /// Extra reason to pulse (e.g. cadence says the user is still running during a walk).
    var emphasize: Bool = false

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
    private var shouldPulse: Bool { isHot || emphasize }

    var body: some View {
        // One clear element: the active segment dominates (taller, full color, soft glow), the
        // target zone is marked by an outline merged *into* the bar (no separate underline), and
        // inactive zones recede. The active segment pulses only when drifting hot.
        HStack(spacing: 3) {
            ForEach(0..<zoneCount, id: \.self) { slot in
                let isActive = slot == activeSlot
                Capsule()
                    .fill(color(for: slot).opacity(isActive ? 1.0 : 0.22))
                    .frame(height: isActive ? 10 : 5)
                    .overlay(
                        Capsule().strokeBorder(.white.opacity(slot == targetSlot ? 0.85 : 0), lineWidth: 1.5)
                    )
                    .shadow(color: isActive ? color(for: slot).opacity(0.6) : .clear,
                            radius: isActive ? 5 : 0)
                    .scaleEffect(y: isActive && shouldPulse && hotPulse ? 1.3 : 1.0, anchor: .center)
            }
        }
        .frame(height: 14)
        .animation(.easeInOut(duration: 0.3), value: activeSlot)
        .onChange(of: shouldPulse, initial: true) { _, pulse in
            if pulse && !reduceMotion {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { hotPulse = true }
            } else {
                withAnimation(.default) { hotPulse = false }
            }
        }
        .accessibilityHidden(true)
    }
}
