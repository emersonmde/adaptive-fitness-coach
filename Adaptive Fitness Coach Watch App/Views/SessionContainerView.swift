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
    /// The sync receiver, observed for the "has the phone spoken yet?" signal that separates
    /// "syncing" from a genuine empty library. `nil` in previews/tests (treated as synced).
    var connectivity: WatchConnectivityManager?
    /// Records a finished session's progression batch — micro lanes applied locally + the
    /// whole batch synced to the phone (structural proposals ride along for the P6 confirm
    /// gate). `nil` in previews/tests. Threaded to both flows.
    var recordProgression: (@MainActor (ProgressionBatch) -> Void)?

    private let simulateRun: Bool
    private let simulateStrength: Bool
    private let simulateMixed: Bool

    /// The routine the user picked to run (via the crown launch picker). `nil` = still picking.
    @State private var chosen: Routine?
    /// Set after ~10s with no context: stop waiting and show the genuine empty state, so a
    /// truly phone-less fresh install is never stuck on a spinner (N6 cuts both ways).
    @State private var syncWaitExpired = false
    /// A start-routine intent (complication / Siri / widget) may target a routine directly.
    @ObservedObject private var launchRequest = WorkoutLaunchRequest.shared

    init(store: RoutineStore,
         connectivity: WatchConnectivityManager? = nil,
         recordProgression: (@MainActor (ProgressionBatch) -> Void)? = nil) {
        self.store = store
        self.connectivity = connectivity
        self.recordProgression = recordProgression
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
            if awaitingFirstSync {
                // A fresh install's store is empty until the phone's context lands. Saying
                // "create a routine on your iPhone" here would assert *nothing exists* when
                // the truth is *not synced yet* (N6) — so say what's actually happening,
                // with the timeout above as the exit to the genuine empty state.
                SyncingView()
                    .task {
                        try? await Task.sleep(for: .seconds(10))
                        syncWaitExpired = true
                    }
            } else {
                // No routines — the run container shows the "create one on iPhone" empty state.
                RunSessionContainerView(store: store, simulate: false)
            }
        } else {
            RoutineLaunchPicker(routines: orderedRoutines, initialIndex: initialIndex) { chosen = $0 }
                .task { routeLaunchRequest() }
                .onReceive(launchRequest.$pendingRoutineId) { _ in routeLaunchRequest() }
                // The complication can fire before the phone's routine context has synced —
                // re-run the match when routines arrive so the request lands instead of dying.
                .onChange(of: store.routines) { _, _ in routeLaunchRequest() }
        }
    }

    /// Still waiting on the phone's first context: nothing synced yet and the timeout hasn't
    /// fired. Reading `hasReceivedInitialContext` in body makes the flip re-render this view.
    private var awaitingFirstSync: Bool {
        guard let connectivity else { return false }   // previews/tests: no receiver to wait on
        return !connectivity.hasReceivedInitialContext && !syncWaitExpired
    }

    /// A `StartRoutineIntent` (complication/Siri/widget) targets a routine by id — jump the
    /// picker straight into its adaptive flow. Peek-then-consume: the pending id is only
    /// consumed on a successful match, so a request arriving before the routines have synced
    /// stays queued and is retried when the store changes (see `onChange` above).
    private func routeLaunchRequest() {
        guard chosen == nil, let id = launchRequest.pendingRoutineId,
              let routine = store.routines.first(where: { $0.id.uuidString == id }) else { return }
        _ = launchRequest.consume()
        chosen = routine
    }

    /// Launch the picked routine's flow by its kind, and hand `onFinish`/`onExit` back so finishing
    /// returns to the picker (rather than restarting the same session).
    @ViewBuilder private func routedFlow(for routine: Routine) -> some View {
        let blocks = routine.expandedCards.workoutBlocks()
        if blocks.count > 1 {
            WorkoutSequenceView(routineName: routine.name, blocks: blocks,
                                routineId: routine.id, recordProgression: recordProgression,
                                autostart: true, onExit: { chosen = nil })
        } else if routine.type == .strength {
            StrengthSessionContainerView(store: store, simulate: false, forcedRoutine: routine,
                                         recordProgression: recordProgression, onFinish: { chosen = nil })
        } else {
            RunSessionContainerView(store: store, simulate: false, forcedRoutine: routine,
                                    recordProgression: recordProgression,
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

}

/// The honest first-launch state: the store is empty because the phone hasn't synced yet, not
/// because no routines exist. Quiet by design — a spinner and one line, and the container's
/// timeout guarantees it can't outlive a phone that never answers.
private struct SyncingView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Syncing from iPhone…")
                .font(.caption)
                .foregroundStyle(WatchTheme.textSecondary)
        }
    }
}

/// The forced-session auto-start moment (the picker or an intent already chose the routine) —
/// one quiet word under the spinner so the wait isn't anonymous.
struct StartingView: View {
    var tint: Color

    var body: some View {
        VStack(spacing: 8) {
            ProgressView().tint(tint)
            Text("Starting…")
                .font(.caption)
                .foregroundStyle(WatchTheme.textSecondary)
        }
    }
}

/// The `.complete`-but-no-summary gap (the manager is still assembling totals). Normally
/// sub-second; label it honestly and, if it drags past ~5s, surface an exit that runs the same
/// reset path as the failed branch — a wedged "done" screen is worse than the missing stats
/// (DESIGN-PRINCIPLES #13: failure states always have an exit).
struct WrappingUpView: View {
    var tint: Color
    let onExit: () -> Void

    @State private var offerExit = false

    var body: some View {
        VStack(spacing: 8) {
            ProgressView().tint(tint)
            Text("Wrapping up…")
                .font(.caption)
                .foregroundStyle(WatchTheme.textSecondary)
            if offerExit {
                Button("Done", action: onExit)
                    .tint(tint)
            }
        }
        .animation(WatchTheme.Motion.settle, value: offerExit)
        .task {
            try? await Task.sleep(for: .seconds(5))
            offerExit = true
        }
    }
}

/// Await a post-workout finalization step, but never let it wedge the Done button: if
/// `operation` hasn't returned within `timeoutSeconds`, give up and proceed. Used for the
/// effort-score write, which awaits the OS's background workout finalize — a hang there is the
/// OS's problem, not something to make the user stare at (the write is best-effort anyway, N6).
@MainActor
func awaitBestEffort(timeoutSeconds: TimeInterval, _ operation: @escaping @MainActor () async -> Void) async {
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await operation() }
        group.addTask { try? await Task.sleep(for: .seconds(timeoutSeconds)) }
        // First finisher wins: either the operation completed, or the timeout says move on.
        await group.next()
        group.cancelAll()
    }
}

/// The run flow: A1 launch → A2/A3 active (+ A4 overlay) → A5 complete. State lives in the
/// `WorkoutSessionManager`; this view maps it to a screen. (Previously `SessionContainerView`.)
struct RunSessionContainerView: View {
    let store: RoutineStore
    /// When set (from the launch picker), run this routine and auto-start — skipping this
    /// container's own launch screen, which the picker has replaced.
    var forcedRoutine: Routine?
    /// Persists the session outcome's progression batch (micro seeds applied + structural
    /// shape changes proposed — local apply + sync to phone).
    var recordProgression: (@MainActor (ProgressionBatch) -> Void)?
    /// Called when the user finishes/dismisses a forced session, to return to the picker.
    var onFinish: (() -> Void)?
    @State private var manager: WorkoutSessionManager
    /// Seeds actually used this session (defaults → possibly calibrated at start).
    @State private var activeCard: RunCard?
    /// The routine this session actually started from, snapshotted at start — `nextRoutine`
    /// is wall-clock-derived and can point at a *different* routine by the time a long run
    /// completes, which would attribute the outcome to the wrong card.
    @State private var activeRoutineId: UUID?
    private let simulate: Bool

    init(store: RoutineStore, simulate: Bool, forcedRoutine: Routine? = nil,
         recordProgression: (@MainActor (ProgressionBatch) -> Void)? = nil,
         onFinish: (() -> Void)? = nil) {
        self.store = store
        self.simulate = simulate
        self.forcedRoutine = forcedRoutine
        self.recordProgression = recordProgression
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
                    StartingView(tint: WatchTheme.run)
                } else {
                    LaunchView(routine: effectiveRoutine, estimatedDuration: plannedDuration, onStart: start)
                }
            case .active:
                WorkoutSessionPager(manager: manager)
            case .complete:
                if let summary = manager.summary {
                    WorkoutCompleteView(
                        summary: summary,
                        saveState: manager.healthSaveState,
                        notePreview: { effort in progressionNote(for: summary, effort: effort) },
                        onDone: { effort in
                            // Emit progression ONCE, on Done, with the rating (so a high rating
                            // holds rather than advances). Then write Health and tear down —
                            // reset clears the backend the write needs. The write awaits the
                            // background finalize, so it races a timeout: if the OS wedges,
                            // the effort is skipped (best-effort) rather than wedging Done.
                            recordOutcome(summary, effort: effort)
                            Task {
                                if let effort {
                                    await awaitBestEffort(timeoutSeconds: 5) {
                                        await manager.writeEffort(effort)
                                    }
                                }
                                manager.reset(); onFinish?()
                            }
                        }
                    )
                } else {
                    WrappingUpView(tint: WatchTheme.run) { manager.reset(); onFinish?() }
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

    /// The card driving this session: shape (warmup/block/cooldown) and seeds (run/walk) both
    /// come from it; the default card covers the no-routine "just run" case.
    private var sessionCard: RunCard { activeCard ?? effectiveRoutine?.firstRunCard ?? RunCard() }

    private var sessionPlan: IntervalPlan { IntervalPlan.plan(for: sessionCard) }

    /// Turn the finished session into next time's seeds and persist them if they moved —
    /// the cross-session half of "adaptive" (N7). Once per completion (`.task` on the
    /// summary screen); simulate sessions never persist.
    private func recordOutcome(_ summary: SessionSummary, effort: Int? = nil) {
        guard !simulate,
              let record = recordProgression,
              let routineId = activeRoutineId else { return }
        let card = sessionCard
        var outcome = RunSessionOutcome(summary: summary)
        outcome.perceivedEffort = effort
        let current = RunSeeds(runSeconds: card.runSeconds, walkSeconds: card.walkSeconds)
        let blockSeconds = card.durationMinutes * 60
        let evaluation = RunProgressionPolicy().evaluate(current: current, outcome: outcome,
                                                         blockSeconds: blockSeconds)
        let next = evaluation.seeds
        guard next != current || !card.seedsCalibrated else { return }
        let update = RunProgressionUpdate(cardId: card.id,
                                          runSeconds: next.runSeconds, walkSeconds: next.walkSeconds,
                                          reason: evaluation.reason.summary, blockSeconds: blockSeconds)
        // A shape graduation (walk shrink / continuous) is structural (P6): proposed, not
        // applied — the phone gates it behind a confirm. Everything else applies as before.
        if evaluation.isStructural, next != current {
            record(ProgressionBatch(routineId: routineId, runProposals: [update],
                                    perceivedEffort: effort, sessionDate: Date()))
        } else {
            record(ProgressionBatch(routineId: routineId, runUpdates: [update],
                                    perceivedEffort: effort, sessionDate: Date()))
        }
    }

    /// Live preview of the "Next run" note as the user turns the effort crown — shows the
    /// rating's effect on next session before they leave (what Apple's rating can't do).
    private func progressionNote(for summary: SessionSummary, effort: Int?) -> String? {
        let card = sessionCard
        var outcome = RunSessionOutcome(summary: summary)
        outcome.perceivedEffort = effort
        let current = RunSeeds(runSeconds: card.runSeconds, walkSeconds: card.walkSeconds)
        let blockSeconds = card.durationMinutes * 60
        let evaluation = RunProgressionPolicy().evaluate(current: current, outcome: outcome,
                                                         blockSeconds: blockSeconds)
        let note = RunSeeds.progressionNote(from: current, to: evaluation.seeds, blockSeconds: blockSeconds)
        guard let note else { return nil }
        return evaluation.isStructural ? "\(note) — confirm on iPhone" : note
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
            // Compressed plan + small adaptation windows so a full adaptive run plays out
            // quickly for testing/demo (~45s of plan). The 25s warmup exists to demo cadence
            // run-detection: the script's sustained running cadence cuts it short ~13s in.
            let plan = IntervalPlan.beginnerRunWalk(
                warmup: 25, runDuration: 6, walkDuration: 8, cycles: 2, cooldown: 2
            )
            let adaptation = AdaptationConfig(
                backOffWindow: 3, hardBackOffWindow: 2, hardBackOffMinRun: 2,
                extendWindow: 4, recoverWindow: 3, recoveryDropBPM: 20,
                minRunDuration: 2, minWalkDuration: 2,
                runExtendIncrement: 6, walkLengthenIncrement: 4, maxWalkDuration: 30
            )
            manager.start(config: SessionConfig(plan: plan), routineName: name, adaptationConfig: adaptation)
        } else {
            // Zero-config cold start: a card whose seeds have never been touched by evidence
            // gets one silent Health-history calibration before the first plan is built, so
            // an experienced runner's first session is already a normal run. Any failure
            // keeps the conservative defaults (N6).
            Task {
                var card = sessionCard
                activeRoutineId = effectiveRoutine?.id // snapshot before the clock can move on
                if card.needsCalibration, let seeds = await HealthFitnessCalibrator.calibratedSeeds() {
                    card.runSeconds = seeds.runSeconds
                    card.walkSeconds = seeds.walkSeconds
                }
                activeCard = card
                manager.start(config: SessionConfig(plan: IntervalPlan.plan(for: card)), routineName: name)
            }
        }
    }
}
