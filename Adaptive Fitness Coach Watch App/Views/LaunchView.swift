import SwiftUI
import AdaptiveCore

/// A1 — pre-session. Shows only the next scheduled run and a single Start. No library, no
/// parameters to confirm. Start begins a real workout immediately. When today's session is
/// already done (W22) the screen becomes a receipt — "Done today ✓ · Next: Thu" — and Start
/// demotes to "Start again" (still fully functional; the user may genuinely go again, N4).
struct LaunchView: View {
    let routine: Routine?
    /// Planned session length, shown as a "~N min" estimate (the duration self-adjusts to HR).
    var estimatedDuration: TimeInterval = 0
    /// True when this routine already completed a session today (W22).
    var doneToday = false
    /// The routine's next repeat day after today ("Thu"); nil when unscheduled.
    var nextDayLabel: String? = nil
    let onStart: () -> Void

    private var durationText: String {
        guard estimatedDuration > 0 else { return "Run / Walk · adaptive" }
        return "Run / Walk · ~\(Int((estimatedDuration / 60).rounded())) min"
    }

    var body: some View {
        VStack(spacing: 10) {
            if let routine {
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    Text("UP NEXT")
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.textSecondary)
                    Text(routine.name)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(durationText)
                        .font(.caption)
                        .foregroundStyle(WatchTheme.textSecondary)
                    if doneToday {
                        DoneTodayLine(tint: WatchTheme.run, nextDayLabel: nextDayLabel)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onStart) {
                    Text(doneToday ? "Start again" : "Start")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchTheme.run)
            } else {
                Spacer(minLength: 0)
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.title)
                    .foregroundStyle(WatchTheme.textSecondary)
                Text("No session scheduled")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Create a routine on your iPhone.")
                    .font(.caption)
                    .foregroundStyle(WatchTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// The "Done today ✓ · Next: Thu" receipt line shared by the launch screens (W22): a closed
/// loop reads as closed instead of resetting to the same Start it showed this morning.
struct DoneTodayLine: View {
    var tint: Color
    var nextDayLabel: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(tint)
            Text("Done today")
                .foregroundStyle(tint)
            if let nextDayLabel {
                Text("· Next: \(nextDayLabel)")
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        }
        .font(.caption2.weight(.semibold))
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }
}
