import Foundation
import Testing
@testable import AdaptiveCore

struct ProgressionTests {

    // MARK: - ProgressionUpdate Codable

    @Test func progressionUpdateRoundTrips() throws {
        let updates = [
            ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(30), reps: 12),
            ProgressionUpdate(exerciseId: "push_up", reps: 15),       // bodyweight: weight nil
            ProgressionUpdate(exerciseId: "plank"),                   // hold: both nil
        ]
        for update in updates {
            let data = try JSONEncoder().encode(update)
            let decoded = try JSONDecoder().decode(ProgressionUpdate.self, from: data)
            #expect(decoded == update)
        }
    }

    @Test func progressionBatchRoundTrips() throws {
        let batch = ProgressionBatch(routineId: UUID(), updates: [
            ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(25), reps: 10),
        ])
        let data = try JSONEncoder().encode(batch)
        let decoded = try JSONDecoder().decode(ProgressionBatch.self, from: data)
        #expect(decoded == batch)
    }

    // MARK: - Routine.applyingProgressions

    private func circuit() -> Routine {
        Routine(name: "Circuit", cards: [
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
            .rest(RestCard(seconds: 30)),
            .exercise(StrengthExerciseItem(exerciseId: "push_up", reps: 8, seedWeight: nil)),   // bodyweight
            .exercise(StrengthExerciseItem(exerciseId: "plank", holdSeconds: 30)),              // hold
        ], rounds: 2)
    }

    @Test func appliesWeightAndRepsToMatchingCard() {
        let updated = circuit().applyingProgressions([
            ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(30), reps: 12),
        ])
        let item = updated.exerciseItems.first { $0.exerciseId == "goblet_squat" }
        #expect(item?.seedWeight == .lb(30))
        #expect(item?.reps == 12)
    }

    @Test func emptyUpdatesIsIdentity() {
        let routine = circuit()
        #expect(routine.applyingProgressions([]) == routine)
    }

    @Test func unknownExerciseLeavesRoutineUnchanged() {
        let routine = circuit()
        #expect(routine.applyingProgressions([ProgressionUpdate(exerciseId: "nonexistent", weight: .lb(99))]) == routine)
    }

    @Test func nilWeightLeavesLoadUntouched() {
        let updated = circuit().applyingProgressions([
            ProgressionUpdate(exerciseId: "goblet_squat", weight: nil, reps: 15),
        ])
        let item = updated.exerciseItems.first { $0.exerciseId == "goblet_squat" }
        #expect(item?.seedWeight == .lb(20)) // unchanged
        #expect(item?.reps == 15)
    }

    @Test func weightUpdateIgnoredOnBodyweightCard() {
        // A bodyweight card (seedWeight == nil) is never turned into a weighted one (N6).
        let updated = circuit().applyingProgressions([
            ProgressionUpdate(exerciseId: "push_up", weight: .lb(45), reps: 12),
        ])
        let item = updated.exerciseItems.first { $0.exerciseId == "push_up" }
        #expect(item?.seedWeight == nil)
        #expect(item?.reps == 12) // reps still advance
    }

    @Test func repsUpdateIgnoredOnHoldCard() {
        // A hold (reps == nil) is never given reps; its hold seconds are left alone.
        let updated = circuit().applyingProgressions([
            ProgressionUpdate(exerciseId: "plank", reps: 20),
        ])
        let item = updated.exerciseItems.first { $0.exerciseId == "plank" }
        #expect(item?.reps == nil)
        #expect(item?.holdSeconds == 30)
    }

    @Test func appliesToEveryCardOfSameExercise() {
        let routine = Routine(name: "Doubled", cards: [
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
        ])
        let updated = routine.applyingProgressions([ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(25))])
        #expect(updated.exerciseItems.allSatisfy { $0.seedWeight == .lb(25) })
    }

    @Test func applyIsIdempotent() {
        let once = circuit().applyingProgressions([ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(30))])
        let twice = once.applyingProgressions([ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(30))])
        #expect(once == twice)
    }

    // MARK: - RoutineStore.applyProgressions

    @MainActor
    private func makeStore(onChange: (@MainActor ([Routine]) -> Void)? = nil) -> RoutineStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routines-\(UUID().uuidString).json")
        return RoutineStore(fileURL: url, onChange: onChange)
    }

    @MainActor
    @Test func storeAppliesAndPersists() {
        let store = makeStore()
        let routine = circuit()
        store.add(routine)
        let changed = store.applyProgressions([ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(30))],
                                              toRoutineId: routine.id, broadcast: false)
        #expect(changed)
        let item = store.routines.first?.exerciseItems.first { $0.exerciseId == "goblet_squat" }
        #expect(item?.seedWeight == .lb(30))
    }

    @MainActor
    @Test func storeApplyMissingRoutineIsNoOp() {
        let store = makeStore()
        #expect(!store.applyProgressions([ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(30))],
                                         toRoutineId: UUID(), broadcast: true))
    }

    @MainActor
    @Test func storeApplyIsIdempotentNoOpSecondTime() {
        let store = makeStore()
        let routine = circuit()
        store.add(routine)
        let updates = [ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(30))]
        #expect(store.applyProgressions(updates, toRoutineId: routine.id, broadcast: false))
        #expect(!store.applyProgressions(updates, toRoutineId: routine.id, broadcast: false)) // already converged
    }

    @Test func holdProgressionAppliesOnlyToHoldCards() {
        let plank = StrengthExerciseItem(exerciseId: "plank", holdSeconds: 30)
        let squat = StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))
        let routine = Routine(name: "Core", cards: [.exercise(plank), .exercise(squat)])
        let updated = routine.applyingProgressions([
            ProgressionUpdate(exerciseId: "plank", holdSeconds: 35),
            ProgressionUpdate(exerciseId: "goblet_squat", holdSeconds: 35), // shape-guarded no-op
        ])
        #expect(updated.exerciseItems.first { $0.exerciseId == "plank" }?.holdSeconds == 35)
        #expect(updated.exerciseItems.first { $0.exerciseId == "goblet_squat" }?.holdSeconds == nil)
    }

    @MainActor
    @Test func storeApplyBroadcastFiresOnce() {
        var broadcasts = 0
        let store = makeStore { _ in broadcasts += 1 }
        let routine = circuit()
        store.add(routine)                       // 1 broadcast (add)
        broadcasts = 0
        _ = store.applyProgressions([ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(30))],
                                    toRoutineId: routine.id, broadcast: true)
        #expect(broadcasts == 1)
    }

    @MainActor
    @Test func storeApplyNoBroadcastWhenFalse() {
        var broadcasts = 0
        let store = makeStore { _ in broadcasts += 1 }
        let routine = circuit()
        store.add(routine)
        broadcasts = 0
        _ = store.applyProgressions([ProgressionUpdate(exerciseId: "goblet_squat", weight: .lb(30))],
                                    toRoutineId: routine.id, broadcast: false)
        #expect(broadcasts == 0)
    }
}
