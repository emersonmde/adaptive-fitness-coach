import SwiftUI
import AdaptiveCore

/// The strength analogue of `WorkoutCompleteView` (A5). The session is already a native Apple
/// strength workout in Health; this is acknowledgement, not a logging step (N1/N2).
struct StrengthCompleteView: View {
    let summary: StrengthSummary
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(WatchTheme.strength)
                    .symbolEffect(.bounce, options: .nonRepeating)

                Text("Done")
                    .font(.title3.bold())
                Text("Saved to Health")
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.strength)

                VStack(spacing: 6) {
                    stat("Time", summary.totalDuration.clockString)
                    stat("Exercises", "\(summary.exercisesCompleted)")
                    stat("Sets", "\(summary.setsCompleted)")
                    if let hr = summary.averageHeartRate, hr > 0 { stat("Avg HR", "\(Int(hr)) bpm") }
                }
                .padding(.top, 4)

                Text("Nothing to log")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                Button("Done", action: onDone)
                    .tint(WatchTheme.strength)
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
    }
}
