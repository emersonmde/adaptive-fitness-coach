import SwiftUI
import AdaptiveCore

/// Coordinates the in-workout flow: A1 launch → A2/A3 active (+ A4 overlay) → A5 complete.
/// State lives in the `WorkoutSessionManager`; this view just maps it to a screen.
struct SessionContainerView: View {
    let store: RoutineStore
    @State private var manager: WorkoutSessionManager

    /// When launched with `-simulateWorkout`, drive a short scripted run (no HealthKit, no
    /// prompt) for end-to-end testing and demos in the Simulator.
    private let simulate: Bool

    init(store: RoutineStore) {
        self.store = store
        let simulate = ProcessInfo.processInfo.arguments.contains("-simulateWorkout")
        self.simulate = simulate
        _manager = State(initialValue: simulate
            ? WorkoutSessionManager(backend: SimulatedWorkoutBackend())
            : WorkoutSessionManager())
    }

    var body: some View {
        Group {
            switch manager.sessionState {
            case .idle:
                LaunchView(routine: nextRoutine, estimatedDuration: plannedDuration, onStart: start)
            case .active:
                WorkoutSessionPager(manager: manager)
            case .complete:
                if let summary = manager.summary {
                    WorkoutCompleteView(summary: summary) { manager.reset() }
                } else {
                    ProgressView()
                }
            case .failed:
                ContentUnavailableView {
                    Label("Couldn't start", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The workout couldn't start. Nothing was saved. Check Health permissions and try again.")
                } actions: {
                    Button("Back") { manager.reset() }
                }
            }
        }
        .task {
            // Auto-start the scripted session so the whole flow runs unattended in the sim.
            if simulate, manager.sessionState == .idle { start() }
        }
    }

    /// Planned length of the P0 session, shown as an estimate on the launch screen.
    private var plannedDuration: TimeInterval { IntervalPlan.beginnerRunWalk().plannedDuration }

    /// The next adaptive-run routine to surface on the launch screen, based on the current
    /// weekday/time. Falls back to any adaptive run if none is scheduled later today.
    private var nextRoutine: Routine? {
        let calendar = Calendar.current
        let now = Date()
        let weekday = DayOfWeek(rawValue: calendar.component(.weekday, from: now)) ?? .monday
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        if let next = store.nextRoutine(fromWeekday: weekday, hour: hour, minute: minute),
           next.type == .adaptiveRun {
            return next
        }
        return store.routines.first { $0.type == .adaptiveRun }
    }

    private func start() {
        let name = nextRoutine?.name ?? "Adaptive Run"
        if simulate {
            // Compressed plan + small adaptation windows so a full adaptive run plays out in
            // under a minute for testing/demo.
            let plan = IntervalPlan.beginnerRunWalk(
                warmup: 3, runDuration: 12, walkDuration: 10, cycles: 3, cooldown: 3
            )
            let adaptation = AdaptationConfig(
                backOffWindow: 3, extendWindow: 4, recoverWindow: 3,
                minRunDuration: 2, minWalkDuration: 2,
                runExtendIncrement: 6, walkLengthenIncrement: 4, maxWalkDuration: 30
            )
            manager.start(config: SessionConfig(plan: plan), routineName: name, adaptationConfig: adaptation)
        } else {
            // P0: every adaptive run uses the beginner run/walk seed plan; it self-corrects to HR.
            manager.start(config: SessionConfig(plan: .beginnerRunWalk()), routineName: name)
        }
    }
}
