import SwiftUI
import AdaptiveCore

/// A5 — done. Shown the instant the session ends: everything the engine tracked itself
/// (time, splits, intervals) is here immediately; distance and average HR fill in when the
/// OS finishes finalizing the workout in the background. The one status line tracks that
/// finalize honestly — "Saving…" → "Saved to Health" — and this stays an acknowledgement,
/// not a logging step: nothing to confirm or rate (N1). Optional `nextRunNote` is the single
/// quiet line that makes cross-session adaptation perceivable ("Next run: 2 min intervals").
struct WorkoutCompleteView: View {
    let summary: SessionSummary
    var saveState: HealthSaveState = .saved
    var nextRunNote: String?
    let onDone: () -> Void

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

                if let nextRunNote {
                    Text(nextRunNote)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.run)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                } else {
                    Text("Nothing to log")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                Button("Done", action: onDone)
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
