import SwiftUI
import WatchKit

/// Pages the in-workout experience like the native Workout app: a swipe-away **controls** page
/// (End) and the **metrics** page (the glanceable run/walk screen). Starting on metrics keeps the
/// main screen pure — End is one deliberate swipe away, never cluttering the glance.
struct WorkoutSessionPager: View {
    let manager: WorkoutSessionManager
    // watchOS-sim XCUI can't tap or swipe (see WatchSessionUITests) — `-startPage=…` lets
    // scripted screenshot runs land directly on a specific page for visual review.
    @State private var selection: Page =
        ProcessInfo.processInfo.arguments.contains("-startPage=controls") ? .controls : .metrics

    private enum Page { case controls, metrics }

    var body: some View {
        TabView(selection: $selection) {
            WorkoutControlsView(manager: manager).tag(Page.controls)
            WorkoutActiveView(manager: manager).tag(Page.metrics)
        }
        .tabViewStyle(.page)
    }
}

/// The controls page — session-level things that stay off the metrics glance (N5): which
/// routine this is, Water Lock (rain and sweat fire false touches mid-run), and End.
/// Mirrors the native Workout app's controls page so the swipe-left habit transfers
/// (and the strength pager's controls page, its sibling).
struct WorkoutControlsView: View {
    let manager: WorkoutSessionManager

    var body: some View {
        VStack(spacing: 10) {
            Text(manager.routineName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            Button {
                WKInterfaceDevice.current().enableWaterLock()
            } label: {
                Label("Water Lock", systemImage: "drop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(WatchTheme.recover)

            Button(role: .destructive) {
                manager.endManually()
            } label: {
                Label("End Workout", systemImage: "xmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(WatchTheme.hot)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
