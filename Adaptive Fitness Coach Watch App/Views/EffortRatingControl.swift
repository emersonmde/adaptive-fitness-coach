import SwiftUI
import AdaptiveCore

/// The post-workout perceived-effort rating — coarse levels (Easy / Moderate / Hard /
/// All-out) stepped with −/+ buttons (P6.1). Optional: left at "–" it's a skip. Shown only
/// on the *complete* screen (post-effort), never mid-work (N5). The chosen level's
/// `EffortLevel.score` (2/5/8/10) writes `HKWorkoutEffortScore` and feeds next session's
/// progression — Hard and All-out both hold an advance the objective counters would have
/// pushed (score ≥ the policies' high-effort threshold).
///
/// Deliberately NO crown involvement: this control lives inside the scrollable summary,
/// and on-device use showed a crown-focused rater captures the crown for the rest of the
/// screen — with wet post-run fingers unable to touch-scroll, that trapped the whole
/// summary. Buttons are the honest input here; the crown's one job on this screen is
/// scrolling. (The strength rep hero keeps its crown — that screen doesn't scroll.)
struct EffortRatingControl: View {
    @Binding var effort: Int?
    var tint: Color
    /// True while the current value is the app's HR-derived suggestion the user hasn't
    /// touched yet — rendered visibly *as* a suggestion (secondary tint + caption) so the
    /// pre-selection reads as "our guess, adjust if it felt different", never as their answer
    /// already given.
    var isSuggested: Bool = false

    private var level: EffortLevel? {
        effort.flatMap(EffortLevel.init(score:))
    }

    var body: some View {
        VStack(spacing: 3) {
            Text("EFFORT")
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(WatchTheme.textSecondary)
            HStack(spacing: 10) {
                stepButton("minus", enabled: effort != nil) {
                    effort = level?.down?.score   // below Easy collapses to unrated (the skip)
                }
                Text(level?.label ?? "–")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(level == nil ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(tint.opacity(isSuggested ? 0.55 : 1)))
                    .frame(minWidth: 88)          // fits "Moderate"; the words never reflow the ±
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                stepButton("plus", enabled: level != .allOut) {
                    effort = (level?.up ?? .easy).score
                }
            }
            Text(level == nil ? "How did it feel?"
                 : (isSuggested ? "Suggested — adjust if it felt different" : " "))
                .font(.caption2)
                .foregroundStyle(WatchTheme.textSecondary)
        }
        // One element for VoiceOver, adjustable: swipe up/down steps the levels.
        .accessibilityElement()
        .accessibilityLabel("Effort rating")
        .accessibilityValue(level.map { isSuggested ? "\($0.label), suggested" : $0.label } ?? "not rated")
        .accessibilityHint("Adjust to rate how hard the workout felt")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: effort = (level?.up ?? level ?? .easy).score
            case .decrement: effort = level?.down?.score
            @unknown default: break
            }
        }
    }

    /// A ±44pt round step target — post-workout fingers are wet; stingy targets were the
    /// whole complaint.
    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    /// The coarse word for an arbitrary 1–10 score (kept for callers that render historical
    /// fine-grained ratings).
    static func label(_ effort: Int) -> String {
        EffortLevel(score: effort)?.label ?? "\(effort)"
    }
}
