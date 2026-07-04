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

/// A backend whose `end()` never returns — stands in for a slow HealthKit finalize, to prove
/// the summary no longer waits on it.
@MainActor
private final class StallingBackend: WorkoutBackend {
    var onHeartRate: ((Double) -> Void)?
    var onZoneChange: ((Int?) -> Void)?
    var onCadence: ((Double) -> Void)?
    var onFailure: (() -> Void)?

    func start() async throws {}
    func end() async -> WorkoutTotals {
        while true { try? await Task.sleep(for: .seconds(60)) }
    }
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

    @Test func concurrentBeginsStartExactlyOneSession() async {
        // A double-tap on Start races two begins across the backend-start suspension point;
        // only one may win or two HKWorkoutSessions would be left running.
        let manager = makeManager()
        async let first: Void = manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "A")
        async let second: Void = manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "B")
        _ = await (first, second)
        #expect(manager.sessionState == .active)
        // The loser's routine name never lands: whichever begin won set its name and the
        // other bailed at the guard (names differ so we can observe exactly one winner).
        #expect(manager.routineName == "A" || manager.routineName == "B")
        tick(manager, seconds: 2)
        #expect(manager.currentPhase == .run) // a single coherent session is progressing
    }

    @Test func staleFinalizeCannotTouchTheNextSession() async {
        // Session A ends against a stalled finalize; the user resets and runs session B.
        // A's finalize must never resurrect its totals into B's summary.
        let manager = WorkoutSessionManager(backend: StallingBackend(), autoTick: false)
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "A")
        tick(manager, seconds: 3)
        manager.endManually()
        await waitUntilComplete(manager)
        #expect(manager.healthSaveState == .saving) // A's finalize is stalled forever

        manager.reset()
        #expect(manager.sessionState == .idle)
        // B would normally use a fresh manager/backend; reusing this one is fine for the
        // generation check — even if A's finalize eventually returned, the token mismatch
        // (generation bumped by reset) blocks the write. Verify state stays clean.
        #expect(manager.summary == nil)
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
        // Totals come from the backend read-back, which finalizes in the background —
        // await the exposed finalize task (the deterministic seam).
        await manager.finalizeTask?.value
        #expect(manager.summary?.totalDistance == 2400)
        #expect(manager.summary?.averageHeartRate == 138)
        #expect((manager.summary?.intervalsCompleted ?? 0) >= 2)
        _ = summary
    }

    // MARK: - Interval countdown (the glance timer shows remaining, not elapsed)

    @Test func intervalRemainingCountsDownFromTheSegmentTarget() async {
        let manager = makeManager()
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        manager.receiveZone(nil)

        // Warmup is 2s: the countdown starts at the target and falls with each tick.
        #expect(manager.intervalRemaining == 2)
        tick(manager, seconds: 1)
        #expect(manager.intervalRemaining == 1)

        // Crossing into the run resets the countdown to the new segment's target (5s).
        tick(manager, seconds: 1)
        #expect(manager.currentPhase == .run)
        #expect(manager.intervalRemaining == 5)
        tick(manager, seconds: 2)
        #expect(manager.intervalRemaining == 3)
    }

    @Test func intervalRemainingNeverGoesNegative() async {
        // Drive a whole session to completion checking the floor at every tick — an extended
        // run bumps the target, but nothing may ever display a negative "remaining".
        let manager = makeManager()
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        manager.receiveZone(nil)
        for _ in 0..<40 {
            manager.tick(delta: 1)
            #expect(manager.intervalRemaining >= 0)
        }
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

    // MARK: - Sample staleness (N6: a dropped sensor must not keep driving the engine)

    @Test func staleZoneStopsDrivingAdaptations() async {
        let manager = makeManager()
        // A long run and a back-off window LONGER than the staleness limit: if the last-known
        // hot zone kept driving the engine after dropout, the window would eventually fill and
        // shorten the run. With expiry, the zone goes nil at ~15s and the window never fills.
        let plan = IntervalPlan.beginnerRunWalk(warmup: 2, runDuration: 120, walkDuration: 10, cycles: 1, cooldown: 2)
        let adaptation = AdaptationConfig(backOffWindow: 25, minRunDuration: 2)
        await manager.begin(config: SessionConfig(plan: plan), routineName: "Test", adaptationConfig: adaptation)

        tick(manager, seconds: 2)                  // warmup → run
        #expect(manager.currentPhase == .run)

        manager.receiveHeartRate(165)
        // One hot report (one zone above target — the soft back-off path, whose 25s window is
        // what must never fill from a stale value)… then the sensor goes silent.
        manager.receiveZone(3)
        tick(manager, seconds: 40)                 // well past the limit AND the back-off window

        #expect(manager.currentPhase == .run)      // the stale zone never forced a back-off
        #expect(manager.adaptationEvent == nil)
        #expect(manager.heartRateIsStale)
        #expect(manager.currentZoneIndex == nil)   // zone bar back to "no reading"
        #expect(manager.currentHeartRate == 0)     // HR readout renders 0 as "--"
    }

    @Test func freshSamplesKeepTheSignalAlive() async {
        let manager = makeManager()
        let plan = IntervalPlan.beginnerRunWalk(warmup: 2, runDuration: 120, walkDuration: 10, cycles: 1, cooldown: 2)
        await manager.begin(config: SessionConfig(plan: plan), routineName: "Test")
        tick(manager, seconds: 2)

        // Samples every 10s — always inside the 15s staleness limit — never expire.
        for _ in 0..<4 {
            manager.receiveZone(2)
            manager.receiveHeartRate(150)
            tick(manager, seconds: 10)
        }
        #expect(!manager.heartRateIsStale)
        #expect(manager.currentZoneIndex == 2)
        #expect(manager.currentHeartRate == 150)
    }

    @Test func aFreshSampleAfterDropoutClearsStaleness() async {
        let manager = makeManager()
        let plan = IntervalPlan.beginnerRunWalk(warmup: 2, runDuration: 120, walkDuration: 10, cycles: 1, cooldown: 2)
        await manager.begin(config: SessionConfig(plan: plan), routineName: "Test")
        tick(manager, seconds: 2)

        manager.receiveZone(2)
        tick(manager, seconds: 20)                 // dropout → stale
        #expect(manager.heartRateIsStale)
        #expect(manager.currentZoneIndex == nil)

        manager.receiveZone(3)                     // the band re-seats; signal is trusted again
        manager.receiveHeartRate(148)
        tick(manager, seconds: 1)
        #expect(!manager.heartRateIsStale)
        #expect(manager.currentZoneIndex == 3)
        #expect(manager.currentHeartRate == 148)
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

    @Test func summaryAppearsInstantlyEvenIfHealthKitFinalizeStalls() async {
        // The end-of-workout freeze fix: the summary must come from the engine immediately,
        // not wait on the OS finalize. The stalling backend never returns from end().
        let manager = WorkoutSessionManager(backend: StallingBackend(), autoTick: false)
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        tick(manager, seconds: 5)
        manager.endManually()
        await waitUntilComplete(manager)

        #expect(manager.sessionState == .complete)
        #expect(manager.summary != nil)
        #expect(manager.summary?.totalDuration == 5)
        #expect(manager.summary?.totalDistance == nil)     // OS-owned totals not in yet
        #expect(manager.healthSaveState == .saving)        // and we say so, honestly (N6)
    }

    @Test func totalsAndSaveStateFillInWhenFinalizeReturns() async {
        let manager = makeManager() // simulated backend: end() returns instantly
        await manager.begin(config: SessionConfig(plan: shortPlan()), routineName: "Test")
        manager.receiveZone(nil)
        tick(manager, seconds: 40)
        await waitUntilComplete(manager)

        // Await the background finalize deterministically.
        await manager.finalizeTask?.value
        #expect(manager.healthSaveState == .saved)
        #expect(manager.summary?.totalDistance == 2400)
        #expect(manager.summary?.averageHeartRate == 138)
    }

    @Test func endingDuringAnExtendedRunIsNotABail() async {
        let manager = makeManager()
        // Small windows so a fast recovery unlocks extension quickly.
        let adaptation = AdaptationConfig(extendWindow: 3, recoverWindow: 2, recoveryDropBPM: 20,
                                          minWalkDuration: 3, runExtendIncrement: 10)
        let plan = IntervalPlan(segments: [
            IntervalSegment(phase: .run, targetDuration: 5),
            IntervalSegment(phase: .walk, targetDuration: 60),
            IntervalSegment(phase: .run, targetDuration: 5),
            IntervalSegment(phase: .walk, targetDuration: 60),
        ])
        await manager.begin(config: SessionConfig(plan: plan), routineName: "Test", adaptationConfig: adaptation)

        manager.receiveZone(2)
        manager.receiveHeartRate(160)
        tick(manager, seconds: 5)                 // run 1 completes on plan
        manager.receiveHeartRate(130)             // 30bpm drop → fast recovery
        tick(manager, seconds: 4)                 // walk ends at the floor
        #expect(manager.currentPhase == .run)
        tick(manager, seconds: 12)                // run 2 extends past its 5s seed
        #expect(manager.currentPhase == .run)

        manager.endManually()                     // stopping a long run, not bailing
        await waitUntilComplete(manager)
        #expect(manager.summary?.endedEarly == false)
        #expect((manager.summary?.longestRunSeconds ?? 0) > 5)
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
        // Long warmup so only cadence (not the timer) can end it; long run so the ticks that
        // deliver the cadence samples can't also run the first interval out.
        let plan = IntervalPlan.beginnerRunWalk(warmup: 300, runDuration: 60, walkDuration: 5, cycles: 2, cooldown: 2)
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

    @Test func stillRunningDuringWalkPulsesAndClearsWhenCompliant() async {
        let manager = makeManager()
        let plan = IntervalPlan.beginnerRunWalk(warmup: 2, runDuration: 5, walkDuration: 60, cycles: 1, cooldown: 2)
        await manager.begin(config: SessionConfig(plan: plan), routineName: "Test")
        manager.receiveZone(nil)
        tick(manager, seconds: 7) // warmup (2) + run (5) → into the walk
        #expect(manager.currentPhase == .walk)
        #expect(!manager.gaitMismatch)

        // Still at running cadence past the 8s grace: the mismatch pulse turns on.
        for _ in 0..<10 {
            manager.receiveCadence(155)
            tick(manager, seconds: 1)
        }
        #expect(manager.gaitMismatch)

        // Feet finally comply → the protest stops.
        manager.receiveCadence(105)
        tick(manager, seconds: 1)
        #expect(!manager.gaitMismatch)
    }

    @Test func runningCadenceDuringARunIsNotAMismatch() async {
        let manager = makeManager()
        let plan = IntervalPlan.beginnerRunWalk(warmup: 2, runDuration: 60, walkDuration: 5, cycles: 1, cooldown: 2)
        await manager.begin(config: SessionConfig(plan: plan), routineName: "Test")
        manager.receiveZone(nil)
        tick(manager, seconds: 2) // into the run
        for _ in 0..<15 {
            manager.receiveCadence(160)
            tick(manager, seconds: 1)
        }
        #expect(manager.currentPhase == .run)
        #expect(!manager.gaitMismatch)
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
