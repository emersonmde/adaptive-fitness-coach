import SwiftUI
import AdaptiveCore

/// Top-level router for the in-workout experience. Picks the next routine and hands off to the
/// run flow or the strength flow by `RoutineType`. The two flows are deliberately separate:
/// running is a clock/HR-driven adaptive loop, strength is a user-advanced card sequence.
///
/// Simulator flags force a flow with a scripted backend (no HealthKit, no prompt):
/// `-simulateWorkout` → a short adaptive run; `-simulateStrength` → a short strength session.
struct SessionContainerView: View {
    let store: RoutineStore

    private let simulateRun: Bool
    private let simulateStrength: Bool

    init(store: RoutineStore) {
        self.store = store
        let args = ProcessInfo.processInfo.arguments
        self.simulateRun = args.contains("-simulateWorkout")
        self.simulateStrength = args.contains("-simulateStrength")
    }

    var body: some View {
        if simulateStrength {
            StrengthSessionContainerView(store: store, simulate: true)
        } else if simulateRun {
            RunSessionContainerView(store: store, simulate: true)
        } else if nextRoutine?.type == .strength {
            StrengthSessionContainerView(store: store, simulate: false)
        } else {
            RunSessionContainerView(store: store, simulate: false)
        }
    }

    /// The next scheduled routine of any type, used only to choose the flow.
    private var nextRoutine: Routine? {
        let calendar = Calendar.current
        let now = Date()
        let weekday = DayOfWeek(rawValue: calendar.component(.weekday, from: now)) ?? .monday
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        return store.nextRoutine(fromWeekday: weekday, hour: hour, minute: minute)
    }
}

/// The run flow: A1 launch → A2/A3 active (+ A4 overlay) → A5 complete. State lives in the
/// `WorkoutSessionManager`; this view maps it to a screen. (Previously `SessionContainerView`.)
struct RunSessionContainerView: View {
    let store: RoutineStore
    @State private var manager: WorkoutSessionManager
    private let simulate: Bool

    init(store: RoutineStore, simulate: Bool) {
        self.store = store
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
            if simulate, manager.sessionState == .idle { start() }
        }
    }

    private var plannedDuration: TimeInterval { sessionPlan.plannedDuration }

    private var sessionPlan: IntervalPlan {
        IntervalPlan.beginnerRunWalk(totalDuration: TimeInterval((nextRoutine?.durationMinutes ?? 30) * 60))
    }

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
            manager.start(config: SessionConfig(plan: sessionPlan), routineName: name)
        }
    }
}
