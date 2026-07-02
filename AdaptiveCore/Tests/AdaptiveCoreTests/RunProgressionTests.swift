import Foundation
import Testing
@testable import AdaptiveCore

// MARK: - RunProgressionPolicy (session outcome → next seeds)

struct RunProgressionPolicyTests {

    private let policy = RunProgressionPolicy()
    private let seeds = RunSeeds(runSeconds: 90, walkSeconds: 120)

    private func outcome(
        planned: Int = 6, completed: Int = 6,
        backOffs: Int = 0, capped: Int = 0,
        endedEarly: Bool = false
    ) -> RunSessionOutcome {
        RunSessionOutcome(
            plannedRunIntervals: planned, completedRunIntervals: completed,
            runBackOffCount: backOffs, walksHitCap: capped, endedEarly: endedEarly
        )
    }

    @Test func cleanSessionAdvancesRunSeed() {
        let next = policy.nextSeeds(current: seeds, outcome: outcome())
        #expect(next.runSeconds == 90 + 22) // +runSeconds/4
        #expect(next.walkSeconds == 120)    // walk untouched below the shrink threshold
    }

    @Test func advanceStepIsBounded() {
        // Small seed advances by at least 15s; large seed by at most 60s.
        let small = policy.nextSeeds(current: RunSeeds(runSeconds: 30, walkSeconds: 120), outcome: outcome())
        #expect(small.runSeconds == 45)
        let large = policy.nextSeeds(current: RunSeeds(runSeconds: 600, walkSeconds: 90), outcome: outcome())
        #expect(large.runSeconds == 660)
    }

    @Test func walkShrinksOnceRunsAreLong() {
        let current = RunSeeds(runSeconds: 200, walkSeconds: 120)
        let next = policy.nextSeeds(current: current, outcome: outcome())
        #expect(next.runSeconds == 250)
        #expect(next.walkSeconds == 105) // −15 once the run seed is past the threshold
    }

    @Test func walkNeverShrinksBelowItsFloor() {
        let current = RunSeeds(runSeconds: 400, walkSeconds: 60)
        let next = policy.nextSeeds(current: current, outcome: outcome())
        #expect(next.walkSeconds == 60)
    }

    @Test func repeatedBackOffsRegress() {
        let next = policy.nextSeeds(current: seeds, outcome: outcome(backOffs: 2))
        #expect(next.runSeconds == 75)   // −15
        #expect(next.walkSeconds == 135) // +15
    }

    @Test func bailingOutEarlyRegresses() {
        let next = policy.nextSeeds(current: seeds, outcome: outcome(planned: 6, completed: 2, endedEarly: true))
        #expect(next.runSeconds == 75)
    }

    @Test func endingEarlyWithMostRunsDoneHolds() {
        // Cut the cooldown short after doing 5 of 6 runs — not a struggle, but not clean either.
        let next = policy.nextSeeds(current: seeds, outcome: outcome(planned: 6, completed: 5, endedEarly: true))
        #expect(next == seeds)
    }

    @Test func singleBackOffHolds() {
        // One cut-short run is a blip, not a pattern: hold, don't regress — and don't advance.
        let next = policy.nextSeeds(current: seeds, outcome: outcome(backOffs: 1))
        #expect(next == seeds)
    }

    @Test func walkAtCapBlocksAdvance() {
        let next = policy.nextSeeds(current: seeds, outcome: outcome(capped: 1))
        #expect(next == seeds)
    }

    @Test func runSeedNeverRegressesBelowItsFloor() {
        let current = RunSeeds(runSeconds: 30, walkSeconds: 180)
        let next = policy.nextSeeds(current: current, outcome: outcome(backOffs: 5))
        #expect(next.runSeconds == 30)   // floor
        #expect(next.walkSeconds == 180) // cap
    }

    @Test func zeroPlannedIntervalsNeverAdvances() {
        // Degenerate outcome (e.g. session ended before any run existed) must hold.
        let next = policy.nextSeeds(current: seeds, outcome: outcome(planned: 0, completed: 0))
        #expect(next == seeds)
    }
}

// MARK: - Run progression persistence & sync compatibility

struct RunProgressionSyncTests {

    @Test func oldRunCardPayloadDecodesWithDefaults() throws {
        // A pre-P1.5 card has only id + durationMinutes; new fields must default, not fail.
        let json = #"{"id":"6F1C0A6E-2C6B-4B34-9A5A-111111111111","durationMinutes":30}"#
        let card = try JSONDecoder().decode(RunCard.self, from: Data(json.utf8))
        #expect(card.durationMinutes == 30)
        #expect(card.warmupMinutes == 5)
        #expect(card.cooldownMinutes == 5)
        #expect(card.runSeconds == 90)
        #expect(card.walkSeconds == 120)
    }

    @Test func progressionBatchWithoutRunUpdatesDecodes() throws {
        let json = #"{"routineId":"6F1C0A6E-2C6B-4B34-9A5A-222222222222","updates":[]}"#
        let batch = try JSONDecoder().decode(ProgressionBatch.self, from: Data(json.utf8))
        #expect(batch.runUpdates.isEmpty)
    }

    @Test func applyingRunProgressionsRewritesSeedsClamped() {
        let card = RunCard()
        let routine = Routine(name: "Morning Run", cards: [.run(card)])
        let sane = routine.applyingRunProgressions([
            RunProgressionUpdate(cardId: card.id, runSeconds: 112, walkSeconds: 105),
        ])
        #expect(sane.firstRunCard?.runSeconds == 112)
        #expect(sane.firstRunCard?.walkSeconds == 105)

        // Garbage values clamp instead of producing a degenerate plan (N6).
        let clamped = routine.applyingRunProgressions([
            RunProgressionUpdate(cardId: card.id, runSeconds: 100_000, walkSeconds: -50),
        ])
        #expect(clamped.firstRunCard?.runSeconds == 3600)
        #expect(clamped.firstRunCard?.walkSeconds == 0)
    }

    @Test func unknownCardIdIsANoOp() {
        let routine = Routine(name: "Morning Run", cards: [.run(RunCard())])
        let unchanged = routine.applyingRunProgressions([
            RunProgressionUpdate(cardId: UUID(), runSeconds: 300, walkSeconds: 60),
        ])
        #expect(unchanged == routine)
    }

    @MainActor
    @Test func storeAppliesRunBatchIdempotently() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = RoutineStore(fileURL: dir.appendingPathComponent("routines.json"))
        let card = RunCard()
        let routine = Routine(name: "Morning Run", cards: [.run(card)])
        store.add(routine)

        let batch = ProgressionBatch(routineId: routine.id, runUpdates: [
            RunProgressionUpdate(cardId: card.id, runSeconds: 112, walkSeconds: 120),
        ])
        #expect(store.applyProgressions(batch, broadcast: false))
        #expect(!store.applyProgressions(batch, broadcast: false)) // converged → no write, no echo
        #expect(store.routines.first?.firstRunCard?.runSeconds == 112)
    }
}

// MARK: - IntervalPlan.runWalk (card shape + seeds → segment plan)

struct RunWalkPlanTests {

    @Test func buildsWarmupCyclesAndCooldown() {
        let plan = IntervalPlan.runWalk(runSeconds: 90, walkSeconds: 120, blockDuration: 1200, warmup: 300, cooldown: 300)
        #expect(plan.segments.first == IntervalSegment(phase: .warmupWalk, targetDuration: 300))
        #expect(plan.segments.last == IntervalSegment(phase: .cooldownWalk, targetDuration: 300))
        // 1200 / (90+120) ≈ 5.7 → 6 cycles.
        #expect(plan.runIntervalCount == 6)
    }

    @Test func zeroWarmupAndCooldownAreOmitted() {
        let plan = IntervalPlan.runWalk(runSeconds: 60, walkSeconds: 90, blockDuration: 600, warmup: 0, cooldown: 0)
        #expect(plan.segments.first?.phase == .run)
        #expect(plan.segments.last?.phase == .walk)
    }

    @Test func zeroWalkSeedMeansContinuousRunning() {
        let plan = IntervalPlan.runWalk(runSeconds: 300, walkSeconds: 0, blockDuration: 1200, warmup: 300, cooldown: 300)
        #expect(plan.runIntervalCount == 1)
        #expect(plan.segments[1] == IntervalSegment(phase: .run, targetDuration: 1200))
    }

    @Test func runSeedCoveringTheBlockMeansContinuousRunning() {
        let plan = IntervalPlan.runWalk(runSeconds: 1300, walkSeconds: 90, blockDuration: 1200, warmup: 300, cooldown: 300)
        #expect(plan.runIntervalCount == 1)
        #expect(plan.segments[1].targetDuration == 1300)
    }

    @Test func tinyBlockStillGetsOneCycle() {
        let plan = IntervalPlan.runWalk(runSeconds: 90, walkSeconds: 120, blockDuration: 60, warmup: 0, cooldown: 0)
        #expect(plan.runIntervalCount == 1)
    }

    @Test func planForCardUsesAllCardFields() {
        let card = RunCard(durationMinutes: 20, warmupMinutes: 5, cooldownMinutes: 3, runSeconds: 90, walkSeconds: 120)
        let plan = IntervalPlan.plan(for: card)
        #expect(plan.segments.first == IntervalSegment(phase: .warmupWalk, targetDuration: 300))
        #expect(plan.segments.last == IntervalSegment(phase: .cooldownWalk, targetDuration: 180))
        #expect(plan.runIntervalCount == 6)
    }
}

// MARK: - RunningCadenceDetector

struct RunningCadenceDetectorTests {

    @Test func sustainedRunningCadenceFires() {
        var detector = RunningCadenceDetector() // 140 spm, 10s sustain
        var fired = false
        // Samples every 2.5s (CMPedometer's real cadence update rate).
        for t in stride(from: 0.0, through: 12.5, by: 2.5) {
            if detector.update(cadence: 155, at: t) { fired = true }
        }
        #expect(fired)
    }

    @Test func firesExactlyOnce() {
        var detector = RunningCadenceDetector()
        var count = 0
        for t in stride(from: 0.0, through: 60.0, by: 2.5) {
            if detector.update(cadence: 155, at: t) { count += 1 }
        }
        #expect(count == 1)
    }

    @Test func briefSpikeDoesNotFire() {
        var detector = RunningCadenceDetector()
        var fired = false
        // 7.5s of running cadence (below the 10s sustain), then walking again.
        for t in stride(from: 0.0, through: 7.5, by: 2.5) {
            if detector.update(cadence: 150, at: t) { fired = true }
        }
        for t in stride(from: 10.0, through: 30.0, by: 2.5) {
            if detector.update(cadence: 110, at: t) { fired = true }
        }
        #expect(!fired)
    }

    @Test func dipBelowThresholdResetsTheStreak() {
        var detector = RunningCadenceDetector()
        var fired = false
        _ = detector.update(cadence: 150, at: 0)
        _ = detector.update(cadence: 150, at: 2.5)
        _ = detector.update(cadence: 120, at: 5)     // dip — streak resets
        for t in stride(from: 7.5, through: 15.0, by: 2.5) {
            if detector.update(cadence: 150, at: t) { fired = true }
        }
        #expect(!fired) // only 7.5s since the reset
        let firesAfterFullStreak = detector.update(cadence: 150, at: 17.5) // 10s after the reset
        #expect(firesAfterFullStreak)
    }

    @Test func sampleGapResetsTheStreak() {
        var detector = RunningCadenceDetector(threshold: 140, sustainDuration: 10, staleAfter: 6)
        _ = detector.update(cadence: 150, at: 0)
        _ = detector.update(cadence: 150, at: 2.5)
        // 8s dropout (> staleAfter): two separate bursts must not add up.
        let afterGap1 = detector.update(cadence: 150, at: 10.5)
        let afterGap2 = detector.update(cadence: 150, at: 13)
        let afterGap3 = detector.update(cadence: 150, at: 18)
        #expect(!afterGap1 && !afterGap2 && !afterGap3)
        let fullStreak = detector.update(cadence: 150, at: 20.5) // 10s of continuous streak since 10.5
        #expect(fullStreak)
    }

    @Test func briskWalkingCadenceNeverFires() {
        var detector = RunningCadenceDetector()
        var fired = false
        for t in stride(from: 0.0, through: 120.0, by: 2.5) {
            if detector.update(cadence: 132, at: t) { fired = true } // brisk walk ~130-135
        }
        #expect(!fired)
    }

    @Test func resetReArms() {
        var detector = RunningCadenceDetector(threshold: 140, sustainDuration: 5, staleAfter: 6)
        _ = detector.update(cadence: 150, at: 0)
        let first = detector.update(cadence: 150, at: 5)
        #expect(first)
        detector.reset()
        _ = detector.update(cadence: 150, at: 10)
        let second = detector.update(cadence: 150, at: 15)
        #expect(second)
    }
}
