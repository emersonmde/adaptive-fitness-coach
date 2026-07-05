import SwiftUI

/// The post-workout perceived-effort rating (build 9) — Apple's Workout "Effort" (1–10),
/// crown-scrubbed like the strength rep hero (the app's crown-for-truth precedent). Optional:
/// left at "–" it's a skip. Shown only on the *complete* screen (post-effort), never mid-work
/// (N5). Its result writes `HKWorkoutEffortScore` to Health and feeds next session's
/// progression — a high rating holds an advance the objective counters would have pushed.
///
/// Crown focus is **opt-in by tap**, never grabbed on appear: this control lives inside the
/// scrollable summary, where the crown's default job is scrolling. Auto-focusing on appear
/// meant a scroll gesture silently *set a rating* — and the rating gates progression, so a
/// stray flick could hold or ease next session's plan. The tiny crown glyph next to the value
/// is the established "this number is crown-live" affordance (see the strength rep hero);
/// here it lights up in the tint while focused so the two crown modes are distinguishable.
struct EffortRatingControl: View {
    @Binding var effort: Int?
    var tint: Color

    @State private var crown: Double = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("EFFORT")
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(WatchTheme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(effort.map { "\($0)" } ?? "–")
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(effort == nil ? .secondary : tint)
                Image(systemName: "digitalcrown.horizontal.arrow.counterclockwise.fill")
                    .font(.caption2)
                    .foregroundStyle(focused ? tint : .secondary.opacity(0.7))
            }
            .focusable(true)
            .focused($focused)
            .digitalCrownRotation(
                $crown, from: 0, through: 10, by: 1,
                sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
            )
            .onChange(of: crown) { _, value in
                let rounded = Int(value.rounded())
                effort = rounded < 1 ? nil : min(10, rounded)
            }
            Text(hint)
                .font(.caption2)
                .foregroundStyle(WatchTheme.textSecondary)
        }
        // The whole stack is the tap target — a 30pt digit alone is a stingy thing to have
        // to hit post-workout with a sweaty finger.
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        // One element for VoiceOver, adjustable like the rep hero: swipe up/down sets the
        // rating without needing the crown-focus dance at all. Below 1 collapses back to
        // "not rated" (the skip), mirroring the crown's 0 detent.
        .accessibilityElement()
        .accessibilityLabel("Effort rating")
        .accessibilityValue(effort.map { "\($0) of 10" } ?? "not rated")
        .accessibilityHint("Adjust to rate how hard the workout felt")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: effort = min(10, (effort ?? 0) + 1)
            case .decrement:
                let lowered = (effort ?? 0) - 1
                effort = lowered < 1 ? nil : lowered
            @unknown default: break
            }
            // Keep the crown-bound mirror in step (same discipline as the rep hero): without
            // this, the next crown turn would snap the rating back to the stale detent.
            crown = Double(effort ?? 0)
        }
    }

    /// The line under the number: the meaning of a set rating, or how to set one. Before the
    /// control is focused the instruction is "tap" — saying "turn crown" while the crown still
    /// scrolls the summary would be a lie.
    private var hint: String {
        if let effort { return Self.label(effort) }
        return focused ? "Turn crown to rate" : "Tap to rate"
    }

    static func label(_ effort: Int) -> String {
        switch effort {
        case ...3: "Easy"
        case 4...6: "Moderate"
        case 7...8: "Hard"
        default: "All-out"
        }
    }
}
