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
    private(set) var routineName: String = "Adaptive Run"

    private let injectedBackend: WorkoutBackend?
    private let autoTick: Bool
    private var backend: WorkoutBackend?

    /// Largest time step credited to the engine in one tick. Caps background catch-up so a
    /// resume after suspension can't fast-forward through whole intervals in a single step.
    private let maxTickDelta: TimeInterval = 3

    // Engine
    private var machine: IntervalStateMachine?
    private var latestZone: Int?

    // Ticking
    private var tickTask: Task<Void, Never>?
    private var lastTickDate: Date?
    private var adaptationClearTask: Task<Void, Never>?
    private var isFinishing = false

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
        guard sessionState == .idle else { return }
        self.routineName = routineName

        let backend = injectedBackend ?? HealthKitWorkoutBackend()
        self.backend = backend
        backend.onHeartRate = { [weak self] hr in self?.receiveHeartRate(hr) }
        backend.onZoneChange = { [weak self] zone in self?.receiveZone(zone) }
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

    /// The session failed after starting (sensor loss, OS termination). Stop the loop and
    /// surface the failure rather than ticking guidance against a dead workout (N6).
    private func handleFailure() {
        guard sessionState == .active else { return }
        tickTask?.cancel(); tickTask = nil
        backend = nil
        sessionState = .failed
    }

    // MARK: - Signal intake (also the test seams)

    func receiveHeartRate(_ hr: Double) {
        currentHeartRate = hr
    }

    func receiveZone(_ zone: Int?) {
        latestZone = zone
        currentZoneIndex = zone
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

        let result = machine.tick(deltaTime: delta, currentZone: latestZone)
        self.machine = machine // write back the mutated value type

        currentPhase = machine.currentPhase
        intervalElapsed = machine.intervalElapsed
        intervalTarget = machine.currentTargetDuration ?? intervalTarget
        sessionElapsed = machine.sessionElapsed
        intervalsCompleted = machine.intervalsCompleted

        if let transition = result.transition {
            haptics.play(for: transition.to.isRun ? .toRun : .toWalk)
        }
        if let adaptation = result.adaptation {
            showAdaptation(adaptation)
        }
        if result.isComplete {
            finish()
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
    func endManually() {
        finish()
    }

    private func end() async {
        tickTask?.cancel()
        tickTask = nil

        let totals = await backend?.end() ?? WorkoutTotals()
        summary = SessionSummary(
            totalDuration: machine?.sessionElapsed ?? sessionElapsed,
            totalDistance: totals.distanceMeters,
            averageHeartRate: totals.averageHeartRate,
            totalRunDuration: machine?.totalRunDuration ?? 0,
            totalWalkDuration: machine?.totalWalkDuration ?? 0,
            intervalsCompleted: machine?.intervalsCompleted ?? 0,
            adaptationsApplied: machine?.adaptationsApplied ?? 0
        )

        sessionState = .complete
        haptics.playComplete()
    }

    /// Reset to idle so a new session can start (e.g. after dismissing the summary).
    func reset() {
        tickTask?.cancel(); tickTask = nil
        adaptationClearTask?.cancel(); adaptationClearTask = nil
        isFinishing = false
        backend = nil
        machine = nil
        latestZone = nil
        currentHeartRate = 0
        currentZoneIndex = nil
        adaptationEvent = nil
        summary = nil
        intervalElapsed = 0
        sessionElapsed = 0
        intervalsCompleted = 0
        totalRunIntervals = 0
        currentPhase = nil
        sessionState = .idle
    }
}
