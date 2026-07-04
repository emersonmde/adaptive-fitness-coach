import Foundation
import AdaptiveCore

/// The lifecycle state of the on-watch workout, driving which screen shows.
enum SessionState: Equatable {
    case idle
    case active
    case complete
    /// The workout could not start, or failed after starting. Nothing was saved (N2/N6).
    case failed
}

/// Where HealthKit finalization stands after the session ends. The summary shows the moment
/// the user stops (the engine already knows time/intervals); the OS finishes persisting the
/// workout in the background and this drives the one status line — never claim "Saved" before
/// the OS confirms it (N2/N6), never freeze the UI waiting for it.
enum HealthSaveState: Equatable {
    case saving
    case saved
    /// Finalization reported an error. The workout data may still be in Health (the builder
    /// collected live), but we can't confirm — say so instead of pretending.
    case unconfirmed
}

/// Drives the adaptive interval loop on top of a `WorkoutBackend` (real HealthKit or a
/// scripted simulator). It ticks the pure `IntervalStateMachine` once a second, feeding it the
/// latest zone the backend reports, and turns the engine's output into observed UI state plus
/// haptics. All adaptation intelligence lives in `AdaptiveCore`; this is the device shell.
///
/// Testability: inject a backend and set `autoTick: false`, then call `begin` and drive
/// `tick(delta:)`/`receiveZone(_:)` directly for fully deterministic coverage without a clock.
@MainActor
@Observable
final class WorkoutSessionManager {
    // Observed UI state
    private(set) var sessionState: SessionState = .idle
    private(set) var currentPhase: IntervalPhase?
    private(set) var intervalElapsed: TimeInterval = 0
    private(set) var intervalTarget: TimeInterval = 0
    private(set) var sessionElapsed: TimeInterval = 0
    /// Seconds left in the current interval — `intervalTarget − intervalElapsed`, floored at 0.
    /// The glance timer shows this counting **down**: mid-effort the runner's question is "how
    /// much longer", not "how long so far" (the session clock stays count-up for the "so far"
    /// job). Pure derivation from tick state, so it's as clock-free and testable as the rest.
    var intervalRemaining: TimeInterval { max(0, intervalTarget - intervalElapsed) }
    private(set) var currentHeartRate: Double = 0
    private(set) var currentZoneIndex: Int?
    /// The aerobic target zone position (1-based), exposed so the zone bar can mark the band.
    private(set) var targetZone = 2
    /// Run intervals completed so far and the plan's total, for the ambient progress readout.
    private(set) var intervalsCompleted = 0
    private(set) var totalRunIntervals = 0
    /// The most recent adaptation, for a brief glanceable on-screen cue. Cleared after a few
    /// seconds. Carries the action (direction) rather than a sentence to read mid-run (N5).
    private(set) var adaptationEvent: AdaptationEvent?
    private(set) var summary: SessionSummary?
    private(set) var healthSaveState: HealthSaveState = .saving
    private(set) var routineName: String = "Adaptive Run"

    private let injectedBackend: WorkoutBackend?
    private let autoTick: Bool
    private var backend: WorkoutBackend?
    /// The finished backend, retained past `end()` so a post-summary effort rating can relate
    /// its score to the saved workout. Cleared on `reset()`.
    private var finishedBackend: WorkoutBackend?

    /// Largest time step credited to the engine in one tick. Caps background catch-up so a
    /// resume after suspension can't fast-forward through whole intervals in a single step.
    private let maxTickDelta: TimeInterval = 3

    // Engine
    private var machine: IntervalStateMachine?
    private var latestZone: Int?
    /// Latest raw heart rate fed to the engine for recovery math; nil until the first sample
    /// so the engine never sees a fabricated 0 bpm (N6).
    private var latestHeartRate: Double?
    /// Seconds since the last sensor sample (zone or HR), accumulated from tick deltas so the
    /// expiry is clock-free and testable through the `autoTick: false` seam. Sensor dropout
    /// (loose band, wrist off) stops the callbacks but would otherwise leave the *last* zone
    /// driving adaptations forever — a fabricated signal (N6). Past the limit, the engine gets
    /// `nil` and the UI shows "--" until a fresh sample arrives.
    private var secondsSinceLastSample: TimeInterval = 0
    /// How long a zone/HR sample stays trusted. Zone updates arrive sparsely (only on change),
    /// but HR samples land every few seconds while the sensor has contact — so 15s of *total*
    /// silence reliably means dropout, not a steady zone.
    private let sampleStalenessLimit: TimeInterval = 15
    /// True while the last sample is older than `sampleStalenessLimit` — the UI's cue to show
    /// "--" instead of a confidently wrong BPM.
    private(set) var heartRateIsStale = false
    /// Detects "started running" from cadence during the warmup, to end it early.
    private var cadenceDetector = RunningCadenceDetector()
    /// Detects "still running after the walk cue" from the same cadence stream, driving the
    /// repeated haptic nudge and the on-screen mismatch pulse.
    private var complianceMonitor = WalkComplianceMonitor()
    /// True while the user is demonstrably still running during a walk phase. The active
    /// screen pulses on this — the visual protest for a missed walk cue.
    private(set) var gaitMismatch = false
    /// Walks the user ran straight through after the full nudge budget (their call —
    /// excluded from struggle signals in progression).
    private var walksDefied = 0
    private var currentWalkDefied = false
    /// Set when the user ends the workout before the plan finishes — a progression signal.
    private var endedEarly = false

    // Ticking
    private var tickTask: Task<Void, Never>?
    private var lastTickDate: Date?
    private var adaptationClearTask: Task<Void, Never>?
    private var isFinishing = false
    /// Guards `begin` across its suspension points: `sessionState` stays `.idle` while the
    /// backend starts, so without this a double-tap on Start could pass the state guard twice
    /// and leave a second, orphaned `HKWorkoutSession` running.
    private var isBeginning = false
    /// Incremented on `reset()`. The background HealthKit finalize captures the generation it
    /// belongs to, so a slow finalize from session A can never write its totals into session
    /// B's summary after a reset-and-restart.
    private var sessionGeneration = 0
    /// The in-flight background finalize, exposed so tests can `await` it deterministically
    /// instead of yield-polling.
    private(set) var finalizeTask: Task<Void, Never>?

    private let haptics = HapticManager()

    /// - Parameters:
    ///   - backend: sensor/zone source. Defaults to real HealthKit when nil.
    ///   - autoTick: when false, the 1s timer is not started (tests drive `tick` themselves).
    init(backend: WorkoutBackend? = nil, autoTick: Bool = true) {
        self.injectedBackend = backend
        self.autoTick = autoTick
    }

    // MARK: - Start

    /// Production entry: kick off the workout and the adaptive loop asynchronously.
    func start(config: SessionConfig, routineName: String, adaptationConfig: AdaptationConfig = AdaptationConfig()) {
        guard sessionState == .idle else { return }
        Task { await begin(config: config, routineName: routineName, adaptationConfig: adaptationConfig) }
    }

    /// Set up the backend and engine and go active. Awaitable so tests can drive ticks after.
    func begin(config: SessionConfig, routineName: String, adaptationConfig: AdaptationConfig = AdaptationConfig()) async {
        guard sessionState == .idle, !isBeginning else { return }
        isBeginning = true
        defer { isBeginning = false }
        self.routineName = routineName

        let backend = injectedBackend ?? HealthKitWorkoutBackend()
        self.backend = backend
        backend.onHeartRate = { [weak self] hr in self?.receiveHeartRate(hr) }
        backend.onZoneChange = { [weak self] zone in self?.receiveZone(zone) }
        backend.onCadence = { [weak self] cadence in self?.receiveCadence(cadence) }
        backend.onFailure = { [weak self] in self?.handleFailure() }

        targetZone = config.targetZone

        do {
            try await backend.start()
        } catch {
            // Couldn't start the underlying workout. Do NOT fake a saved workout — there is
            // nothing in Health and nothing to log (N2/N6). Surface an explicit failure.
            self.backend = nil
            sessionState = .failed
            return
        }

        machine = IntervalStateMachine(
            config: SessionConfig(plan: config.plan, targetZone: config.targetZone),
            adaptationConfig: adaptationConfig
        )
        totalRunIntervals = config.plan.runIntervalCount
        currentPhase = machine?.currentPhase
        intervalTarget = machine?.currentTargetDuration ?? 0
        lastTickDate = Date()
        sessionState = .active

        if autoTick { startTicking() }
    }

    /// The session failed after starting (sensor loss, OS termination). Stop the loop, ask
    /// the backend to wind down whatever survives (fire-and-forget — the session may already
    /// be dead), and surface the failure rather than ticking against a dead workout (N6).
    private func handleFailure() {
        guard sessionState == .active else { return }
        tickTask?.cancel(); tickTask = nil
        let failedBackend = backend
        backend = nil
        Task { _ = await failedBackend?.end() }
        sessionState = .failed
    }

    // MARK: - Signal intake (also the test seams)

    func receiveHeartRate(_ hr: Double) {
        currentHeartRate = hr
        latestHeartRate = hr
        secondsSinceLastSample = 0
        heartRateIsStale = false
    }

    func receiveZone(_ zone: Int?) {
        latestZone = zone
        currentZoneIndex = zone
        // Even a nil zone is a *fresh* report from the backend ("no zone data"), distinct
        // from silence — either way the staleness clock restarts.
        secondsSinceLastSample = 0
        heartRateIsStale = false
    }

    /// Feed a cadence sample (steps/minute). During the warmup a sustained running cadence
    /// ends it early — the user said "let's go" with their feet. During a recovery walk the
    /// same stream verifies compliance (still running? → nudge).
    func receiveCadence(_ cadence: Double) {
        guard sessionState == .active, let machine else { return }
        switch currentPhase {
        case .warmupWalk:
            if cadenceDetector.update(cadence: cadence, at: machine.sessionElapsed) {
                skipWarmup()
            }
        case .walk:
            complianceMonitor.recordCadence(cadence, at: machine.sessionElapsed)
        default:
            break
        }
    }

    /// End the warmup now and start the first run — from cadence detection or the user's
    /// "Start Run" tap. Routed through the engine so the transition (and its haptic) is
    /// exactly the one a natural warmup end would produce.
    func skipWarmup() {
        guard var machine, sessionState == .active, machine.currentPhase == .warmupWalk else { return }
        let result = machine.skipCurrentSegment()
        self.machine = machine
        applyTickResult(result, from: machine)
    }

    // MARK: - Tick loop

    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.sessionState != .active { return }
                let now = Date()
                let elapsed = now.timeIntervalSince(self.lastTickDate ?? now)
                self.lastTickDate = now
                // Clamp background catch-up so a resume after suspension advances at most one
                // capped step instead of fast-forwarding through intervals and bursting haptics.
                self.tick(delta: min(elapsed, self.maxTickDelta))
            }
        }
    }

    /// Advance the engine by `delta` seconds using the latest reported zone, and reflect the
    /// result in observed state, haptics, and the adaptation banner. Internal so tests can
    /// drive it deterministically.
    func tick(delta: TimeInterval) {
        guard var machine, sessionState == .active else { return }

        // Staleness expiry: past the limit with no fresh sample, the last-known zone/HR stop
        // driving the engine — degrade to the fixed-interval path rather than adapt against a
        // signal that may be minutes old (N6). Cleared the moment a new sample arrives.
        secondsSinceLastSample += delta
        if secondsSinceLastSample > sampleStalenessLimit, !heartRateIsStale {
            heartRateIsStale = true
            latestZone = nil
            latestHeartRate = nil
            currentZoneIndex = nil
            currentHeartRate = 0 // the HR readout renders 0 as "--"
        }

        let sample = WorkoutSample(zone: latestZone, heartRate: latestHeartRate)
        let result = machine.tick(deltaTime: delta, sample: sample)
        self.machine = machine // write back the mutated value type

        applyTickResult(result, from: machine)
    }

    /// Reflect one engine step (a tick or a segment skip) into observed state, haptics, and
    /// the adaptation banner.
    private func applyTickResult(_ result: TickResult, from machine: IntervalStateMachine) {
        currentPhase = machine.currentPhase
        intervalElapsed = machine.intervalElapsed
        intervalTarget = machine.currentTargetDuration ?? intervalTarget
        sessionElapsed = machine.sessionElapsed
        intervalsCompleted = machine.intervalsCompleted

        if let transition = result.transition {
            haptics.play(for: transition.to.isRun ? .toRun : .toWalk)
            if transition.to == .walk {
                complianceMonitor.walkStarted(at: machine.sessionElapsed)
            } else {
                complianceMonitor.walkEnded()
            }
            gaitMismatch = false
            currentWalkDefied = false
        }
        if let adaptation = result.adaptation {
            showAdaptation(adaptation)
        }
        if result.isComplete {
            finish()
        }

        // Compliance check: still running after the walk cue? Re-buzz (rate-limited, capped)
        // and let the screen pulse until the feet agree — or until the budget is spent and
        // continued running is accepted as the user's call (screen calms, walk marked defied).
        if currentPhase == .walk {
            let assessment = complianceMonitor.assess(at: machine.sessionElapsed)
            if assessment.shouldNudge { haptics.playWalkNudge() }
            gaitMismatch = assessment.isMismatched
            if assessment.accepted, !currentWalkDefied {
                currentWalkDefied = true
                walksDefied += 1
            }
        } else if gaitMismatch {
            gaitMismatch = false
        }
    }

    private func showAdaptation(_ event: AdaptationEvent) {
        adaptationEvent = event
        adaptationClearTask?.cancel()
        adaptationClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.adaptationEvent = nil
        }
    }

    // MARK: - End

    /// End the session (user-initiated or natural completion). The single finishing entry
    /// point — guarded so a user tap racing a natural completion can't double-finalize.
    func finish() {
        guard sessionState == .active, !isFinishing else { return }
        isFinishing = true
        Task { await self.end() }
    }

    /// End early (user-initiated). Routed through the same guarded `finish()`.
    /// Stopping mid-*extended*-run is finishing a long run the plan didn't dare schedule,
    /// not bailing — don't let it read as a struggle to progression.
    func endManually() {
        if let machine, !machine.isComplete, !machine.currentRunIsExtended {
            endedEarly = true
        }
        finish()
    }

    /// Complete the session **immediately** from what the engine already knows — time,
    /// intervals, splits — and let HealthKit finalize in the background. The user is standing
    /// there sweating; making them stare at a frozen screen while the OS does bookkeeping is
    /// the wrong place to spend seconds. Distance/avg HR arrive with the finalize and fill in.
    private func end() async {
        tickTask?.cancel()
        tickTask = nil

        summary = SessionSummary(
            totalDuration: machine?.sessionElapsed ?? sessionElapsed,
            totalDistance: nil,
            averageHeartRate: nil,
            totalRunDuration: machine?.totalRunDuration ?? 0,
            totalWalkDuration: machine?.totalWalkDuration ?? 0,
            intervalsCompleted: machine?.intervalsCompleted ?? 0,
            adaptationsApplied: machine?.adaptationsApplied ?? 0,
            plannedRunIntervals: totalRunIntervals,
            runBackOffCount: machine?.runBackOffCount ?? 0,
            walksHitCap: machine?.walksHitCap ?? 0,
            walksDefied: walksDefied,
            fastRecoveries: machine?.fastRecoveries ?? 0,
            longestRunSeconds: machine?.longestRunInterval ?? 0,
            meanRecoveryDrop: machine?.meanRecoveryDrop,
            endedEarly: endedEarly
        )
        healthSaveState = .saving
        sessionState = .complete
        haptics.playComplete()

        // Finalize with the OS off the critical path. The backend is captured strongly so a
        // reset/dismiss can't abandon HealthKit mid-finalize; the generation token keeps a
        // slow finalize from a *previous* session from resurrecting its totals into a new
        // session's summary after reset-and-restart.
        let finishingBackend = backend
        let generation = sessionGeneration
        backend = nil
        finishedBackend = finishingBackend   // survives for the effort rating
        finalizeTask = Task { [weak self] in
            let totals = await finishingBackend?.end() ?? WorkoutTotals()
            guard let self, self.sessionGeneration == generation, self.sessionState == .complete else { return }
            if var filled = self.summary {
                filled.totalDistance = totals.distanceMeters
                filled.averageHeartRate = totals.averageHeartRate
                self.summary = filled
            }
            self.healthSaveState = totals.savedToHealth ? .saved : .unconfirmed
        }
    }

    /// Write the user's perceived-effort rating (1–10) to the finished workout in Health.
    /// Waits for the OS finalize so the workout exists before relating the score.
    func writeEffort(_ score: Int) async {
        await finalizeTask?.value
        await finishedBackend?.writeEffortScore(score)
    }

    /// Reset to idle so a new session can start (e.g. after dismissing the summary).
    func reset() {
        sessionGeneration += 1
        finalizeTask = nil
        tickTask?.cancel(); tickTask = nil
        adaptationClearTask?.cancel(); adaptationClearTask = nil
        isFinishing = false
        backend = nil
        finishedBackend = nil
        machine = nil
        latestZone = nil
        latestHeartRate = nil
        secondsSinceLastSample = 0
        heartRateIsStale = false
        cadenceDetector = RunningCadenceDetector()
        complianceMonitor = WalkComplianceMonitor()
        gaitMismatch = false
        walksDefied = 0
        currentWalkDefied = false
        endedEarly = false
        currentHeartRate = 0
        currentZoneIndex = nil
        adaptationEvent = nil
        summary = nil
        healthSaveState = .saving
        intervalElapsed = 0
        sessionElapsed = 0
        intervalsCompleted = 0
        totalRunIntervals = 0
        currentPhase = nil
        sessionState = .idle
    }
}
