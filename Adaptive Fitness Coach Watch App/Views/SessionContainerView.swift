import SwiftUI
import AdaptiveCore

/// Top-level router for the in-workout experience. Picks the next routine and hands off to the
/// right flow. A single-block routine (all run, or all strength) uses its dedicated container with
/// the full launch/summary; a mixed routine (run + strength) walks its blocks in sequence,
/// switching Apple workouts automatically (`WorkoutWalkerView`). The active screens are the same
/// ones either way.
///
/// Simulator flags force a flow with a scripted backend (no HealthKit, no prompt):
/// `-simulateWorkout` → a short adaptive run; `-simulateStrength` → a short strength session.
struct SessionContainerView: View {
    let store: RoutineStore
    /// Records a finished session's weight/rep bumps against a routine (local apply + sync to phone).
    /// `nil` in previews/tests. Threaded to the strength flows; runs don't have a seed to persist.
    var recordProgressions: (@MainActor (UUID, [ProgressionUpdate]) -> Void)?

    private let simulateRun: Bool
    private let simulateStrength: Bool
    private let simulateMixed: Bool

    init(store: RoutineStore, recordProgressions: (@MainActor (UUID, [ProgressionUpdate]) -> Void)? = nil) {
        self.store = store
        self.recordProgressions = recordProgressions
        let args = ProcessInfo.processInfo.arguments
        self.simulateRun = args.contains("-simulateWorkout")
        self.simulateStrength = args.contains("-simulateStrength")
        self.simulateMixed = args.contains("-simulateMixed")
    }

    var body: some View {
        if simulateMixed {
            WorkoutSequenceView(routineName: "Mixed Demo", blocks: Self.demoMixedBlocks, simulate: true)
        } else if simulateStrength {
            StrengthSessionContainerView(store: store, simulate: true)
        } else if simulateRun {
            RunSessionContainerView(store: store, simulate: true)
        } else if blocks.count > 1, let routine = nextRoutine {
            WorkoutSequenceView(routineName: routine.name, blocks: blocks,
                                routineId: routine.id, recordProgressions: recordProgressions)
        } else if nextRoutine?.type == .strength {
            StrengthSessionContainerView(store: store, simulate: false, recordProgressions: recordProgressions)
        } else {
            RunSessionContainerView(store: store, simulate: false)
        }
    }

    /// A short scripted mixed routine (a run, then two strength moves) for the Simulator/UITest —
    /// the only way to exercise the run→strength workout handoff without a device.
    static var demoMixedBlocks: [WorkoutBlock] {
        let cards: [WorkoutCard] = [
            .run(RunCard(durationMinutes: 1)),
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
            .rest(RestCard(seconds: 30)),
            .exercise(StrengthExerciseItem(exerciseId: "db_curl", reps: 12, seedWeight: .lb(12.5))),
        ]
        return cards.workoutBlocks()
    }

    /// The next scheduled routine of any type, used to choose the flow.
    private var nextRoutine: Routine? {
        let calendar = Calendar.current
        let now = Date()
        let weekday = DayOfWeek(rawValue: calendar.component(.weekday, from: now)) ?? .monday
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        return store.nextRoutine(fromWeekday: weekday, hour: hour, minute: minute)
    }

    /// The next routine's Apple-workout blocks (run/strength runs of cards). More than one ⇒ mixed.
    private var blocks: [WorkoutBlock] {
        (nextRoutine?.expandedCards ?? []).workoutBlocks()
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
        let minutes = nextRoutine?.firstRunCard?.durationMinutes ?? 30
        return IntervalPlan.beginnerRunWalk(totalDuration: TimeInterval(minutes * 60))
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
            // Compressed plan + small adaptation windows so a full adaptive run plays out quickly
            // for testing/demo (~25s of plan).
            let plan = IntervalPlan.beginnerRunWalk(
                warmup: 2, runDuration: 6, walkDuration: 5, cycles: 2, cooldown: 2
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
