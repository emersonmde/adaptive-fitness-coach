import Foundation
import Testing
@testable import AdaptiveCore

struct StrengthProgressionPolicyTests {

    private let policy = StrengthProgressionPolicy()
    // goblet_squat: 8...12, 5 lb step, weighted compound.
    private var squat: Exercise { ExerciseLibrary.exercise(id: "goblet_squat")! }
    // push_up: 8...20, bodyweight.
    private var pushUp: Exercise { ExerciseLibrary.exercise(id: "push_up")! }
    // plank: hold.
    private var plank: Exercise { ExerciseLibrary.exercise(id: "plank")! }

    private func outcome(
        id: String = "goblet_squat", planned: Int = 3, completed: Int = 3,
        reps: [Int], prescribed: Int = 10,
        unrecovered: Int = 0,
        lowered: Bool = false, raised: Bool = false, repsChanged: Bool = false
    ) -> StrengthExerciseOutcome {
        StrengthExerciseOutcome(
            exerciseId: id, setsPlanned: planned, setsCompleted: completed,
            completedRepsPerSet: reps, prescribedReps: prescribed,
            unrecoveredRests: unrecovered,
            weightManuallyLowered: lowered, weightManuallyRaised: raised,
            repsManuallyChanged: repsChanged
        )
    }

    // MARK: - Double progression (ACSM 2009 / NSCA 2-for-2 lineage)

    @Test func cleanSessionBelowTopAddsOneRep() {
        let current = StrengthPrescription(reps: 10, weight: .lb(20))
        let next = policy.nextPrescription(current: current, exercise: squat,
                                           outcome: outcome(reps: [10, 10, 10]), endedEarly: false)
        #expect(next.reps == 11)
        #expect(next.weight == .lb(20))
    }

    @Test func cleanSessionAtTopStepsWeightAndResetsReps() {
        let current = StrengthPrescription(reps: 12, weight: .lb(20))
        let next = policy.nextPrescription(current: current, exercise: squat,
                                           outcome: outcome(reps: [12, 12, 13], prescribed: 12), endedEarly: false)
        #expect(next.weight == .lb(25)) // +5 compound step
        #expect(next.reps == 8)         // back to the bottom of the band
    }

    @Test func isolationStepsOnTheFiveGrid() {
        let curl = ExerciseLibrary.exercise(id: "db_curl")! // 10...15, 5 lb (real-dumbbell grid)
        let current = StrengthPrescription(reps: 15, weight: .lb(10))
        let next = policy.nextPrescription(current: current, exercise: curl,
                                           outcome: outcome(id: "db_curl", reps: [15, 15, 15], prescribed: 15), endedEarly: false)
        #expect(next.weight == .lb(15)) // +5
        #expect(next.reps == 10)
    }

    // MARK: - Legacy off-grid loads (pre-grid 2.5-step seeds, e.g. the stuck 22.5)

    @Test func offGridLoadAdvancesToTheAdjacentMultipleOfFive() {
        let curl = ExerciseLibrary.exercise(id: "db_curl")!
        let current = StrengthPrescription(reps: 15, weight: .lb(22.5))
        let next = policy.nextPrescription(current: current, exercise: curl,
                                           outcome: outcome(id: "db_curl", reps: [15, 15, 15], prescribed: 15), endedEarly: false)
        #expect(next.weight == .lb(25)) // adjacent grid point, not 27.5
    }

    @Test func offGridLoadSnapsDownOnHold() {
        let curl = ExerciseLibrary.exercise(id: "db_curl")!
        let current = StrengthPrescription(reps: 12, weight: .lb(22.5))
        let next = policy.nextPrescription(current: current, exercise: curl,
                                           outcome: outcome(id: "db_curl", reps: [11, 12, 12], prescribed: 12), endedEarly: false)
        #expect(next.weight == .lb(20)) // a hold still converges to the grid; midpoint eases
        #expect(next.reps == 12)
    }

    @Test func twoShortSetsEaseOneRep() {
        let current = StrengthPrescription(reps: 10, weight: .lb(20))
        let next = policy.nextPrescription(current: current, exercise: squat,
                                           outcome: outcome(reps: [8, 8, 10]), endedEarly: false)
        #expect(next.reps == 9)
        #expect(next.weight == .lb(20))
    }

    @Test func oneShortSetHolds() {
        let current = StrengthPrescription(reps: 10, weight: .lb(20))
        let next = policy.nextPrescription(current: current, exercise: squat,
                                           outcome: outcome(reps: [8, 10, 10]), endedEarly: false)
        #expect(next == current)
    }

    @Test func easeAtBottomStepsWeightDown() {
        let current = StrengthPrescription(reps: 8, weight: .lb(20))
        let next = policy.nextPrescription(current: current, exercise: squat,
                                           outcome: outcome(reps: [5, 5, 8], prescribed: 8), endedEarly: false)
        #expect(next.weight == .lb(15))
        #expect(next.reps == 8)
    }

    @Test func easedWeightNeverFallsBelowTheSmallestDumbbell() {
        let curl = ExerciseLibrary.exercise(id: "db_curl")!
        let current = StrengthPrescription(reps: 10, weight: .lb(5))
        let next = policy.nextPrescription(current: current, exercise: curl,
                                           outcome: outcome(id: "db_curl", reps: [7, 7, 7], prescribed: 10), endedEarly: false)
        #expect(next.weight == .lb(5)) // floored at the 5 lb grid unit
    }

    // MARK: - Advance gates

    @Test func manualWeightLoweringEasesAndNeverAdvances() {
        let current = StrengthPrescription(reps: 10, weight: .lb(15)) // already folded-in lower weight
        let next = policy.nextPrescription(current: current, exercise: squat,
                                           outcome: outcome(reps: [10, 10, 10], lowered: true), endedEarly: false)
        #expect(next.reps == 9) // struggle evidence → ease from the manual base
    }

    @Test func manualRaiseFreezesTheDimension() {
        // User bumped weight mid-session (folded into current) — policy must not stack +1 rep.
        let current = StrengthPrescription(reps: 10, weight: .lb(25))
        let next = policy.nextPrescription(current: current, exercise: squat,
                                           outcome: outcome(reps: [10, 10, 10], raised: true), endedEarly: false)
        #expect(next == current)
    }

    @Test func unrecoveredRestsBlockAdvanceButDoNotEase() {
        let current = StrengthPrescription(reps: 10, weight: .lb(20))
        let next = policy.nextPrescription(current: current, exercise: squat,
                                           outcome: outcome(reps: [10, 10, 10], unrecovered: 2), endedEarly: false)
        #expect(next == current) // hold: suspicion downgrades advance, never eases
    }

    @Test func endedEarlyWithHalfDoneEases() {
        let current = StrengthPrescription(reps: 10, weight: .lb(20))
        let next = policy.nextPrescription(current: current, exercise: squat,
                                           outcome: outcome(completed: 1, reps: [10]), endedEarly: true)
        #expect(next.reps == 9)
    }

    @Test func endedEarlyWithMostDoneHolds() {
        let current = StrengthPrescription(reps: 10, weight: .lb(20))
        let next = policy.nextPrescription(current: current, exercise: squat,
                                           outcome: outcome(completed: 2, reps: [10, 10]), endedEarly: true)
        #expect(next == current) // unattempted sets are not failures
    }

    // MARK: - Bodyweight & holds

    @Test func bodyweightClimbsThenHoldsAtTop() {
        let climbing = policy.nextPrescription(
            current: StrengthPrescription(reps: 12),
            exercise: pushUp,
            outcome: outcome(id: "push_up", reps: [12, 12, 12], prescribed: 12), endedEarly: false)
        #expect(climbing.reps == 13)

        let atTop = policy.nextPrescription(
            current: StrengthPrescription(reps: 20),
            exercise: pushUp,
            outcome: outcome(id: "push_up", reps: [20, 20, 20], prescribed: 20), endedEarly: false)
        #expect(atTop.reps == 20) // no weight to step into — P3 suggests harder variations
    }

    @Test func holdsProgressAndRegressByFiveSeconds() {
        let holdOutcome = StrengthExerciseOutcome(
            exerciseId: "plank", setsPlanned: 3, setsCompleted: 3,
            completedHoldSecondsPerSet: [30, 30, 30], prescribedHoldSeconds: 30
        )
        let up = policy.nextPrescription(current: StrengthPrescription(holdSeconds: 30),
                                         exercise: plank, outcome: holdOutcome, endedEarly: false)
        #expect(up.holdSeconds == 35)

        let struggling = StrengthExerciseOutcome(
            exerciseId: "plank", setsPlanned: 3, setsCompleted: 3,
            completedHoldSecondsPerSet: [20, 22, 30], prescribedHoldSeconds: 30
        )
        let down = policy.nextPrescription(current: StrengthPrescription(holdSeconds: 30),
                                           exercise: plank, outcome: struggling, endedEarly: false)
        #expect(down.holdSeconds == 25)
    }

    @Test func holdBoundsAreEnforced() {
        let clean = StrengthExerciseOutcome(exerciseId: "plank", setsPlanned: 1, setsCompleted: 1,
                                            completedHoldSecondsPerSet: [120], prescribedHoldSeconds: 120)
        let capped = policy.nextPrescription(current: StrengthPrescription(holdSeconds: 120),
                                             exercise: plank, outcome: clean, endedEarly: false)
        #expect(capped.holdSeconds == 120)

        let bad = StrengthExerciseOutcome(exerciseId: "plank", setsPlanned: 3, setsCompleted: 3,
                                          completedHoldSecondsPerSet: [5, 5, 5], prescribedHoldSeconds: 15)
        let floored = policy.nextPrescription(current: StrengthPrescription(holdSeconds: 15),
                                              exercise: plank, outcome: bad, endedEarly: false)
        #expect(floored.holdSeconds == 15)
    }

    @Test func outOfRangeSeedIsClampedIntoTheBand() {
        // Hand-edited seed above the band: clamped before any decision applies.
        let current = StrengthPrescription(reps: 30, weight: .lb(20))
        let next = policy.nextPrescription(current: current, exercise: squat,
                                           outcome: outcome(completed: 0, reps: [], prescribed: 30), endedEarly: false)
        #expect(next.reps == 12)
    }

    // MARK: - Aggregation

    @Test func setLogAggregatesByExercise() {
        let log = [
            StrengthSetRecord(exerciseId: "goblet_squat", prescribedReps: 10, completedReps: 10, restRecovered: true),
            StrengthSetRecord(exerciseId: "goblet_squat", prescribedReps: 10, completedReps: 8, restRecovered: false),
            StrengthSetRecord(exerciseId: "plank", prescribedHoldSeconds: 30, completedHoldSeconds: 30),
        ]
        let outcome = StrengthSessionOutcome(
            setLog: log,
            plannedSetsByExercise: ["goblet_squat": 2, "plank": 1],
            loweredWeight: ["goblet_squat"]
        )
        let squatOutcome = outcome.exercises.first { $0.exerciseId == "goblet_squat" }!
        #expect(squatOutcome.setsCompleted == 2)
        #expect(squatOutcome.completedRepsPerSet == [10, 8])
        #expect(squatOutcome.unrecoveredRests == 1)
        #expect(squatOutcome.weightManuallyLowered)
        let plankOutcome = outcome.exercises.first { $0.exerciseId == "plank" }!
        #expect(plankOutcome.completedHoldSecondsPerSet == [30])
    }

    // MARK: - Property sweep

    @Test func prescriptionsStayInBandForAllOutcomes() {
        // Deterministic pseudo-random sweep: whatever the outcome, results stay in band,
        // deltas are single steps, and nil-ness never flips (N6).
        var state: UInt64 = 0x9E3779B97F4A7C15
        func rand(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }

        let exercises = [squat, pushUp, plank, ExerciseLibrary.exercise(id: "db_curl")!]
        for _ in 0..<4000 {
            let exercise = exercises[rand(exercises.count)]
            let isHold = exercise.kind.isHold
            let range = exercise.repRange
            let currentReps = range.map { $0.lowerBound + rand($0.count + 6) - 3 } // may be out of band
            let weight: Weight? = {
                if isHold { return nil }
                // Deliberately includes off-grid legacy values (2.5 steps) — the policy
                // must converge them onto the 5 lb grid, whatever the decision.
                if case let .reps(_, seed) = exercise.kind, seed != nil { return .lb(Double(rand(10)) * 2.5 + 2.5) }
                return nil
            }()
            let current = StrengthPrescription(
                reps: isHold ? nil : currentReps,
                weight: weight,
                holdSeconds: isHold ? TimeInterval(rand(140) + 5) : nil
            )
            let prescribed = currentReps ?? 10
            let reps = (0..<rand(4)).map { _ in max(0, prescribed - rand(5)) }
            let holds = (0..<rand(4)).map { _ in TimeInterval(max(0, 30 - rand(20))) }
            let o = StrengthExerciseOutcome(
                exerciseId: exercise.id, setsPlanned: rand(4), setsCompleted: reps.count + holds.count,
                completedRepsPerSet: isHold ? [] : reps, prescribedReps: isHold ? nil : prescribed,
                completedHoldSecondsPerSet: isHold ? holds : [], prescribedHoldSeconds: isHold ? 30 : nil,
                unrecoveredRests: rand(3),
                weightManuallyLowered: rand(4) == 0, weightManuallyRaised: rand(4) == 0,
                repsManuallyChanged: rand(4) == 0
            )
            let endedEarly = rand(3) == 0
            let next = policy.nextPrescription(current: current, exercise: exercise, outcome: o, endedEarly: endedEarly)

            // Nil-ness never flips.
            #expect((next.reps == nil) == (current.reps == nil))
            #expect((next.weight == nil) == (current.weight == nil))
            #expect((next.holdSeconds == nil) == (current.holdSeconds == nil))
            // In band.
            if let range, let reps = next.reps {
                #expect(range.contains(reps))
            }
            if let hold = next.holdSeconds {
                #expect(hold >= policy.config.holdFloor && hold <= policy.config.holdCap)
            }
            // Deltas are single steps (post-clamp comparisons).
            if let w = current.weight, let nw = next.weight {
                // At most one step in either direction; the ease floor (5 lb) and the grid
                // snap can shorten a step, never lengthen one.
                let delta = abs(nw.pounds - w.pounds)
                #expect(delta <= exercise.weightStepPounds + 0.001)
                // Whatever the decision, the proposed load lands on the 5 lb grid.
                let remainder = nw.pounds.truncatingRemainder(dividingBy: 5)
                #expect(min(remainder, 5 - remainder) < 0.001)
            }
        }
    }
}
