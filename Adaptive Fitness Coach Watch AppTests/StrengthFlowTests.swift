import Foundation
import Testing
import AdaptiveCore
@testable import Adaptive_Fitness_Coach_Watch_App

/// Integration tests for the on-watch strength flow. They drive `StrengthSessionManager` with a
/// `SimulatedStrengthBackend`, walking a flat card block (exercise/rest) by calling `advance()` —
/// the user-driven analogue of the run flow's tick loop — so progression, rest, weight adjust,
/// and failure are covered without HealthKit or a clock.
@MainActor
private final class FailingStrengthBackend: WorkoutBackend {
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

@MainActor
struct StrengthFlowTests {

    private func makeManager() -> StrengthSessionManager {
        // autoTick off: tests drive rest/hold time via tick(delta:) deterministically.
        StrengthSessionManager(backend: SimulatedStrengthBackend(), autoTick: false)
    }

    /// Two exercises with a rest between, then a plank — 3 exercise cards, 1 rest card.
    private func sampleCards() -> [WorkoutCard] {
        [
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
            .rest(RestCard(seconds: 30)),
            .exercise(StrengthExerciseItem(exerciseId: "db_bench_press", reps: 10, seedWeight: .lb(15))),
            .exercise(StrengthExerciseItem(exerciseId: "plank", holdSeconds: 30)),
        ]
    }

    private func waitUntilComplete(_ manager: StrengthSessionManager) async {
        for _ in 0..<200 {
            if manager.sessionState == .complete { return }
            await Task.yield()
        }
    }

    // MARK: - Lifecycle

    @Test func beginActivatesAtFirstExercise() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        #expect(manager.sessionState == .active)
        #expect(manager.activity == .exercise)
        #expect(manager.currentExercise?.id == "goblet_squat")
        #expect(manager.exercisePosition.total == 3)
    }

    @Test func emptyBlockFails() async {
        let manager = makeManager()
        await manager.begin(cards: [], routineName: "Empty")
        #expect(manager.sessionState == .failed)
        #expect(manager.summary == nil)
    }

    @Test func blockOfOnlyUnknownIdsFails() async {
        let manager = makeManager()
        await manager.begin(cards: [.exercise(StrengthExerciseItem(exerciseId: "ghost", reps: 5))], routineName: "Ghosts")
        #expect(manager.sessionState == .failed)
    }

    @Test func leadingRestIsSkipped() async {
        let manager = makeManager()
        await manager.begin(cards: [.rest(RestCard(seconds: 30)),
                                    .exercise(StrengthExerciseItem(exerciseId: "push_up", reps: 8))],
                            routineName: "R")
        #expect(manager.activity == .exercise)
        #expect(manager.currentExercise?.id == "push_up")
    }

    // MARK: - Progression through exercises and rests

    @Test func advanceWalksExercisesAndRests() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")

        // Exercise 1 → advance lands on the rest card.
        manager.advance()
        #expect(manager.activity == .rest)
        #expect(manager.currentRestSeconds == 30)

        // Rest done → advance to exercise 2.
        manager.advance()
        #expect(manager.activity == .exercise)
        #expect(manager.currentExercise?.id == "db_bench_press")

        // → plank (hold) exercise.
        manager.advance()
        #expect(manager.currentExercise?.id == "plank")
        #expect(manager.currentItem?.isHold == true)
    }

    @Test func exercisePositionTracks() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        #expect(manager.exercisePosition.current == 1)
        manager.advance() // rest
        manager.advance() // exercise 2
        #expect(manager.exercisePosition.current == 2)
    }

    @Test func finishesAfterLastCard() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        for _ in 0..<4 { manager.advance() } // ex, rest, ex, plank → past the end
        await waitUntilComplete(manager)
        #expect(manager.sessionState == .complete)
        #expect(manager.summary?.exercisesCompleted == 3)
        // Average HR fills in from the background HealthKit finalize (deterministic seam).
        await manager.finalizeTask?.value
        #expect(manager.summary?.averageHeartRate == 121)
        #expect(manager.healthSaveState == .saved)
    }

    // MARK: - Weight adjust (N7 seed, applies across rounds)

    @Test func adjustWeightChangesCurrentExerciseLoad() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        manager.adjustWeight(byPounds: 5)
        #expect(manager.currentItem?.seedWeight == .lb(25))
        manager.adjustWeight(byPounds: -10)
        #expect(manager.currentItem?.seedWeight == .lb(15))
    }

    @Test func adjustWeightClampsAtZero() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        manager.adjustWeight(byPounds: -1000)
        #expect(manager.currentItem?.seedWeight == .lb(0))
    }

    /// The same movement appearing again (e.g. a later round) reflects the earlier adjustment.
    @Test func weightAdjustmentAppliesToLaterRoundsOfSameExercise() async {
        let manager = makeManager()
        let bench = WorkoutCard.exercise(StrengthExerciseItem(exerciseId: "db_bench_press", reps: 10, seedWeight: .lb(15)))
        await manager.begin(cards: [bench, bench], routineName: "Bench×2")
        manager.adjustWeight(byPounds: 5)
        #expect(manager.currentItem?.seedWeight == .lb(20))
        manager.advance() // second instance of the same exercise
        #expect(manager.currentItem?.seedWeight == .lb(20))
    }

    @Test func adjustWeightIsNoOpForHold() async {
        let manager = makeManager()
        await manager.begin(cards: [.exercise(StrengthExerciseItem(exerciseId: "plank", holdSeconds: 30))], routineName: "Core")
        manager.adjustWeight(byPounds: 5)
        #expect(manager.currentItem?.seedWeight == nil)
    }

    // MARK: - Rep adjust (mirrors weight: N7 seed, applies across rounds)

    @Test func adjustRepsChangesCurrentExerciseReps() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        manager.adjustReps(by: 2)
        #expect(manager.currentItem?.reps == 12)
        manager.adjustReps(by: -5)
        #expect(manager.currentItem?.reps == 7)
    }

    @Test func adjustRepsClampsAtOne() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        manager.adjustReps(by: -100)
        #expect(manager.currentItem?.reps == 1)
    }

    @Test func adjustRepsIsNoOpForHold() async {
        let manager = makeManager()
        await manager.begin(cards: [.exercise(StrengthExerciseItem(exerciseId: "plank", holdSeconds: 30))], routineName: "Core")
        manager.adjustReps(by: 5)
        #expect(manager.currentItem?.reps == nil)
    }

    @Test func repsAdjustmentAppliesToLaterRoundsOfSameExercise() async {
        let manager = makeManager()
        let bench = WorkoutCard.exercise(StrengthExerciseItem(exerciseId: "db_bench_press", reps: 10, seedWeight: .lb(15)))
        await manager.begin(cards: [bench, bench], routineName: "Bench×2")
        manager.adjustReps(by: 2)
        #expect(manager.currentItem?.reps == 12)
        manager.advance()
        #expect(manager.currentItem?.reps == 12)
    }

    // MARK: - Progression recording (emitted on finish for a real routine)

    @Test func pendingProgressionsCarriesBothAdjustedDimensions() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineId: UUID(), routineName: "Push Day")
        manager.adjustWeight(byPounds: 5)
        manager.adjustReps(by: 2)
        let updates = manager.pendingProgressions(now: Date(timeIntervalSince1970: 0))
        #expect(updates.count == 1)
        let update = updates.first
        #expect(update?.exerciseId == "goblet_squat")
        #expect(update?.weight == .lb(25))
        #expect(update?.reps == 12)
    }

    @Test func onProgressionsFiresOnFinishWithRoutineId() async {
        let manager = makeManager()
        let routineId = UUID()
        var captured: (routineId: UUID, updates: [ProgressionUpdate])?
        manager.onProgressions = { id, updates in captured = (id, updates) }
        await manager.begin(cards: sampleCards(), routineId: routineId, routineName: "Push Day")
        manager.adjustWeight(byPounds: 5)
        manager.endManually()
        await waitUntilComplete(manager)
        #expect(captured?.routineId == routineId)
        #expect(captured?.updates.first?.exerciseId == "goblet_squat")
        #expect(captured?.updates.first?.weight == .lb(25))
    }

    @Test func noProgressionsWithoutRoutineId() async {
        let manager = makeManager()
        var fired = false
        manager.onProgressions = { _, _ in fired = true }
        await manager.begin(cards: sampleCards(), routineName: "Push Day") // no routineId (e.g. demo)
        manager.adjustWeight(byPounds: 5)
        manager.endManually()
        await waitUntilComplete(manager)
        #expect(!fired)
    }

    @Test func noProgressionsWhenNothingAdjusted() async {
        let manager = makeManager()
        var fired = false
        manager.onProgressions = { _, _ in fired = true }
        await manager.begin(cards: sampleCards(), routineId: UUID(), routineName: "Push Day")
        manager.endManually()
        await waitUntilComplete(manager)
        #expect(!fired)
    }

    @Test func resetClearsRepOverrides() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineId: UUID(), routineName: "Push Day")
        manager.adjustReps(by: 3)
        manager.reset()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        #expect(manager.currentItem?.reps == 10) // back to the seed
        #expect(manager.routineId == nil)
    }

    // MARK: - Failure & manual end

    @Test func startFailureSurfacesFailedWithoutFakingCompletion() async {
        let manager = StrengthSessionManager(backend: FailingStrengthBackend(), autoTick: false)
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        #expect(manager.sessionState == .failed)
        #expect(manager.summary == nil)
    }

    @Test func runtimeFailureStopsTheSession() async {
        let backend = FailingStrengthBackend(failOnStart: false)
        let manager = StrengthSessionManager(backend: backend)
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        #expect(manager.sessionState == .active)
        backend.onFailure?()
        #expect(manager.sessionState == .failed)
    }

    @Test func endManuallyCompletesAndBuildsSummary() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        manager.endManually()
        await waitUntilComplete(manager)
        #expect(manager.sessionState == .complete)
        #expect(manager.summary != nil)
    }

    @Test func resetReturnsToIdle() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        for _ in 0..<4 { manager.advance() }
        await waitUntilComplete(manager)
        manager.reset()
        #expect(manager.sessionState == .idle)
        #expect(manager.summary == nil)
        #expect(manager.cards.isEmpty)
    }

    // MARK: - P2: set capture, adaptive rest, holds, progression

    /// Advance to the first rest card (complete the first exercise's set).
    private func advanceToRest(_ manager: StrengthSessionManager) {
        manager.completeSet() // goblet_squat set → rest card
        #expect(manager.activity == .rest)
    }

    @Test func repsPendingSeedsFromPrescriptionPerCard() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        #expect(manager.repsPending == 10) // goblet_squat prescription
        manager.repsPending = 7            // crown adjusted down
        manager.completeSet()
        manager.skipRest()
        #expect(manager.repsPending == 10) // bench prescription re-seeds the pending count
    }

    @Test func completeSetRecordsPrescribedVsCompleted() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        manager.repsPending = 8
        manager.completeSet()
        #expect(manager.setLog.count == 1)
        #expect(manager.setLog[0].exerciseId == "goblet_squat")
        #expect(manager.setLog[0].prescribedReps == 10)
        #expect(manager.setLog[0].completedReps == 8)
        #expect(manager.setLog[0].weight == .lb(20))
    }

    @Test func restCountsDownViaTickAndAutoAdvances() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        advanceToRest(manager) // 30s rest card, no HR seen → plain timer (N6)
        #expect(!manager.restUsesHeartRate)
        for _ in 0..<29 { manager.tick(delta: 1) }
        #expect(manager.activity == .rest)
        #expect(!manager.restIsReady)
        manager.tick(delta: 1)                 // 30s: timer expires → READY latch
        #expect(manager.restIsReady)
        manager.tick(delta: 1)                 // grace...
        manager.tick(delta: 1)                 // ...2s grace elapses → auto-advance
        #expect(manager.activity == .exercise) // bench
        #expect(manager.setLog[0].restRecovered == nil) // no HR → no recovery claim (N6)
    }

    @Test func adaptiveRestEndsEarlyOnHeartRateRecovery() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        manager.receiveHeartRate(150)          // set peak
        advanceToRest(manager)
        #expect(manager.restUsesHeartRate)
        manager.receiveHeartRate(125)          // 25 bpm drop → recovered signal
        // 30s seed → floor min(30, max(45, 22.5)) = 30... floor clamps to seed, so recovery
        // can only trim the sustained-window path if floor < seed; with a 30s seed the rest
        // ends at 30 regardless — use readiness to assert HR mode engaged.
        for _ in 0..<10 { manager.tick(delta: 1) }
        #expect(manager.restReadiness == 1.0)  // recovery ring full well before the timer
        for _ in 0..<25 { manager.tick(delta: 1) }
        #expect(manager.setLog[0].restRecovered == true)
    }

    @Test func unrecoveredRestExtendsToCapAndFlagsIt() async {
        var cards = sampleCards()
        cards[1] = .rest(RestCard(seconds: 60)) // longer rest: cap = 120
        let manager = makeManager()
        await manager.begin(cards: cards, routineName: "Push Day")
        manager.receiveHeartRate(150)
        advanceToRest(manager)
        manager.receiveHeartRate(145)          // pinned high — never recovers
        for _ in 0..<119 { manager.tick(delta: 1) }
        #expect(manager.activity == .rest)     // extended past the 60s seed
        manager.tick(delta: 1)                 // 120s cap
        #expect(manager.restIsReady)
        for _ in 0..<3 { manager.tick(delta: 1) }
        #expect(manager.setLog[0].restRecovered == false)
    }

    @Test func fixedRestCardIgnoresHeartRate() async {
        var cards = sampleCards()
        cards[1] = .rest(RestCard(seconds: 30, adaptive: false))
        let manager = makeManager()
        await manager.begin(cards: cards, routineName: "Push Day")
        manager.receiveHeartRate(150)
        advanceToRest(manager)
        #expect(!manager.restUsesHeartRate)    // authored control: plain timer
        manager.receiveHeartRate(100)          // huge drop — must not matter
        for _ in 0..<29 { manager.tick(delta: 1) }
        #expect(!manager.restIsReady)
        manager.tick(delta: 1)
        #expect(manager.restIsReady)           // exactly the authored 30s
    }

    @Test func skipRestRecordsNoRecoverySignal() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        manager.receiveHeartRate(150)
        advanceToRest(manager)
        manager.skipRest()
        #expect(manager.activity == .exercise)
        #expect(manager.setLog[0].restRecovered == nil) // a skip says nothing (N6)
    }

    @Test func holdAutoCompletesRecordingFullDuration() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        manager.completeSet(); manager.skipRest(); manager.completeSet() // → plank
        #expect(manager.currentItem?.isHold == true)
        manager.startHold()
        for _ in 0..<30 { manager.tick(delta: 1) }
        await waitUntilComplete(manager)       // last card → session completes
        let plankSet = manager.setLog.last
        #expect(plankSet?.completedHoldSeconds == 30)
        #expect(plankSet?.prescribedHoldSeconds == 30)
    }

    @Test func holdDoneEarlyRecordsActualSeconds() async {
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        manager.completeSet(); manager.skipRest(); manager.completeSet()
        manager.startHold()
        for _ in 0..<12 { manager.tick(delta: 1) }
        manager.completeHoldEarly()
        #expect(manager.setLog.last?.completedHoldSeconds == 12)
    }

    @Test func tickClampsAreCallerResponsibility() async {
        // tick(delta:) applies whatever it's given; the auto loop clamps at maxTickDelta.
        // A giant delta must still resolve the rest sanely (no crash, single READY).
        let manager = makeManager()
        await manager.begin(cards: sampleCards(), routineName: "Push Day")
        advanceToRest(manager)
        manager.tick(delta: 500)
        #expect(manager.restIsReady)
    }

    @Test func cleanSessionEmitsPolicyProgressionAndNotes() async {
        var fired: [ProgressionUpdate] = []
        let routineId = UUID()
        let manager = makeManager()
        manager.onProgressions = { _, updates in fired = updates }
        // Prescriptions met on every set of a squat-only block (2 sets) + full plank hold.
        let cards: [WorkoutCard] = [
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
            .rest(RestCard(seconds: 30)),
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
        ]
        await manager.begin(cards: cards, routineId: routineId, routineName: "Squats")
        manager.completeSet()
        manager.skipRest()
        manager.completeSet()
        await waitUntilComplete(manager)

        #expect(fired.count == 1)
        #expect(fired.first?.exerciseId == "goblet_squat")
        #expect(fired.first?.reps == 11) // clean double progression: +1 rep
        #expect(manager.summary?.progressionNotes.first?.contains("11 reps") == true)
        #expect(manager.summary?.setsCompleted == 2)
    }

    @Test func shortSetsEaseInsteadOfAdvance() async {
        var fired: [ProgressionUpdate] = []
        let manager = makeManager()
        manager.onProgressions = { _, updates in fired = updates }
        let cards: [WorkoutCard] = [
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
        ]
        await manager.begin(cards: cards, routineId: UUID(), routineName: "Squats")
        manager.repsPending = 7; manager.completeSet()
        manager.repsPending = 7; manager.completeSet()
        await waitUntilComplete(manager)
        #expect(fired.first?.reps == 9) // two short sets → ease one rep
    }

    @Test func manualAdjustmentBeatsPolicy() async {
        var fired: [ProgressionUpdate] = []
        let manager = makeManager()
        manager.onProgressions = { _, updates in fired = updates }
        let cards: [WorkoutCard] = [
            .exercise(StrengthExerciseItem(exerciseId: "goblet_squat", reps: 10, seedWeight: .lb(20))),
        ]
        await manager.begin(cards: cards, routineId: UUID(), routineName: "Squats")
        manager.adjustWeight(byPounds: 5) // manual raise: 20 → 25 (this IS the progression)
        manager.completeSet()             // clean set at the prescription
        await waitUntilComplete(manager)
        #expect(fired.first?.weight == .lb(25)) // the manual value, not a policy stack on top
        #expect(fired.first?.reps == nil)       // reps frozen — no +1 on a manually-raised session
    }
}
