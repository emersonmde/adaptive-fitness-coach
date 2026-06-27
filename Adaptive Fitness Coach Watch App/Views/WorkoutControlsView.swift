import SwiftUI

/// Pages the in-workout experience like the native Workout app: a swipe-away **controls** page
/// (End) and the **metrics** page (the glanceable run/walk screen). Starting on metrics keeps the
/// main screen pure — End is one deliberate swipe away, never cluttering the glance.
struct WorkoutSessionPager: View {
    let manager: WorkoutSessionManager
    @State private var selection = Page.metrics

    private enum Page { case controls, metrics }

    var body: some View {
        TabView(selection: $selection) {
            WorkoutControlsView(manager: manager).tag(Page.controls)
            WorkoutActiveView(manager: manager).tag(Page.metrics)
        }
        .tabViewStyle(.page)
    }
}

/// The controls page: End the workout (which ends the underlying HKWorkoutSession cleanly).
struct WorkoutControlsView: View {
    let manager: WorkoutSessionManager

    var body: some View {
        VStack(spacing: 10) {
            Button(role: .destructive) {
                manager.endManually()
            } label: {
                Label("End Workout", systemImage: "xmark")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .tint(WatchTheme.hot)

            Text("Swipe back to your run")
                .font(.caption2)
                .foregroundStyle(WatchTheme.textSecondary)
        }
        .padding()
    }
}
