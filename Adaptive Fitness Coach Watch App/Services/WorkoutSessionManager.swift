import Foundation
import AdaptiveCore

/// The lifecycle state of the on-watch workout, driving which screen shows.
enum SessionState: Equatable {
    case idle
    case active
    case complete
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
    private(set) var adaptationMessage: String?
    private(set) var summary: SessionSummary?
    private(set) var routineName: String = "Adaptive Run"

    private let injectedBackend: WorkoutBackend?
    private let autoTick: Bool
    private var backend: WorkoutBackend?

    // Engine
    private var machine: IntervalStateMachine?
    private var targetZoneIndex = 2
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

        if let target = await backend.preferredTargetZoneIndex() {
            targetZoneIndex = target
        }

        do {
            try await backend.start()
        } catch {
            // Couldn't start the underlying workout; surface as immediate completion.
            sessionState = .complete
            summary = SessionSummary(totalDuration: 0)
            return
        }

        machine = IntervalStateMachine(
            config: SessionConfig(plan: config.plan, targetZone: targetZoneIndex),
            adaptationConfig: adaptationConfig
        )
        currentPhase = machine?.currentPhase
        intervalTarget = machine?.currentTargetDuration ?? 0
        lastTickDate = Date()
        sessionState = .active

        if autoTick { startTicking() }
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
                let delta = now.timeIntervalSince(self.lastTickDate ?? now)
                self.lastTickDate = now
                self.tick(delta: delta)
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

        if let transition = result.transition {
            haptics.play(for: transition.to.isRun ? .toRun : .toWalk)
        }
        if let adaptation = result.adaptation {
            showAdaptation(adaptation.message)
        }
        if result.isComplete, !isFinishing {
            isFinishing = true
            Task { await self.end() }
        }
    }

    private func showAdaptation(_ message: String) {
        adaptationMessage = message
        adaptationClearTask?.cancel()
        adaptationClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.adaptationMessage = nil
        }
    }

    // MARK: - End

    /// End early (user-initiated). Same path as a natural finish.
    func endManually() {
        guard sessionState == .active else { return }
        Task { await end() }
    }

    func end() async {
        guard sessionState == .active else { return }
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
        adaptationMessage = nil
        summary = nil
        intervalElapsed = 0
        sessionElapsed = 0
        currentPhase = nil
        sessionState = .idle
    }
}
