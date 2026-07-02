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

    @Test func defiedWalksDoNotCountAsCappedStruggles() {
        // The user ran through a walk (cadence-verified choice): its capped recovery is an
        // artifact of the choice, so an otherwise-clean session still advances.
        var out = outcome(capped: 1)
        out.walksDefied = 1
        let next = policy.nextSeeds(current: seeds, outcome: out)
        #expect(next.runSeconds == 112) // normal clean advance, not a hold
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

    // MARK: - Strong sessions and demonstrated capacity

    @Test func strongSessionAdvancesTwoNotches() {
        // Every walk ended at the recovery floor: two notches, not one.
        let strong = RunSessionOutcome(plannedRunIntervals: 6, completedRunIntervals: 6,
                                       runBackOffCount: 0, walksHitCap: 0, fastRecoveries: 6)
        let next = policy.nextSeeds(current: seeds, outcome: strong)
        // 90 → +22 → 112 → +28 → 140
        #expect(next.runSeconds == 140)
    }

    @Test func partialFastRecoveriesAdvanceOneNotch() {
        let mixed = RunSessionOutcome(plannedRunIntervals: 6, completedRunIntervals: 6,
                                      runBackOffCount: 0, walksHitCap: 0, fastRecoveries: 3)
        let next = policy.nextSeeds(current: seeds, outcome: mixed)
        #expect(next.runSeconds == 112)
    }

    @Test func demonstratedLongRunSnapsTheSeed() {
        // Extension unlocked mid-session and the user ran 14 minutes straight: next session
        // starts from what was actually run, not one notch up.
        let out = RunSessionOutcome(plannedRunIntervals: 6, completedRunIntervals: 2,
                                    runBackOffCount: 0, walksHitCap: 0, fastRecoveries: 1,
                                    longestRunSeconds: 845)
        let next = policy.nextSeeds(current: seeds, outcome: out)
        #expect(next.runSeconds == 840) // rounded down to 15s
        #expect(next.walkSeconds <= 90) // long runs come with short recoveries
    }

    @Test func longRunEndingInStruggleDoesNotSnap() {
        // A long run that ended in repeated back-offs is overreach, not capacity.
        let out = RunSessionOutcome(plannedRunIntervals: 6, completedRunIntervals: 3,
                                    runBackOffCount: 3, walksHitCap: 0,
                                    longestRunSeconds: 600)
        let next = policy.nextSeeds(current: seeds, outcome: out)
        #expect(next.runSeconds == 75) // regressed, no snap
    }

    @Test func normalCompletedRunDoesNotSnap() {
        // longestRun == the seed itself (every run ran its plan) — snap must not fire.
        let next = policy.nextSeeds(current: seeds, outcome: {
            var o = outcome(); o.longestRunSeconds = 90; return o
        }())
        #expect(next.runSeconds == 112) // plain single-notch advance
    }
}

// MARK: - FitnessCalibration (Health history → starting seeds)

struct FitnessCalibrationTests {

    private func run(_ minutes: Double, km: Double? = nil) -> FitnessCalibration.PriorRun {
        FitnessCalibration.PriorRun(duration: minutes * 60, distanceMeters: km.map { $0 * 1000 })
    }

    @Test func noSignalIsBeginner() {
        #expect(FitnessCalibration.seeds(vo2Max: nil, recentRuns: []) == FitnessCalibration.beginnerSeeds)
    }

    @Test func regularRunnerIsContinuous() {
        let runs = [run(25, km: 4.5), run(30, km: 5), run(22, km: 4)]
        #expect(FitnessCalibration.seeds(vo2Max: nil, recentRuns: runs) == FitnessCalibration.continuousSeeds)
    }

    @Test func occasionalRunnerIsIntermediate() {
        let runs = [run(15, km: 2.5)]
        #expect(FitnessCalibration.seeds(vo2Max: nil, recentRuns: runs) == FitnessCalibration.intermediateSeeds)
    }

    @Test func goodVo2WithoutRunsIsIntermediateNotContinuous() {
        // Cardio capacity without recent running practice: don't skip the build-up entirely.
        #expect(FitnessCalibration.seeds(vo2Max: 48, recentRuns: []) == FitnessCalibration.intermediateSeeds)
    }

    @Test func lowVo2IsBeginner() {
        #expect(FitnessCalibration.seeds(vo2Max: 33, recentRuns: []) == FitnessCalibration.beginnerSeeds)
    }

    @Test func walkingPaceWorkoutsAreNotRuns() {
        // 30 minutes covering 2.5 km is a walk logged as a run (12 min/km).
        let walks = [run(30, km: 2.5), run(25, km: 2.0), run(40, km: 3.0)]
        #expect(FitnessCalibration.seeds(vo2Max: nil, recentRuns: walks) == FitnessCalibration.beginnerSeeds)
    }

    @Test func shortJogsDoNotCountAsRealRuns() {
        let jogs = [run(5, km: 0.9), run(4, km: 0.7), run(6, km: 1.0)]
        #expect(FitnessCalibration.seeds(vo2Max: nil, recentRuns: jogs) == FitnessCalibration.beginnerSeeds)
    }

    @Test func calibrationOnlyAppliesToUntouchedDefaultSeeds() {
        #expect(RunCard().needsCalibration)
        #expect(!RunCard(runSeconds: 112).needsCalibration)
        #expect(!RunCard(seedsCalibrated: true).needsCalibration)
    }

    @Test func applyingRunProgressionMarksTheCardCalibrated() {
        let card = RunCard()
        let routine = Routine(name: "Run", cards: [.run(card)])
        // Same seed values as the defaults — the apply must still stick the flag.
        let applied = routine.applyingRunProgressions([
            RunProgressionUpdate(cardId: card.id, runSeconds: 90, walkSeconds: 120),
        ])
        #expect(applied.firstRunCard?.seedsCalibrated == true)
        #expect(applied != routine) // flag change persists through the store's no-op check
    }

    @Test func progressionNoteDescribesTheNextRun() {
        let note = RunSeeds.progressionNote(
            from: RunSeeds(runSeconds: 90, walkSeconds: 120),
            to: RunSeeds(runSeconds: 120, walkSeconds: 120),
            blockSeconds: 1200
        )
        #expect(note == "Next run: 2 min run · 2 min walk")

        let continuous = RunSeeds.progressionNote(
            from: RunSeeds(runSeconds: 600, walkSeconds: 60),
            to: RunSeeds(runSeconds: 1300, walkSeconds: 60),
            blockSeconds: 1200
        )
        #expect(continuous == "Next run: continuous")

        let unchanged = RunSeeds.progressionNote(
            from: RunSeeds(runSeconds: 90, walkSeconds: 120),
            to: RunSeeds(runSeconds: 90, walkSeconds: 120),
            blockSeconds: 1200
        )
        #expect(unchanged == nil)
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
