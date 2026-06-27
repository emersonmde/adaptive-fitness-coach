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
enum WorkoutColors {
    static func tint(for phase: IntervalPhase?) -> Color {
        (phase?.isRun ?? false) ? .green : .orange
    }
}

/// Live heart rate with a beating heart glyph. Shows "--" until the first sample arrives (N6).
struct HeartRateView: View {
    let bpm: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .font(.caption)
            Text(bpm > 0 ? "\(Int(bpm))" : "--")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityLabel("Heart rate")
        .accessibilityValue(bpm > 0 ? "\(Int(bpm)) beats per minute" : "no reading")
    }
}

/// A five-segment zone bar with the current zone highlighted. Ambient reassurance only —
/// nothing here is required to follow the session (N5).
struct ZoneBarView: View {
    /// Apple's current zone index, or nil before the first zone update.
    let currentZoneIndex: Int?
    /// The aerobic target zone index (highlighted subtly as the "good" band).
    let targetZoneIndex: Int

    private let zoneCount = 5

    private func color(for slot: Int) -> Color {
        switch slot {
        case 0: .blue
        case 1: .green
        case 2: .yellow
        case 3: .orange
        default: .red
        }
    }

    /// Normalize Apple's index (which may be 0- or 1-based) into a 0..<5 slot for display.
    private var activeSlot: Int? {
        guard let i = currentZoneIndex else { return nil }
        return max(0, min(zoneCount - 1, i <= 0 ? 0 : i - (i >= zoneCount ? 1 : 0)))
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<zoneCount, id: \.self) { slot in
                Capsule()
                    .fill(color(for: slot).opacity(slot == activeSlot ? 1.0 : 0.25))
                    .frame(height: slot == activeSlot ? 7 : 5)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: activeSlot)
        .accessibilityHidden(true)
    }
}
