import Foundation
import Testing
@testable import AdaptiveCore

/// Codable round-trips and seeding behavior for the P1 strength models, plus the backward-compat
/// guarantee that routines persisted before `exercises` existed still decode.
struct ExerciseModelTests {

    // MARK: - Round-trips

    @Test func exerciseRoundTrips() throws {
        for exercise in ExerciseLibrary.all {
            let data = try JSONEncoder().encode(exercise)
            let decoded = try JSONDecoder().decode(Exercise.self, from: data)
            #expect(decoded == exercise)
        }
    }

    @Test func strengthItemAndPlanRoundTrip() throws {
        let plan = StrengthPlan(items: [
            StrengthExerciseItem(exerciseId: "db_bench_press", sets: 3, reps: 10, seedWeight: .lb(15)),
            StrengthExerciseItem(exerciseId: "plank", sets: 3, holdSeconds: 30),
            StrengthExerciseItem(exerciseId: "push_up", sets: 3, reps: 8, seedWeight: nil),
        ])
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(StrengthPlan.self, from: data)
        #expect(decoded == plan)
    }

    @Test func strengthRoutineRoundTrips() throws {
        let routine = Routine(
            name: "Push Day", type: .strength, repeatDays: [.monday],
            exercises: [
                StrengthExerciseItem(exerciseId: "db_bench_press", sets: 3, reps: 10, seedWeight: .lb(15)),
                StrengthExerciseItem(exerciseId: "plank", sets: 3, holdSeconds: 45),
            ]
        )
        let data = try JSONEncoder().encode(routine)
        let decoded = try JSONDecoder().decode(Routine.self, from: data)
        #expect(decoded == routine)
        #expect(decoded.exercises.count == 2)
    }

    // MARK: - Seeding from the library

    @Test func itemSeedsRepsFromRepExercise() throws {
        let bench = try #require(ExerciseLibrary.exercise(id: "db_bench_press"))
        let item = StrengthExerciseItem(from: bench)
        #expect(item.exerciseId == "db_bench_press")
        #expect(item.sets == bench.defaultSets)
        #expect(item.reps == 10)
        #expect(item.seedWeight == .lb(15))
        #expect(item.holdSeconds == nil)
        #expect(item.isHold == false)
    }

    @Test func itemSeedsHoldFromIsometricExercise() throws {
        let plank = try #require(ExerciseLibrary.exercise(id: "plank"))
        let item = StrengthExerciseItem(from: plank)
        #expect(item.reps == nil)
        #expect(item.seedWeight == nil)
        #expect(item.holdSeconds == 30)
        #expect(item.isHold == true)
    }

    @Test func bodyweightRepExerciseSeedsNilWeight() throws {
        let pushUp = try #require(ExerciseLibrary.exercise(id: "push_up"))
        let item = StrengthExerciseItem(from: pushUp)
        #expect(item.reps == 8)
        #expect(item.seedWeight == nil)
        #expect(item.isHold == false)
    }

    // MARK: - Resolution (N6: drop unknown ids, never fabricate)

    @Test func planResolvesKnownItemsAndDropsUnknown() {
        let plan = StrengthPlan(items: [
            StrengthExerciseItem(exerciseId: "db_curl", sets: 3, reps: 12, seedWeight: .lb(12.5)),
            StrengthExerciseItem(exerciseId: "no_such_exercise", sets: 3, reps: 5),
        ])
        let resolved = plan.resolved()
        #expect(resolved.count == 1)
        #expect(resolved.first?.exercise.id == "db_curl")
    }

    @Test func totalSetsSumsItems() {
        let plan = StrengthPlan(items: [
            StrengthExerciseItem(exerciseId: "a", sets: 3, reps: 10),
            StrengthExerciseItem(exerciseId: "b", sets: 4, reps: 8),
        ])
        #expect(plan.totalSets == 7)
    }

    // MARK: - Backward compatibility

    /// A routine JSON written before `exercises` existed must decode with an empty list, never
    /// fail the whole decode — the same guarantee `durationMinutes` got in build 2.
    @Test func decodesPreExercisesRoutineAsEmpty() throws {
        let legacyJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "Old Run",
            "type": "adaptiveRun",
            "repeatDays": [3, 6],
            "durationMinutes": 30,
            "reminderEnabled": false,
            "createdAt": 0
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Routine.self, from: legacyJSON)
        #expect(decoded.exercises.isEmpty)
        #expect(decoded.name == "Old Run")
    }

    // MARK: - Weight

    @Test func weightAdjustClampsAtZero() {
        #expect(Weight.lb(10).adjusted(byPounds: 5) == .lb(15))
        #expect(Weight.lb(2.5).adjusted(byPounds: -5) == .lb(0))
    }

    @Test func weightConvertsToKilograms() {
        // 10 lb ≈ 4.536 kg
        #expect(abs(Weight.lb(10).kilograms - 4.5359237) < 0.0001)
    }
}
