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

    /// The routine the user picked to run (via the crown launch picker). `nil` = still picking.
    @State private var chosen: Routine?

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
        } else if let chosen {
            // The user picked a routine — run its flow, returning to the picker when done.
            routedFlow(for: chosen)
        } else if orderedRoutines.isEmpty {
            // No routines yet — the run container shows the "create one on iPhone" empty state.
            RunSessionContainerView(store: store, simulate: false)
        } else {
            RoutineLaunchPicker(routines: orderedRoutines, initialIndex: initialIndex) { chosen = $0 }
        }
    }

    /// Launch the picked routine's flow by its kind, and hand `onFinish`/`onExit` back so finishing
    /// returns to the picker (rather than restarting the same session).
    @ViewBuilder private func routedFlow(for routine: Routine) -> some View {
        let blocks = routine.expandedCards.workoutBlocks()
        if blocks.count > 1 {
            WorkoutSequenceView(routineName: routine.name, blocks: blocks,
                                routineId: routine.id, recordProgressions: recordProgressions,
                                autostart: true, onExit: { chosen = nil })
        } else if routine.type == .strength {
            StrengthSessionContainerView(store: store, simulate: false, forcedRoutine: routine,
                                         recordProgressions: recordProgressions, onFinish: { chosen = nil })
        } else {
            RunSessionContainerView(store: store, simulate: false, forcedRoutine: routine,
                                    onFinish: { chosen = nil })
        }
    }

    /// All routines in a stable order for the picker (the crown pages through these).
    private var orderedRoutines: [Routine] {
        store.routines.sorted { $0.name < $1.name }
    }

    /// The picker opens on the "up next" routine, falling back to the first page.
    private var initialIndex: Int {
        guard let next = nextRoutine,
              let i = orderedRoutines.firstIndex(where: { $0.id == next.id }) else { return 0 }
        return i
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
    /// When set (from the launch picker), run this routine and auto-start — skipping this
    /// container's own launch screen, which the picker has replaced.
    var forcedRoutine: Routine?
    /// Called when the user finishes/dismisses a forced session, to return to the picker.
    var onFinish: (() -> Void)?
    @State private var manager: WorkoutSessionManager
    private let simulate: Bool

    init(store: RoutineStore, simulate: Bool, forcedRoutine: Routine? = nil, onFinish: (() -> Void)? = nil) {
        self.store = store
        self.simulate = simulate
        self.forcedRoutine = forcedRoutine
        self.onFinish = onFinish
        _manager = State(initialValue: simulate
            ? WorkoutSessionManager(backend: SimulatedWorkoutBackend())
            : WorkoutSessionManager())
    }

    var body: some View {
        Group {
            switch manager.sessionState {
            case .idle:
                // A forced session auto-starts; show a brief spinner instead of the launch screen.
                if forcedRoutine != nil {
                    ProgressView().tint(WatchTheme.run)
                } else {
                    LaunchView(routine: effectiveRoutine, estimatedDuration: plannedDuration, onStart: start)
                }
            case .active:
                WorkoutSessionPager(manager: manager)
            case .complete:
                if let summary = manager.summary {
                    WorkoutCompleteView(summary: summary) { manager.reset(); onFinish?() }
                } else {
                    ProgressView()
                }
            case .failed:
                ContentUnavailableView {
                    Label("Couldn't start", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("The workout couldn't start. Nothing was saved. Check Health permissions and try again.")
                } actions: {
                    Button("Back") { manager.reset(); onFinish?() }
                }
            }
        }
        .task {
            if (simulate || forcedRoutine != nil), manager.sessionState == .idle { start() }
        }
    }

    /// The routine to run: the picked one if forced, else the next scheduled adaptive run.
    private var effectiveRoutine: Routine? { forcedRoutine ?? nextRoutine }

    private var plannedDuration: TimeInterval { sessionPlan.plannedDuration }

    private var sessionPlan: IntervalPlan {
        let minutes = effectiveRoutine?.firstRunCard?.durationMinutes ?? 30
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
        let name = effectiveRoutine?.name ?? "Adaptive Run"
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
