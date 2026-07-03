import SwiftUI

/// The post-workout perceived-effort rating (build 9) — Apple's Workout "Effort" (1–10),
/// crown-scrubbed like the strength rep hero (the app's crown-for-truth precedent). Optional:
/// left at "–" it's a skip. Shown only on the *complete* screen (post-effort), never mid-work
/// (N5). Its result writes `HKWorkoutEffortScore` to Health and feeds next session's
/// progression — a high rating holds an advance the objective counters would have pushed.
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
                .foregroundStyle(.secondary)
            Text(effort.map { "\($0)" } ?? "–")
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(effort == nil ? .secondary : tint)
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
                .accessibilityLabel("Effort rating")
                .accessibilityValue(effort.map { "\($0) of 10" } ?? "not rated")
            Text(effort.map(Self.label) ?? "Turn crown to rate")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear { focused = true }
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
