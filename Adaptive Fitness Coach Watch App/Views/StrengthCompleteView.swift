import SwiftUI
import AdaptiveCore

/// The strength analogue of `WorkoutCompleteView` (A5). The session is already a native Apple
/// strength workout in Health; this is acknowledgement plus build 9's optional **effort
/// rating** (crown 1–10, skippable). Strength gets no Apple-estimated effort at all, so the
/// rating is the only Training-Load signal — and it holds an otherwise-clean advance. The
/// "NEXT TIME" notes update live via `notePreview` as the crown turns.
struct StrengthCompleteView: View {
    let summary: StrengthSummary
    var saveState: HealthSaveState = .saved
    /// The "next time" notes for a given effort — recomputed live as the crown turns.
    var notePreview: (Int?) -> [String]
    let onDone: (Int?) -> Void

    @State private var effort: Int?

    private var saveLine: (text: String, color: Color) {
        switch saveState {
        case .saving: ("Saving to Health…", .secondary)
        case .saved: ("Saved to Health", WatchTheme.strength)
        case .unconfirmed: ("Check Health for this workout", .secondary)
        }
    }

    var body: some View {
        ZStack {
            WatchTheme.strengthField.ignoresSafeArea()
            ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(WatchTheme.strength)
                    .symbolEffect(.bounce, options: .nonRepeating)

                Text("Done")
                    .font(.title3.bold())
                Text(saveLine.text)
                    .font(.caption2)
                    .foregroundStyle(saveLine.color)
                    .animation(WatchTheme.Motion.settle, value: saveState)

                VStack(spacing: 6) {
                    stat("Time", summary.totalDuration.clockString)
                    stat("Exercises", "\(summary.exercisesCompleted)")
                    if summary.setsCompleted > 0 { stat("Sets", "\(summary.setsCompleted)") }
                    stat("Avg HR", summary.averageHeartRate.map { "\(Int($0)) bpm" } ?? "—")
                }
                .padding(.top, 4)

                EffortRatingControl(effort: $effort, tint: WatchTheme.strength)
                    .padding(.top, 6)

                let notes = notePreview(effort)
                if !notes.isEmpty {
                    // The quietly-perceivable adaptation moment: what the app learned and
                    // what next session prescribes because of it (Q5 — one calm section).
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NEXT TIME")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.5)
                            .foregroundStyle(WatchTheme.textSecondary)
                        ForEach(notes.prefix(3), id: \.self) { note in
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(WatchTheme.strength)
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        if notes.count > 3 {
                            Text("+\(notes.count - 3) more")
                                .font(.caption2)
                                .foregroundStyle(WatchTheme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }

                Button("Done") { onDone(effort) }
                    .tint(WatchTheme.strength)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 6)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(WatchTheme.textSecondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.footnote)
    }
}
