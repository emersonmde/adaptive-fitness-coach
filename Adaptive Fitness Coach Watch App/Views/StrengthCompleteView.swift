import SwiftUI
import AdaptiveCore

/// The strength analogue of `WorkoutCompleteView` (A5). The session is already a native Apple
/// strength workout in Health; this is acknowledgement, not a logging step (N1/N2).
struct StrengthCompleteView: View {
    let summary: StrengthSummary
    var saveState: HealthSaveState = .saved
    let onDone: () -> Void

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
                    .animation(.easeInOut(duration: 0.3), value: saveState)

                VStack(spacing: 6) {
                    stat("Time", summary.totalDuration.clockString)
                    stat("Exercises", "\(summary.exercisesCompleted)")
                    stat("Avg HR", summary.averageHeartRate.map { "\(Int($0)) bpm" } ?? "—")
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
