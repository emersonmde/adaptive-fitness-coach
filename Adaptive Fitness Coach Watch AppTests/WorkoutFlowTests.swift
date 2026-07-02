import Foundation
import Testing
import AdaptiveCore
@testable import Adaptive_Fitness_Coach_Watch_App

/// Integration tests for the on-watch workout flow. They drive `WorkoutSessionManager` with a
/// silent `SimulatedWorkoutBackend` (empty script) and `autoTick: false`, so zones and time are
/// fed deterministically — the same engine that's unit-tested in AdaptiveCore, exercised here
/// through the real device-shell wiring without HealthKit or a clock.
/// A backend that fails on start (or on demand via `onFailure`) to exercise the failure paths.
@MainActor
private final class FailingBackend: WorkoutBackend {
    var onHeartRate: ((Double) -> Void)?
    var onZoneChange: ((Int?) -> Void)?
    var onCadence: ((Double) -> Void)?
    var onFailure: (() -> Void)?
    let failOnStart: Bool

    init(failOnStart: Bool = true) { self.failOnStart = failOnStart }

    struct StartError: Error {}
    func start() async throws { if failOnStart { throw StartError() } }
    func end() async -> WorkoutTotals { WorkoutTotals() }
}

@MainActor
struct WorkoutFlowTests {

    private func makeManager() -> WorkoutSessionManager {
        WorkoutSessionManager(backend: SimulatedWorkoutBackend(script: []), autoTick: false)
    }

    private func shortPlan() -> IntervalPlan {
        // warmup 2 + 2×(run 5 / walk 5) + cooldown 2
        IntervalPlan.beginnerRunWalk(warmup: 2, runDuration: 5, walkDuration: 5, cycles: 2, cooldown: 2)
    }

    private func tick(_ manager: WorkoutSessionManager, seconds: Int) {
        for _ in 0..<seconds { manager.tick(delta: 1) }
    }

    /// Completion finalizes through an async `end()` (the backend read-back is awaited), so
    /// after the session finishes we yield until the state settles to `.complete`.
    private func waitUntilComplete(_ manager: WorkoutSessionManager) async {
        for _ in 0..<200 {
            if manager.sessionState == .complete { return }
            await Task.yield()
        }
    }

    // MARK: - Lifecycle

    @Test func beginActivatesInWarmup() async {
        let manager = makeManager()
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        #expect(manager.sessionState == .active)
        #expect(manager.currentPhase == .warmupWalk)
    }

    @Test func fixedIntervalsProgressWithoutZoneData() async {
        let manager = makeManager()
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        manager.receiveZone(nil) // no zone → graceful fixed-interval path (N6)

        tick(manager, seconds: 2)            // warmup (2s) elapses
        #expect(manager.currentPhase == .run)

        tick(manager, seconds: 5)            // run (5s) elapses
        #expect(manager.currentPhase == .walk)
    }

    @Test func completesAndBuildsSummaryFromBackendTotals() async {
        let manager = makeManager()
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        manager.receiveZone(nil)

        // Drive well past the planned duration to guarantee completion.
        tick(manager, seconds: 40)
        await waitUntilComplete(manager)

        #expect(manager.sessionState == .complete)
        let summary = try? #require(manager.summary)
        // Totals come from the backend read-back (the simulated backend reports these).
        #expect(manager.summary?.totalDistance == 2400)
        #expect(manager.summary?.averageHeartRate == 138)
        #expect((manager.summary?.intervalsCompleted ?? 0) >= 2)
        _ = summary
    }

    // MARK: - Adaptation through the shell

    @Test func sustainedHotZoneShortensRunAndShowsBanner() async {
        let manager = makeManager()
        let adaptation = AdaptationConfig(backOffWindow: 3, minRunDuration: 2)
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test", adaptationConfig: adaptation)

        tick(manager, seconds: 2)            // finish warmup → into run
        #expect(manager.currentPhase == .run)

        manager.receiveZone(4)               // running hot (above target zone 2)
        tick(manager, seconds: 3)            // sustained hot ≥ backOffWindow

        // Run was cut short → now walking, an adaptation was applied, the cue is showing.
        #expect(manager.currentPhase == .walk)
        #expect(manager.adaptationEvent != nil)
    }

    @Test func heartRateReachesDisplayState() async {
        let manager = makeManager()
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        manager.receiveHeartRate(142)
        #expect(manager.currentHeartRate == 142)
    }

    // MARK: - Failure & manual end

    @Test func startFailureSurfacesFailedStateWithoutFakingCompletion() async {
        let manager = WorkoutSessionManager(backend: FailingBackend(), autoTick: false)
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        #expect(manager.sessionState == .failed)
        #expect(manager.summary == nil) // never fabricate a "saved to Health" summary (N2/N6)
    }

    @Test func runtimeFailureStopsTheSession() async {
        let backend = FailingBackend(failOnStart: false)
        let manager = WorkoutSessionManager(backend: backend, autoTick: false)
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        #expect(manager.sessionState == .active)
        backend.onFailure?() // simulate a mid-run sensor/session failure
        #expect(manager.sessionState == .failed)
    }

    @Test func endManuallyCompletesAndBuildsSummary() async {
        let manager = makeManager()
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        manager.endManually()
        await waitUntilComplete(manager)
        #expect(manager.sessionState == .complete)
        #expect(manager.summary != nil)
        // Ending before the plan finished is recorded — the progression policy's bail signal.
        #expect(manager.summary?.endedEarly == true)
    }

    @Test func naturalCompletionIsNotMarkedEndedEarly() async {
        let manager = makeManager()
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        manager.receiveZone(nil)
        tick(manager, seconds: 40)
        await waitUntilComplete(manager)
        #expect(manager.summary?.endedEarly == false)
        #expect(manager.summary?.plannedRunIntervals == 2)
    }

    // MARK: - Warmup run-detection / skip

    @Test func sustainedRunningCadenceEndsTheWarmup() async {
        let manager = makeManager()
        // Long warmup so only cadence (not the timer) can end it.
        let plan = IntervalPlan.beginnerRunWalk(warmup: 300, runDuration: 5, walkDuration: 5, cycles: 2, cooldown: 2)
        await manager.begin(config: SessionConfig(plan: plan), routineName: "Test")
        #expect(manager.currentPhase == .warmupWalk)

        // Running cadence sustained past the detector's 10s window (samples every 2.5s of
        // session time, advanced by ticks).
        for _ in 0..<6 {
            manager.receiveCadence(155)
            tick(manager, seconds: 3)
        }
        #expect(manager.currentPhase == .run)
        #expect(manager.intervalElapsed < 20) // the run started fresh, not fast-forwarded
    }

    @Test func walkingCadenceNeverEndsTheWarmup() async {
        let manager = makeManager()
        let plan = IntervalPlan.beginnerRunWalk(warmup: 300, runDuration: 5, walkDuration: 5, cycles: 1, cooldown: 2)
        await manager.begin(config: SessionConfig(plan: plan), routineName: "Test")
        for _ in 0..<20 {
            manager.receiveCadence(115) // strolling
            tick(manager, seconds: 3)
        }
        #expect(manager.currentPhase == .warmupWalk)
    }

    @Test func cadenceOutsideTheWarmupIsIgnored() async {
        let manager = makeManager()
        let plan = IntervalPlan.beginnerRunWalk(warmup: 2, runDuration: 60, walkDuration: 60, cycles: 1, cooldown: 2)
        await manager.begin(config: SessionConfig(plan: plan), routineName: "Test")
        tick(manager, seconds: 2) // warmup elapses naturally
        #expect(manager.currentPhase == .run)

        // A flood of running cadence mid-run must not skip anything.
        for _ in 0..<10 {
            manager.receiveCadence(160)
            tick(manager, seconds: 2)
        }
        #expect(manager.currentPhase == .run)
    }

    @Test func manualSkipEndsTheWarmupImmediately() async {
        let manager = makeManager()
        let plan = IntervalPlan.beginnerRunWalk(warmup: 300, runDuration: 5, walkDuration: 5, cycles: 1, cooldown: 2)
        await manager.begin(config: SessionConfig(plan: plan), routineName: "Test")
        tick(manager, seconds: 3)
        manager.skipWarmup()
        #expect(manager.currentPhase == .run)
        #expect(manager.intervalElapsed == 0)

        // Skip is warmup-only: calling it again mid-run is a no-op.
        manager.skipWarmup()
        #expect(manager.currentPhase == .run)
    }

    // MARK: - Reset

    @Test func resetReturnsToIdle() async {
        let manager = makeManager()
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        manager.receiveZone(nil)
        tick(manager, seconds: 40)
        await waitUntilComplete(manager)
        #expect(manager.sessionState == .complete)

        manager.reset()
        #expect(manager.sessionState == .idle)
        #expect(manager.summary == nil)
        #expect(manager.currentPhase == nil)
    }
}
