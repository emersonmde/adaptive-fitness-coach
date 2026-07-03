import Foundation
import Testing
@testable import AdaptiveCore

/// Build 9: perceived-effort (RPE) gating on both progression policies. The invariant under
/// test everywhere: effort only ever *lowers* aggressiveness — it holds an otherwise-clean
/// advance and suppresses the run snap; it never eases, and never makes progression push harder.
struct EffortProgressionTests {

    // MARK: - Run

    private let runPolicy = RunProgressionPolicy()
    private let seeds = RunSeeds(runSeconds: 120, walkSeconds: 120)

    private func cleanOutcome(effort: Int? = nil) -> RunSessionOutcome {
        RunSessionOutcome(
            plannedRunIntervals: 4, completedRunIntervals: 4, runBackOffCount: 0,
            walksHitCap: 0, perceivedEffort: effort
        )
    }

    @Test func cleanRunAdvancesWhenEffortLowOrUnrated() {
        #expect(runPolicy.nextSeeds(current: seeds, outcome: cleanOutcome(effort: nil)).runSeconds > seeds.runSeconds)
        #expect(runPolicy.nextSeeds(current: seeds, outcome: cleanOutcome(effort: 5)).runSeconds > seeds.runSeconds)
        #expect(runPolicy.nextSeeds(current: seeds, outcome: cleanOutcome(effort: 7)).runSeconds > seeds.runSeconds)
    }

    @Test func highEffortHoldsACleanRun() {
        // 8/10 or 10/10 on an otherwise-clean session → hold, not advance.
        #expect(runPolicy.nextSeeds(current: seeds, outcome: cleanOutcome(effort: 8)) == seeds)
        #expect(runPolicy.nextSeeds(current: seeds, outcome: cleanOutcome(effort: 10)) == seeds)
    }

    @Test func highEffortSuppressesTheSnap() {
        // A long run (demonstrated capacity) that felt all-out must NOT snap the seed up.
        let longRun = RunSessionOutcome(
            plannedRunIntervals: 3, completedRunIntervals: 3, runBackOffCount: 0, walksHitCap: 0,
            longestRunSeconds: 300, perceivedEffort: 9   // 300s ≥ 120×1.5 would normally snap
        )
        #expect(runPolicy.nextSeeds(current: seeds, outcome: longRun) == seeds)
        // Same session at low effort DOES snap.
        var lowEffort = longRun; lowEffort.perceivedEffort = 4
        #expect(runPolicy.nextSeeds(current: seeds, outcome: lowEffort).runSeconds >= 300)
    }

    @Test func highEffortNeverEasesAStruggleFurther() {
        // A struggle already regresses; adding high effort must not regress *more* than the
        // struggle rule alone (effort never increases aggressiveness in either direction).
        let struggle = RunSessionOutcome(
            plannedRunIntervals: 4, completedRunIntervals: 4, runBackOffCount: 3, walksHitCap: 0
        )
        var struggleHighEffort = struggle; struggleHighEffort.perceivedEffort = 10
        #expect(runPolicy.nextSeeds(current: seeds, outcome: struggleHighEffort)
                == runPolicy.nextSeeds(current: seeds, outcome: struggle))
    }

    @Test func effortFlowsThroughSummary() {
        var summary = SessionSummary(totalDuration: 600, intervalsCompleted: 4, plannedRunIntervals: 4)
        summary.perceivedEffort = 9
        #expect(RunSessionOutcome(summary: summary).perceivedEffort == 9)
    }

    // MARK: - Strength

    private let strengthPolicy = StrengthProgressionPolicy()
    private var squat: Exercise { ExerciseLibrary.exercise(id: "goblet_squat")! }

    /// A clean squat set: all planned sets done at/above prescription, rests recovered.
    private func cleanSquatOutcome() -> StrengthExerciseOutcome {
        StrengthExerciseOutcome(
            exerciseId: "goblet_squat", setsPlanned: 3, setsCompleted: 3,
            completedRepsPerSet: [10, 10, 10], prescribedReps: 10, unrecoveredRests: 0
        )
    }

    @Test func cleanStrengthAdvancesWhenEffortLow() {
        #expect(strengthPolicy.decision(for: cleanSquatOutcome(), endedEarly: false, perceivedEffort: nil) == .advance)
        #expect(strengthPolicy.decision(for: cleanSquatOutcome(), endedEarly: false, perceivedEffort: 6) == .advance)
    }

    @Test func highEffortHoldsACleanStrengthSession() {
        #expect(strengthPolicy.decision(for: cleanSquatOutcome(), endedEarly: false, perceivedEffort: 8) == .hold)
        #expect(strengthPolicy.decision(for: cleanSquatOutcome(), endedEarly: false, perceivedEffort: 10) == .hold)
    }

    @Test func highEffortStrengthPrescriptionHoldsReps() {
        let current = StrengthPrescription(reps: 10, weight: .lb(20))
        let advanced = strengthPolicy.nextPrescription(
            current: current, exercise: squat, outcome: cleanSquatOutcome(), endedEarly: false, perceivedEffort: 6
        )
        let held = strengthPolicy.nextPrescription(
            current: current, exercise: squat, outcome: cleanSquatOutcome(), endedEarly: false, perceivedEffort: 9
        )
        #expect(advanced.reps == 11)   // low effort: +1 rep
        #expect(held.reps == 10)       // high effort: held
    }

    @Test func highEffortNeverEasesAStrengthStruggle() {
        // Short sets already ease; high effort must not ease further.
        let struggle = StrengthExerciseOutcome(
            exerciseId: "goblet_squat", setsPlanned: 3, setsCompleted: 3,
            completedRepsPerSet: [6, 6, 6], prescribedReps: 10
        )
        #expect(strengthPolicy.decision(for: struggle, endedEarly: false, perceivedEffort: 10) == .ease)
        #expect(strengthPolicy.decision(for: struggle, endedEarly: false, perceivedEffort: 10)
                == strengthPolicy.decision(for: struggle, endedEarly: false, perceivedEffort: nil))
    }
}
