import Foundation
import Testing
@testable import AdaptiveCore

/// Codable round-trips and seeding for the strength models, plus the card-model behaviors:
/// resolution, round expansion, and grouping cards into workout blocks.
struct ExerciseModelTests {

    // MARK: - Round-trips

    @Test func exerciseRoundTrips() throws {
        for exercise in ExerciseLibrary.all {
            let data = try JSONEncoder().encode(exercise)
            let decoded = try JSONDecoder().decode(Exercise.self, from: data)
            #expect(decoded == exercise)
        }
    }

    @Test func cardsRoundTrip() throws {
        let cards: [WorkoutCard] = [
            .run(RunCard(durationMinutes: 25)),
            .exercise(StrengthExerciseItem(exerciseId: "db_bench_press", reps: 10, seedWeight: .lb(15))),
            .exercise(StrengthExerciseItem(exerciseId: "plank", holdSeconds: 30)),
            .rest(RestCard(seconds: 45)),
        ]
        let data = try JSONEncoder().encode(cards)
        let decoded = try JSONDecoder().decode([WorkoutCard].self, from: data)
        #expect(decoded == cards)
    }

    @Test func strengthRoutineRoundTrips() throws {
        let routine = Routine(
            name: "Push Day", repeatDays: [.monday],
            cards: [
                .exercise(StrengthExerciseItem(exerciseId: "db_bench_press", reps: 10, seedWeight: .lb(15))),
                .rest(RestCard(seconds: 60)),
                .exercise(StrengthExerciseItem(exerciseId: "plank", holdSeconds: 45)),
            ],
            rounds: 3
        )
        let decoded = try JSONDecoder().decode(Routine.self, from: JSONEncoder().encode(routine))
        #expect(decoded == routine)
        #expect(decoded.rounds == 3)
        #expect(decoded.exerciseItems.count == 2)
    }

    // MARK: - Seeding from the library

    @Test func itemSeedsRepsFromRepExercise() throws {
        let bench = try #require(ExerciseLibrary.exercise(id: "db_bench_press"))
        let item = StrengthExerciseItem(from: bench)
        #expect(item.exerciseId == "db_bench_press")
        #expect(item.reps == 8) // seeds at the bottom of the 8...12 progression band
        #expect(item.seedWeight == .lb(15))
        #expect(item.isHold == false)
    }

    @Test func itemSeedsHoldFromIsometricExercise() throws {
        let plank = try #require(ExerciseLibrary.exercise(id: "plank"))
        let item = StrengthExerciseItem(from: plank)
        #expect(item.reps == nil)
        #expect(item.holdSeconds == 30)
        #expect(item.isHold == true)
    }

    // MARK: - Resolution (N6: drop unknown ids)

    @Test func resolvesKnownItemAndDropsUnknown() {
        #expect(StrengthExerciseItem(exerciseId: "db_curl", reps: 12).resolved()?.exercise.id == "db_curl")
        #expect(StrengthExerciseItem(exerciseId: "no_such", reps: 5).resolved() == nil)
    }

    // MARK: - Workout blocks (auto session switching)

    @Test func consecutiveSameKindCardsMergeIntoOneBlock() {
        let cards: [WorkoutCard] = [
            .exercise(StrengthExerciseItem(exerciseId: "a", reps: 5)),
            .rest(RestCard(seconds: 30)),
            .exercise(StrengthExerciseItem(exerciseId: "b", reps: 5)),
        ]
        let blocks = cards.workoutBlocks()
        #expect(blocks.count == 1)
        #expect(blocks.first?.kind == .strength)
        #expect(blocks.first?.cards.count == 3) // the rest attaches to the strength block
    }

    @Test func kindChangeStartsANewBlock() {
        let cards: [WorkoutCard] = [
            .run(RunCard(durationMinutes: 10)),
            .exercise(StrengthExerciseItem(exerciseId: "a", reps: 5)),
        ]
        let blocks = cards.workoutBlocks()
        #expect(blocks.map(\.kind) == [.run, .strength])
    }

    @Test func leadingRestAttachesToFirstBlock() {
        let cards: [WorkoutCard] = [
            .rest(RestCard(seconds: 15)),
            .exercise(StrengthExerciseItem(exerciseId: "a", reps: 5)),
        ]
        let blocks = cards.workoutBlocks()
        #expect(blocks.count == 1)
        #expect(blocks.first?.cards.count == 2)
    }

    @Test func onlyRestCardsProduceNoBlock() {
        let cards: [WorkoutCard] = [.rest(RestCard(seconds: 30))]
        #expect(cards.workoutBlocks().isEmpty)
    }

    @Test func roundsExpandThenGroup() {
        let routine = Routine(name: "Circuit",
                              cards: [.exercise(StrengthExerciseItem(exerciseId: "push_up", reps: 8)),
                                      .rest(RestCard(seconds: 20))],
                              rounds: 3)
        // One strength block holding all 6 expanded cards (3 push-ups + 3 rests).
        let blocks = routine.expandedCards.workoutBlocks()
        #expect(blocks.count == 1)
        #expect(blocks.first?.cards.count == 6)
    }

    // MARK: - Weight

    @Test func weightAdjustClampsAtZero() {
        #expect(Weight.lb(10).adjusted(byPounds: 5) == .lb(15))
        #expect(Weight.lb(2.5).adjusted(byPounds: -5) == .lb(0))
    }
}
