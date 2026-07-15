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
    private let simulateQuickLog: Bool

    /// Quick-log sheet (P6) — reachable from the routine picker's toolbar.
    @State private var showingQuickLog = false

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
        self.simulateQuickLog = args.contains("-simulateQuickLog")
    }

    var body: some View {
        content
            // The quick-log sheet lives at the TOP level, not inside the picker branch: the
            // complication/intent must reach it from any non-session state — empty library,
            // still syncing, picker — a meal log needs no routines (N4).
            .sheet(isPresented: $showingQuickLog) {
                if let connectivity {
                    QuickLogView(queueOffline: { connectivity.queueQuickLogOffline($0) }) {
                        showingQuickLog = false
                    }
                }
            }
            .task { routeQuickLogRequest() }
            // @Published publishes during willSet — the property still holds the OLD value
            // here, so defer one main-actor turn before consuming (the WeekView Siri
            // warm-start lesson).
            .onReceive(launchRequest.$pendingQuickLog) { pending in
                if pending { Task { @MainActor in routeQuickLogRequest() } }
            }
    }

    @ViewBuilder private var content: some View {
        if simulateQuickLog {
            // The only way to see the quick-log flow without hardware (paired-sim WC is
            // unreliable) — the park is a no-op here.
            NavigationStack { QuickLogView(queueOffline: { _ in }, initialText: "Chicken caesar salad") }
        } else if simulateMixed {
            WorkoutSequenceView(routineName: "Mixed Demo", blocks: Self.demoMixedBlocks, simulate: true)
        } else if simulateStrength {
            StrengthSessionContainerView(store: store, simulate: true)
        } else if simulateRun {
            RunSessionContainerView(store: store, simulate: true)
        } else if let chosen {
            // The user picked a routine — run its flow, returning to the picker when done.
            routedFlow(for: chosen)
        } else if orderedRoutines.isEmpty {
            if let connectivity, !connectivity.hasReceivedInitialContext {
                // A fresh install's store is empty until the phone's context lands. Saying
                // "create a routine on your iPhone" here would assert *nothing exists* when
                // the truth is *not synced yet* (N6) — so say what's actually happening.
                // After the timeout the phone still hasn't spoken, and that must NOT read
                // as confirmed-empty either (W1): the watch keeps listening (the context
                // applies whenever it arrives and this view re-renders on the flip), so the
                // settled state says exactly that.
                if syncWaitExpired {
                    WaitingForPhoneView()
                } else {
                    SyncingView()
                        .task {
                            try? await Task.sleep(for: .seconds(10))
                            syncWaitExpired = true
                        }
                }
            } else {
                // The phone HAS spoken and there really are zero routines — the run
                // container shows the honest "create one on iPhone" empty state.
                RunSessionContainerView(store: store, simulate: false)
            }
        } else {
            NavigationStack {
                RoutineLaunchPicker(routines: orderedRoutines, initialIndex: initialIndex) { chosen = $0 }
                    .toolbar {
                        // Quick-log (P6): the one non-workout action on the wrist. Quiet
                        // toolbar door — the picker's Start stays the dominant element.
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingQuickLog = true
                            } label: {
                                Image(systemName: "fork.knife")
                            }
                            .accessibilityLabel("Log a meal")
                        }
                    }
            }
            .task { routeLaunchRequest() }
            .onReceive(launchRequest.$pendingRoutineId) { _ in routeLaunchRequest() }
            // The complication can fire before the phone's routine context has synced —
            // re-run the match when routines arrive so the request lands instead of dying.
            .onChange(of: store.routines) { _, _ in routeLaunchRequest() }
        }
    }

    /// The quick-log complication / `LogMealIntent` wants the meal sheet. Consume even when
    /// dropped — an in-progress session keeps the screen (N5); the tap still opened the app,
    /// and a stale request must not pop a sheet over a workout minutes later.
    private func routeQuickLogRequest() {
        guard launchRequest.consumeQuickLog() else { return }
        guard chosen == nil, !simulateRun, !simulateStrength, !simulateMixed, !simulateQuickLog
        else { return }
        showingQuickLog = true
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
/// because no routines exist. The status line paints with the spinner from the first frame —
/// a wrist peek is ≤5s, and a bare spinner reads as "hung" (W3). The container's timeout
/// hands off to `WaitingForPhoneView`, never to a fabricated empty state.
private struct SyncingView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Syncing from iPhone…")
                .font(.caption)
                .foregroundStyle(WatchTheme.textSecondary)
        }
    }
}

/// The sync timeout elapsed and the phone never spoke (W1). Not an error and not "no routines
/// exist" — the watch is still listening (context applies whenever it arrives), so say that
/// instead of asserting an empty library the phone never confirmed (N6).
private struct WaitingForPhoneView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone.slash")
                .font(.title3)
                .foregroundStyle(WatchTheme.textSecondary)
            Text("Waiting for your iPhone…")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Keep the app open — the watch is still listening.")
                .font(.caption2)
                .foregroundStyle(WatchTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
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
    /// When this session started — the comparison query's exclusion boundary (the
    /// just-finished workout must not compare against itself).
    @State private var sessionStart: Date?
    /// Summary comparison lines (P6.1), filled asynchronously from Health history; nil while
    /// loading, empty when there's honestly nothing to compare against.
    @State private var comparisons: [RunComparison.Line]?
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
                    LaunchView(routine: effectiveRoutine, estimatedDuration: plannedDuration,
                               doneToday: doneToday, nextDayLabel: nextDayLabel, onStart: start)
                }
            case .active:
                WorkoutSessionPager(manager: manager)
            case .complete:
                if let summary = manager.summary {
                    WorkoutCompleteView(
                        summary: summary,
                        saveState: manager.healthSaveState,
                        comparisons: comparisons,
                        // Discardable only when the session ended before the first planned
                        // run interval could finish — a mis-tap-sized workout (W20).
                        canDiscard: summary.endedEarly
                            && summary.totalDuration < TimeInterval(sessionCard.runSeconds),
                        notePreview: { effort in progressionNote(for: summary, effort: effort) },
                        onDiscard: {
                            // The user called the workout a mis-tap: delete our just-saved
                            // workout, no progression, no done-today marker, back to launch.
                            Task {
                                comparisons = nil
                                await awaitBestEffort(timeoutSeconds: 5) { _ = await manager.discard() }
                                onFinish?()
                            }
                        },
                        onDone: { effort, userAdjusted in
                            // Emit progression ONCE, on Done, with the rating (so a high rating
                            // holds rather than advances). Then write Health and tear down —
                            // reset clears the backend the write needs. The write awaits the
                            // background finalize, so it races a timeout: if the OS wedges,
                            // the effort is skipped (best-effort) rather than wedging Done.
                            // Only a USER-adjusted rating gates progression — an untouched
                            // suggestion is our own objective signals echoed back, and feeding
                            // it into the high-effort gate would double-count them (it still
                            // records to Health below, per the prefill decision).
                            recordOutcome(summary, effort: userAdjusted ? effort : nil)
                            // Done-today receipt (W22): the launch screen shows the closed
                            // loop for the rest of the day. Real, completed sessions only —
                            // an ended-early bail must not read back as "Done today ✓".
                            if !simulate, !summary.endedEarly, let routineId = activeRoutineId {
                                LastCompletionStore.shared.recordCompletion(routineId: routineId)
                            }
                            Task {
                                if let effort {
                                    await awaitBestEffort(timeoutSeconds: 5) {
                                        await manager.writeEffort(effort)
                                    }
                                }
                                comparisons = nil
                                manager.reset(); onFinish?()
                            }
                        }
                    )
                    .task {
                        // Fill the reserved comparison slot from Health history — bounded so
                        // a slow first HealthKit query can never stall past a glance; the
                        // slot simply stays silent (N6: no line beats a late/hollow one).
                        guard comparisons == nil else { return }
                        await awaitBestEffort(timeoutSeconds: 3) {
                            await loadComparisons(for: summary)
                        }
                    }
                } else {
                    WrappingUpView(tint: WatchTheme.run) { manager.reset(); onFinish?() }
                }
            case let .failedToStart(cause):
                WorkoutFailedView(failure: .start(cause)) {
                    RetryFailedActions(
                        onRetry: { manager.reset(); start() },
                        onBack: { manager.reset(); onFinish?() }
                    )
                }
            case let .failedMidSession(elapsed):
                WorkoutFailedView(failure: .midSession(elapsed: elapsed)) {
                    Button("Done") { manager.reset(); onFinish?() }
                }
            }
        }
        .task {
            if (simulate || forcedRoutine != nil), manager.sessionState == .idle { start() }
        }
    }

    /// Whether the up-next routine already completed a session today (W22).
    private var doneToday: Bool {
        guard !simulate, let routine = effectiveRoutine else { return false }
        return LastCompletionStore.shared.completedToday(routineId: routine.id)
    }

    /// The routine's next repeat day after today, for the "Next: Thu" receipt line.
    private var nextDayLabel: String? {
        effectiveRoutine.flatMap { LastCompletionStore.nextDayLabel(repeatDays: $0.repeatDays) }
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
        sessionStart = Date()
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
                runExtendIncrement: 6, walkLengthenIncrement: 4, maxWalkDuration: 30,
                // Scale the convergence grid/slew with the compressed 6s runs — the default
                // 15s grid would floor every demo back-off to the 2s minimum.
                convergenceRounding: 2, maxUpwardConvergenceStep: 4
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
                manager.start(config: SessionConfig(plan: IntervalPlan.plan(for: card)),
                              routineName: name, routineId: activeRoutineId)
            }
        }
    }

    /// Build the summary's comparison lines from Health history (P6.1). Under `-simulateWorkout`
    /// canned lines stand in after a short beat (the sim's compressed ~12s runs would collapse
    /// every honest delta into the "even" band); `-simulateNoHistory` demos the empty slot.
    private func loadComparisons(for summary: SessionSummary) async {
        if simulate {
            // Mirror the real pipeline's W19 gate: an aborted sim run must render the same
            // silence the production path would, or the sim demo shows a state that can't exist.
            guard !summary.endedEarly,
                  !ProcessInfo.processInfo.arguments.contains("-simulateNoHistory") else {
                comparisons = []
                return
            }
            try? await Task.sleep(for: .milliseconds(600))   // show the slot filling in
            comparisons = [
                RunComparison.Line(label: "vs last run", delta: "+2:10 running", improved: true),
                RunComparison.Line(label: "vs 28-day baseline", delta: "+1:50 running", improved: true),
            ]
            return
        }
        let current = RunDigest(summary: summary, routineId: activeRoutineId)
        let history = await HealthRunDigestReader.history(
            routineId: activeRoutineId, before: sessionStart ?? Date())
        var lines: [RunComparison.Line] = []
        // "Last run" skips aborts (W19): an ended-early bail is a fact for Health, never a
        // comparison baseline.
        if let line = RunComparison.vsLastRun(current: current,
                                              previous: RunComparison.lastComparable(in: history.all)) {
            lines.append(line)
        }
        if let line = RunComparison.vsBaseline(current: current, history: history.window) {
            lines.append(line)
        }
        comparisons = lines
    }
}
