import SwiftUI
import AdaptiveCore

/// A5 — done. Shown the instant the session ends: everything the engine tracked itself
/// (time, splits, intervals) is here immediately; distance and average HR fill in when the
/// OS finishes finalizing the workout in the background. The one status line tracks that
/// finalize honestly — "Saving…" → "Saved to Health".
///
/// Build 9 adds an optional **effort rating** (crown, 1–10, skippable): the app's one
/// deliberate post-workout question, matching Apple's Workout "Effort". It's post-effort
/// (never mid-work — N5) and optional, and `notePreview` shows its effect on next session's
/// plan live as the crown turns — the adaptation Apple's rating can't do. `onDone(effort)`
/// carries the rating (nil = skipped) out to write Health + gate progression.
struct WorkoutCompleteView: View {
    let summary: SessionSummary
    var saveState: HealthSaveState = .saved
    /// The "Next run" note for a given effort — recomputed live as the crown turns.
    var notePreview: (Int?) -> String?
    let onDone: (Int?) -> Void

    @State private var effort: Int?

    private var distanceText: String? {
        guard let meters = summary.totalDistance, meters > 0 else { return nil }
        return String(format: "%.2f km", meters / 1000)
    }

    private var saveLine: (text: String, color: Color) {
        switch saveState {
        case .saving: ("Saving to Health…", .secondary)
        case .saved: ("Saved to Health", WatchTheme.run)
        case .unconfirmed: ("Check Health for this workout", .secondary)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(WatchTheme.run)
                    .symbolEffect(.bounce, options: .nonRepeating)

                Text("Done")
                    .font(.title3.bold())
                Text(saveLine.text)
                    .font(.caption2)
                    .foregroundStyle(saveLine.color)
                    .animation(.easeInOut(duration: 0.3), value: saveState)

                VStack(spacing: 6) {
                    stat("Time", summary.totalDuration.clockString)
                    // Totals owned by the OS appear once the finalize returns; a quiet dash
                    // holds the slot so the layout never jumps.
                    stat("Distance", distanceText ?? "—")
                    stat("Avg HR", summary.averageHeartRate.map { "\(Int($0)) bpm" } ?? "—")
                    stat("Intervals", "\(summary.intervalsCompleted)")
                    if summary.adaptationsApplied > 0 {
                        stat("Adaptations", "\(summary.adaptationsApplied)")
                    }
                }
                .padding(.top, 4)

                EffortRatingControl(effort: $effort, tint: WatchTheme.run)
                    .padding(.top, 6)

                if let note = notePreview(effort) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.run)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                        .animation(.easeInOut(duration: 0.25), value: note)
                }

                Button("Done") { onDone(effort) }
                    .tint(.green)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 6)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.footnote)
        .animation(.easeInOut(duration: 0.3), value: value)
    }
}
