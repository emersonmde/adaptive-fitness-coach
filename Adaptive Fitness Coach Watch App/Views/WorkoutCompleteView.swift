import SwiftUI
import AdaptiveCore

/// A5 — done. The session is already a native Apple workout in Health. This is a brief
/// acknowledgement read back from the saved workout, not a logging step: nothing to confirm,
/// rate, or save (N1).
struct WorkoutCompleteView: View {
    let summary: SessionSummary
    let onDone: () -> Void

    private var distanceText: String? {
        guard let meters = summary.totalDistance, meters > 0 else { return nil }
        return String(format: "%.2f km", meters / 1000)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)

                Text("Done")
                    .font(.title3.bold())
                Text("Saved to Health")
                    .font(.caption2)
                    .foregroundStyle(.green)

                VStack(spacing: 6) {
                    stat("Time", summary.totalDuration.clockString)
                    if let distanceText { stat("Distance", distanceText) }
                    if let hr = summary.averageHeartRate, hr > 0 { stat("Avg HR", "\(Int(hr)) bpm") }
                    stat("Intervals", "\(summary.intervalsCompleted)")
                    if summary.adaptationsApplied > 0 {
                        stat("Adaptations", "\(summary.adaptationsApplied)")
                    }
                }
                .padding(.top, 4)

                Text("Nothing to log")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

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
    }
}
