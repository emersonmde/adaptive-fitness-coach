import Foundation
import Testing
@testable import AdaptiveCore

struct IntervalStateMachineTests {

    /// Collects everything a run produces so tests can assert on the whole session.
    private struct Recording {
        var transitions: [TransitionEvent] = []
        var adaptations: [AdaptationEvent] = []
        var completedAt: TimeInterval?
    }

    /// Tick the machine at 1s granularity, feeding `zone(elapsed)` each second, until the
    /// session completes or `maxSeconds` elapses.
    private func drive(
        _ machine: inout IntervalStateMachine,
        zone: (TimeInterval) -> Int?,
        maxSeconds: Int
    ) -> Recording {
        var rec = Recording()
        for _ in 0..<maxSeconds {
            let nextElapsed = machine.sessionElapsed + 1
            let result = machine.tick(deltaTime: 1, currentZone: zone(nextElapsed))
            if let t = result.transition { rec.transitions.append(t) }
            if let a = result.adaptation { rec.adaptations.append(a) }
            if result.isComplete {
                rec.completedAt = machine.sessionElapsed
                break
            }
        }
        return rec
    }

    private func config(_ segments: [(IntervalPhase, TimeInterval)], targetZone: Int = 2) -> SessionConfig {
        SessionConfig(
            plan: IntervalPlan(segments: segments.map { IntervalSegment(phase: $0.0, targetDuration: $0.1) }),
            targetZone: targetZone
        )
    }

    // MARK: - Natural progression (no zone data)

    @Test func naturalProgressionCompletesWithCorrectTransitions() {
        var machine = IntervalStateMachine(config: config([
            (.warmupWalk, 2), (.run, 3), (.walk, 3), (.cooldownWalk, 2),
        ]))
        let rec = drive(&machine, zone: { _ in nil }, maxSeconds: 30)

        #expect(rec.completedAt == 10)
        #expect(machine.isComplete)
        #expect(rec.adaptations.isEmpty) // no zone data → no adaptation
        #expect(rec.transitions == [
            TransitionEvent(from: .warmupWalk, to: .run),
            TransitionEvent(from: .run, to: .walk),
            TransitionEvent(from: .walk, to: .cooldownWalk),
        ])
    }

    @Test func tracksRunWalkSplitsAndIntervalCount() {
        var machine = IntervalStateMachine(config: config([
            (.warmupWalk, 2), (.run, 3), (.walk, 3), (.run, 3), (.cooldownWalk, 2),
        ]))
        _ = drive(&machine, zone: { _ in nil }, maxSeconds: 30)

        #expect(machine.intervalsCompleted == 2)            // two run segments
        #expect(machine.totalRunDuration == 6)              // 3 + 3
        #expect(machine.totalWalkDuration == 7)             // 2 + 3 + 2
        #expect(machine.totalRunDuration + machine.totalWalkDuration == machine.sessionElapsed)
    }

    // MARK: - Backing off

    @Test func sustainedHotShortensRunAndTransitions() {
        let adapt = AdaptationConfig(backOffWindow: 3, recoverWindow: 999, minRunDuration: 3, maxWalkDuration: 999)
        var machine = IntervalStateMachine(config: config([(.run, 60), (.walk, 60)]), adaptationConfig: adapt)
        let rec = drive(&machine, zone: { _ in 5 }, maxSeconds: 10)

        // Run is cut short at 3s (back-off window + min-run both satisfied), transitions to walk.
        #expect(rec.transitions.first == TransitionEvent(from: .run, to: .walk))
        #expect(rec.adaptations.first?.action == .shortenedRun)
        #expect(machine.intervalsCompleted == 1)
        #expect(machine.currentPhase == .walk)
    }

    // MARK: - Extending

    @Test func sustainedComfortExtendsRunWithExactlyOneBanner() {
        // Extension is opt-in (allowRunExtension) — see comfortableRunNeverExtendsByDefault.
        let adapt = AdaptationConfig(backOffWindow: 999, allowRunExtension: true, extendWindow: 3, runExtendIncrement: 3)
        var machine = IntervalStateMachine(config: config([(.run, 5), (.walk, 5)]), adaptationConfig: adapt)
        let rec = drive(&machine, zone: { _ in 1 }, maxSeconds: 12)

        // The run keeps stretching (still running, never handed to the walk)...
        #expect(machine.currentPhase == .run)
        #expect(!rec.transitions.contains(TransitionEvent(from: .run, to: .walk)))
        // ...but the "keep running" banner is surfaced exactly once, not every increment (Q5).
        #expect(rec.adaptations.filter { $0.action == .extendedRun }.count == 1)
        #expect(machine.adaptationsApplied == 1)
    }

    // MARK: - Extension gated off by default

    @Test func comfortableRunNeverExtendsByDefault() {
        // The default config must hold the planned run duration even under permanent comfort —
        // HR lag reads as comfort in a deconditioned runner (the first real-run failure).
        var machine = IntervalStateMachine(config: config([(.run, 5), (.walk, 5)]))
        let rec = drive(&machine, zone: { _ in 1 }, maxSeconds: 8)

        #expect(rec.transitions.first == TransitionEvent(from: .run, to: .walk))
        #expect(rec.transitions.first != nil)
        #expect(!rec.adaptations.contains { $0.action == .extendedRun })
        #expect(machine.totalRunDuration == 5) // exactly the plan
    }

    // MARK: - Walk lengthening / capping

    @Test func notRecoveredLengthensWalkUpToCap() {
        let adapt = AdaptationConfig(recoverWindow: 999, walkLengthenIncrement: 3, maxWalkDuration: 12)
        var machine = IntervalStateMachine(config: config([(.walk, 5)]), adaptationConfig: adapt)
        let rec = drive(&machine, zone: { _ in 4 }, maxSeconds: 30)

        #expect(rec.adaptations.contains { $0.action == .lengthenedWalk })
        // Walk is lengthened 5→8→11→12 (capped), then completes at the 12s cap.
        #expect(machine.isComplete)
        #expect(rec.completedAt == 12)
        // Ending at the cap still unrecovered is remembered as a struggle signal.
        #expect(machine.walksHitCap == 1)
    }

    // MARK: - Quick recovery shortens walk

    @Test func quickRecoveryShortensWalk() {
        let adapt = AdaptationConfig(recoverWindow: 3, minWalkDuration: 3)
        var machine = IntervalStateMachine(config: config([(.walk, 60), (.run, 60)]), adaptationConfig: adapt)
        let rec = drive(&machine, zone: { _ in 1 }, maxSeconds: 10)

        #expect(rec.adaptations.first?.action == .shortenedWalk)
        #expect(rec.transitions.first == TransitionEvent(from: .walk, to: .run))
    }

    // MARK: - Warmup/cooldown are not adapted

    @Test func warmupIsNotAdaptedEvenWhenHot() {
        let adapt = AdaptationConfig(backOffWindow: 1, minRunDuration: 1)
        var machine = IntervalStateMachine(config: config([(.warmupWalk, 5), (.run, 5)]), adaptationConfig: adapt)
        // Capture only the warmup window (first 5s): drive 5 ticks and assert no adaptation
        // occurred and the warmup ran its full fixed duration before transitioning.
        var adaptationsDuringWarmup = 0
        for _ in 0..<5 {
            let r = machine.tick(deltaTime: 1, currentZone: 5)
            if r.adaptation != nil { adaptationsDuringWarmup += 1 }
        }
        #expect(adaptationsDuringWarmup == 0)            // warmup is never adapted
        #expect(machine.currentPhase == .run)            // transitioned at exactly 5s
        #expect(machine.intervalsCompleted == 0)         // no run completed yet
    }

    // MARK: - Delta-time robustness

    @Test func nonPositiveDeltaIsInert() {
        var machine = IntervalStateMachine(config: config([(.run, 5)]))
        let before = machine.sessionElapsed
        let zero = machine.tick(deltaTime: 0, currentZone: nil)
        let negative = machine.tick(deltaTime: -3, currentZone: nil)
        #expect(zero == TickResult())
        #expect(negative == TickResult())
        #expect(machine.sessionElapsed == before) // no advancement, no corruption
    }

    @Test func variableDeltaStillCompletesAndTotalsAreConsistent() {
        var machine = IntervalStateMachine(config: config([(.warmupWalk, 2), (.run, 4), (.walk, 4)]))
        // Mixed deltas (the watch clamps background catch-up, but the engine must stay sane).
        for delta in [0.5, 0.5, 1.0, 2.0, 1.0, 3.0, 2.0, 1.0] as [TimeInterval] {
            _ = machine.tick(deltaTime: delta, currentZone: nil)
        }
        // Run + walk totals always sum to the session elapsed regardless of tick cadence.
        #expect(abs((machine.totalRunDuration + machine.totalWalkDuration) - machine.sessionElapsed) < 0.0001)
    }

    // MARK: - Degraded path

    @Test func nilZoneRunsFixedIntervalsNoAdaptation() {
        let adapt = AdaptationConfig(backOffWindow: 1, extendWindow: 1, recoverWindow: 1, minRunDuration: 1)
        var machine = IntervalStateMachine(config: config([(.run, 5), (.walk, 5)]), adaptationConfig: adapt)
        let rec = drive(&machine, zone: { _ in nil }, maxSeconds: 20)

        #expect(rec.adaptations.isEmpty)
        #expect(rec.completedAt == 10) // fixed 5 + 5
    }

    // MARK: - Edge cases

    @Test func emptyPlanIsImmediatelyComplete() {
        var machine = IntervalStateMachine(config: SessionConfig(plan: IntervalPlan(segments: []), targetZone: 2))
        #expect(machine.isComplete)
        let result = machine.tick(deltaTime: 1, currentZone: 3)
        #expect(result.isComplete)
        #expect(result.transition == nil)
    }

    @Test func ticksAfterCompletionAreInert() {
        var machine = IntervalStateMachine(config: config([(.run, 2)]))
        _ = drive(&machine, zone: { _ in nil }, maxSeconds: 5)
        #expect(machine.isComplete)
        let elapsedAtComplete = machine.sessionElapsed
        let result = machine.tick(deltaTime: 1, currentZone: 3)
        #expect(result.isComplete)
        #expect(machine.sessionElapsed == elapsedAtComplete) // no further advancement
    }

    // MARK: - Skipping a segment (warmup ends when running is detected / "Start Run" tap)

    @Test func skipDuringWarmupTransitionsToTheFirstRun() {
        var machine = IntervalStateMachine(config: config([(.warmupWalk, 300), (.run, 60), (.walk, 60)]))
        _ = machine.tick(deltaTime: 1, currentZone: nil)
        let result = machine.skipCurrentSegment()

        // Identical shape to a natural transition, so the same haptic path fires.
        #expect(result.transition == TransitionEvent(from: .warmupWalk, to: .run))
        #expect(!result.isComplete)
        #expect(machine.currentPhase == .run)
        #expect(machine.intervalElapsed == 0)
        #expect(machine.sessionElapsed == 1) // session clock keeps its true elapsed
    }

    @Test func skipOnTheFinalSegmentCompletesTheSession() {
        var machine = IntervalStateMachine(config: config([(.cooldownWalk, 300)]))
        let result = machine.skipCurrentSegment()
        #expect(result.isComplete)
        #expect(result.transition == nil)
        #expect(machine.isComplete)
    }

    @Test func skipAfterCompletionIsInert() {
        var machine = IntervalStateMachine(config: config([(.run, 1)]))
        _ = drive(&machine, zone: { _ in nil }, maxSeconds: 3)
        #expect(machine.isComplete)
        let result = machine.skipCurrentSegment()
        #expect(result.isComplete)
        #expect(result.transition == nil)
    }

    // MARK: - Heart-rate recovery (walk ends when HR drops from run peak)

    /// Tick the machine with full samples (zone + heart rate).
    private func drive(
        _ machine: inout IntervalStateMachine,
        sample: (TimeInterval) -> WorkoutSample,
        maxSeconds: Int
    ) -> Recording {
        var rec = Recording()
        for _ in 0..<maxSeconds {
            let nextElapsed = machine.sessionElapsed + 1
            let result = machine.tick(deltaTime: 1, sample: sample(nextElapsed))
            if let t = result.transition { rec.transitions.append(t) }
            if let a = result.adaptation { rec.adaptations.append(a) }
            if result.isComplete {
                rec.completedAt = machine.sessionElapsed
                break
            }
        }
        return rec
    }

    @Test func walkEndsWhenHeartRateDropsFromRunPeak() {
        // 10s run at HR 160 (in zone), then walking at HR 130 (still zone 2 — the green band):
        // the 30bpm drop is the recovery signal even though the zone never falls below target.
        let adapt = AdaptationConfig(recoverWindow: 3, recoveryDropBPM: 20, minWalkDuration: 5)
        var machine = IntervalStateMachine(config: config([(.run, 10), (.walk, 90), (.run, 10)]), adaptationConfig: adapt)
        let rec = drive(&machine, sample: { elapsed in
            elapsed <= 10 ? WorkoutSample(zone: 2, heartRate: 160)
                          : WorkoutSample(zone: 2, heartRate: 130)
        }, maxSeconds: 30)

        #expect(rec.adaptations.contains { $0.action == .shortenedWalk })
        #expect(rec.transitions.contains(TransitionEvent(from: .walk, to: .run)))
        // Walk ended at the minWalk floor (recovery confirmed well inside it), not at 90s.
        #expect(machine.totalWalkDuration < 10)
    }

    @Test func insufficientHeartRateDropHoldsTheWalkInTheGreenBand() {
        // Peak 160 → walking at 150 (only 10bpm), zone pinned at target: unrecovered, so the
        // walk lengthens rather than handing the user back to a run they can't sustain.
        let adapt = AdaptationConfig(recoverWindow: 3, recoveryDropBPM: 20, minWalkDuration: 5,
                                     walkLengthenIncrement: 5, maxWalkDuration: 20)
        var machine = IntervalStateMachine(config: config([(.run, 5), (.walk, 10), (.run, 5)]), adaptationConfig: adapt)
        let rec = drive(&machine, sample: { elapsed in
            elapsed <= 5 ? WorkoutSample(zone: 2, heartRate: 160)
                         : WorkoutSample(zone: 2, heartRate: 150)
        }, maxSeconds: 60)

        #expect(rec.adaptations.contains { $0.action == .lengthenedWalk })
        #expect(!rec.adaptations.contains { $0.action == .shortenedWalk })
        #expect(machine.walksHitCap == 1) // rode the walk all the way to the cap
    }

    @Test func heartRateDropoutDuringAWalkRecordsNoRecovery() {
        // HR present through the run, gone for the whole walk: the stale pre-walk reading
        // proves nothing — recording a near-zero "drop" would fabricate a poor recovery (N6).
        var machine = IntervalStateMachine(config: config([(.run, 5), (.walk, 70), (.run, 3)]))
        _ = drive(&machine, sample: { elapsed in
            elapsed <= 5 ? WorkoutSample(zone: 2, heartRate: 160)
                         : WorkoutSample(zone: 2, heartRate: nil)
        }, maxSeconds: 90)
        #expect(machine.recoveryDrops.isEmpty)
    }

    @Test func recoveryDropIsRecordedPerWalk() {
        var machine = IntervalStateMachine(config: config([(.run, 5), (.walk, 5), (.cooldownWalk, 2)]))
        _ = drive(&machine, sample: { elapsed in
            elapsed <= 5 ? WorkoutSample(zone: 2, heartRate: 158)
                         : WorkoutSample(zone: 2, heartRate: 136)
        }, maxSeconds: 20)

        // Short walk (< the 60s HRR mark) records its drop at walk exit: 158 - 136 = 22.
        #expect(machine.recoveryDrops == [22])
        #expect(machine.meanRecoveryDrop == 22)
    }

    @Test func runBackOffsAreCounted() {
        let adapt = AdaptationConfig(backOffWindow: 2, recoverWindow: 2, minRunDuration: 2, minWalkDuration: 2)
        var machine = IntervalStateMachine(config: config([(.run, 30), (.walk, 30), (.run, 30)]), adaptationConfig: adapt)
        // Hot through each run (cut at 2s), recovered through the walk (cut at 2s).
        _ = drive(&machine, zone: { elapsed in elapsed <= 2 || elapsed > 4 ? 3 : 1 }, maxSeconds: 60)
        #expect(machine.runBackOffCount == 2)
        #expect(machine.intervalsCompleted == 2) // cut-short runs still count as reached
    }

    @Test func fastRecoveryUnlocksRunExtensionForTheRestOfTheSession() {
        // Extension is off by default (in-run zone comfort lies under HR lag), but a walk
        // that ends at the recovery floor is trustworthy evidence of fitness — after it,
        // comfortable runs may stretch. Run 1 must NOT extend; run 2 (after the fast
        // recovery) must.
        let adapt = AdaptationConfig(extendWindow: 4, recoverWindow: 3, recoveryDropBPM: 20,
                                     minWalkDuration: 5, runExtendIncrement: 10)
        var machine = IntervalStateMachine(config: config([(.run, 10), (.walk, 60), (.run, 10), (.walk, 60)]),
                                           adaptationConfig: adapt)
        let rec = drive(&machine, sample: { elapsed in
            elapsed <= 10 ? WorkoutSample(zone: 2, heartRate: 160)   // run 1, comfortable
                          : WorkoutSample(zone: 2, heartRate: 130)   // 30bpm drop → fast recovery
        }, maxSeconds: 40)

        // Run 1 ended exactly on plan (no extension before evidence).
        #expect(rec.transitions.first == TransitionEvent(from: .run, to: .walk))
        #expect(machine.fastRecoveries >= 1)
        // Run 2 extended: the machine is still in it well past its 10s seed.
        #expect(machine.currentPhase == .run)
        #expect(rec.adaptations.contains { $0.action == .extendedRun })
        #expect(machine.currentRunIsExtended)
        #expect(machine.longestRunInterval > 10)
    }

    @Test func noSignalsWalkRunsItsPlannedDuration() {
        // Neither zone nor HR: the walk runs its seed duration exactly (N6 degradation).
        var machine = IntervalStateMachine(config: config([(.run, 3), (.walk, 5), (.run, 3)]))
        let rec = drive(&machine, zone: { _ in nil }, maxSeconds: 20)
        #expect(rec.transitions.contains(TransitionEvent(from: .walk, to: .run)))
        #expect(rec.adaptations.isEmpty)
        #expect(machine.recoveryDrops.isEmpty)
        #expect(machine.totalWalkDuration == 5)
    }

    // MARK: - Session metrics (P6.1: walksCompleted + timeInTargetZone)

    @Test func walksCompletedCountsRecoveryWalksOnly() {
        // Warmup and cooldown are walks by phase family but NOT recovery walks — only the
        // repeating .walk segments count, mirroring how intervalsCompleted treats runs.
        var machine = IntervalStateMachine(config: config([
            (.warmupWalk, 2), (.run, 3), (.walk, 3), (.run, 3), (.walk, 3), (.cooldownWalk, 2),
        ]))
        _ = drive(&machine, zone: { _ in nil }, maxSeconds: 30)
        #expect(machine.walksCompleted == 2)
        #expect(machine.intervalsCompleted == 2)
    }

    @Test func skippedWalkEarnsNoWalkCredit() {
        var machine = IntervalStateMachine(config: config([(.run, 3), (.walk, 30), (.run, 3)]))
        _ = machine.tick(deltaTime: 3, currentZone: nil)     // finish the run
        #expect(machine.currentPhase == .walk)
        _ = machine.skipCurrentSegment()                      // user skips the walk
        _ = machine.tick(deltaTime: 3, currentZone: nil)     // finish the last run
        #expect(machine.walksCompleted == 0)                  // nothing was demonstrated (N6)
        #expect(machine.intervalsCompleted == 2)
    }

    @Test func timeInTargetZoneAccumulatesOnlyInZoneDuringRuns() {
        // 6s run: 3 ticks in the target zone, 2 above it, 1 with no reading; then a walk
        // spent entirely "in zone" — which must not count (walks below zone are desired).
        var machine = IntervalStateMachine(config: config([(.run, 6), (.walk, 4)], targetZone: 2))
        let zones: [Int?] = [2, 2, 3, 3, 2, nil]
        for zone in zones { _ = machine.tick(deltaTime: 1, currentZone: zone) }
        #expect(machine.timeInTargetZone == 3)

        for _ in 0..<4 { _ = machine.tick(deltaTime: 1, currentZone: 2) }
        #expect(machine.timeInTargetZone == 3)   // walk ticks added nothing
    }

    @Test func nilZoneTicksNeverAccumulateZoneTime() {
        var machine = IntervalStateMachine(config: config([(.run, 5)], targetZone: 2))
        _ = drive(&machine, zone: { _ in nil }, maxSeconds: 10)
        #expect(machine.timeInTargetZone == 0)
    }
}
