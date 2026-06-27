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

    @Test func sustainedComfortExtendsRunWithoutTransitioning() {
        let adapt = AdaptationConfig(backOffWindow: 999, extendWindow: 3, runExtendIncrement: 3)
        var machine = IntervalStateMachine(config: config([(.run, 5), (.walk, 5)]), adaptationConfig: adapt)
        let rec = drive(&machine, zone: { _ in 1 }, maxSeconds: 12)

        #expect(rec.adaptations.allSatisfy { $0.action == .extendedRun })
        #expect(!rec.adaptations.isEmpty)
        // Still running — the run never handed off to the walk.
        #expect(machine.currentPhase == .run)
        #expect(!rec.transitions.contains(TransitionEvent(from: .run, to: .walk)))
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
        let rec = drive(&machine, zone: { _ in 5 }, maxSeconds: 6)

        // No adaptation during the warmup; it runs its full fixed 5s then transitions.
        #expect(rec.transitions.first == TransitionEvent(from: .warmupWalk, to: .run))
        #expect(rec.transitions.first.map { _ in machine.sessionElapsed } != nil)
        #expect(!rec.adaptations.contains { $0.atSessionTime <= 5 && $0.action != .shortenedRun } || rec.adaptations.isEmpty)
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
}
