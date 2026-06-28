import Foundation
import Testing
import AdaptiveCore
@testable import Adaptive_Fitness_Coach_Watch_App

/// Integration tests for the on-watch strength flow. They drive `StrengthSessionManager` with a
/// `SimulatedStrengthBackend` and advance set by set — the user-driven analogue of the run
/// flow's tick loop — so progression, weight adjust, the hold path, and failure are covered
/// without HealthKit or a clock.
@MainActor
private final class FailingStrengthBackend: StrengthWorkoutBackend {
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
        StrengthSessionManager(backend: SimulatedStrengthBackend())
    }

    /// Two rep exercises (2 sets each) + a plank (1 hold set) — 5 sets, 3 exercises.
    private func samplePlan() -> StrengthPlan {
        StrengthPlan(items: [
            StrengthExerciseItem(exerciseId: "goblet_squat", sets: 2, reps: 10, seedWeight: .lb(20)),
            StrengthExerciseItem(exerciseId: "db_bench_press", sets: 2, reps: 10, seedWeight: .lb(15)),
            StrengthExerciseItem(exerciseId: "plank", sets: 1, holdSeconds: 30),
        ])
    }

    private func waitUntilComplete(_ manager: StrengthSessionManager) async {
        for _ in 0..<200 {
            if manager.sessionState == .complete { return }
            await Task.yield()
        }
    }

    // MARK: - Lifecycle

    @Test func beginActivatesAtFirstCard() async {
        let manager = makeManager()
        await manager.begin(plan: samplePlan(), routineName: "Push Day")
        #expect(manager.sessionState == .active)
        #expect(manager.currentIndex == 0)
        #expect(manager.currentSet == 1)
        #expect(manager.currentExercise?.id == "goblet_squat")
        #expect(manager.totalSets == 5)
    }

    @Test func emptyPlanFailsWithoutStartingAWorkout() async {
        let manager = makeManager()
        await manager.begin(plan: StrengthPlan(items: []), routineName: "Empty")
        #expect(manager.sessionState == .failed)
        #expect(manager.summary == nil)
    }

    @Test func planOfOnlyUnknownIdsFails() async {
        let manager = makeManager()
        let plan = StrengthPlan(items: [StrengthExerciseItem(exerciseId: "ghost", sets: 3, reps: 5)])
        await manager.begin(plan: plan, routineName: "Ghosts")
        #expect(manager.sessionState == .failed)
    }

    // MARK: - Progression

    @Test func completeSetAdvancesThroughSetsAndExercises() async {
        let manager = makeManager()
        await manager.begin(plan: samplePlan(), routineName: "Push Day")

        // Exercise 1: set 1 → set 2.
        manager.completeSet()
        #expect(manager.currentIndex == 0)
        #expect(manager.currentSet == 2)

        // Set 2 was the last → advance to exercise 2, set 1.
        manager.completeSet()
        #expect(manager.currentIndex == 1)
        #expect(manager.currentSet == 1)
        #expect(manager.currentExercise?.id == "db_bench_press")
    }

    @Test func setsCompletedTracksProgress() async {
        let manager = makeManager()
        await manager.begin(plan: samplePlan(), routineName: "Push Day")
        #expect(manager.setsCompleted == 0)
        manager.completeSet()                 // 1 set done
        #expect(manager.setsCompleted == 1)
        manager.completeSet()                 // 2 sets done, now on exercise 2
        #expect(manager.setsCompleted == 2)
    }

    @Test func finishesAfterLastSetOfLastExercise() async {
        let manager = makeManager()
        await manager.begin(plan: samplePlan(), routineName: "Push Day")
        // 5 sets total → 5 completes finishes the session.
        for _ in 0..<5 { manager.completeSet() }
        await waitUntilComplete(manager)
        #expect(manager.sessionState == .complete)
        #expect(manager.summary?.exercisesCompleted == 3)
        #expect(manager.summary?.setsCompleted == 5)
        #expect(manager.summary?.averageHeartRate == 121) // from the simulated backend
    }

    // MARK: - Weight adjust (N7 seed, clamped)

    @Test func adjustWeightChangesCurrentExerciseLoad() async {
        let manager = makeManager()
        await manager.begin(plan: samplePlan(), routineName: "Push Day")
        manager.adjustWeight(byPounds: 5)
        #expect(manager.currentItem?.seedWeight == .lb(25))
        manager.adjustWeight(byPounds: -10)
        #expect(manager.currentItem?.seedWeight == .lb(15))
    }

    @Test func adjustWeightClampsAtZero() async {
        let manager = makeManager()
        await manager.begin(plan: samplePlan(), routineName: "Push Day")
        manager.adjustWeight(byPounds: -1000)
        #expect(manager.currentItem?.seedWeight == .lb(0))
    }

    @Test func adjustWeightIsNoOpForHoldCard() async {
        let manager = makeManager()
        await manager.begin(plan: samplePlan(), routineName: "Push Day")
        // Advance to the plank (last exercise): 4 completes lands on exercise index 2.
        for _ in 0..<4 { manager.completeSet() }
        #expect(manager.currentExercise?.id == "plank")
        #expect(manager.currentItem?.isHold == true)
        manager.adjustWeight(byPounds: 5) // no load to adjust
        #expect(manager.currentItem?.seedWeight == nil)
    }

    // MARK: - Hold path

    @Test func holdCardCompletesLikeARepSet() async {
        let manager = makeManager()
        let plan = StrengthPlan(items: [StrengthExerciseItem(exerciseId: "plank", sets: 2, holdSeconds: 30)])
        await manager.begin(plan: plan, routineName: "Core")
        #expect(manager.currentItem?.isHold == true)
        manager.completeSet()
        #expect(manager.currentSet == 2)
        manager.completeSet()
        await waitUntilComplete(manager)
        #expect(manager.sessionState == .complete)
    }

    // MARK: - Failure & manual end

    @Test func startFailureSurfacesFailedWithoutFakingCompletion() async {
        let manager = StrengthSessionManager(backend: FailingStrengthBackend())
        await manager.begin(plan: samplePlan(), routineName: "Push Day")
        #expect(manager.sessionState == .failed)
        #expect(manager.summary == nil)
    }

    @Test func runtimeFailureStopsTheSession() async {
        let backend = FailingStrengthBackend(failOnStart: false)
        let manager = StrengthSessionManager(backend: backend)
        await manager.begin(plan: samplePlan(), routineName: "Push Day")
        #expect(manager.sessionState == .active)
        backend.onFailure?()
        #expect(manager.sessionState == .failed)
    }

    @Test func endManuallyCompletesAndBuildsSummary() async {
        let manager = makeManager()
        await manager.begin(plan: samplePlan(), routineName: "Push Day")
        manager.endManually()
        await waitUntilComplete(manager)
        #expect(manager.sessionState == .complete)
        #expect(manager.summary != nil)
    }

    // MARK: - Reset

    @Test func resetReturnsToIdle() async {
        let manager = makeManager()
        await manager.begin(plan: samplePlan(), routineName: "Push Day")
        for _ in 0..<5 { manager.completeSet() }
        await waitUntilComplete(manager)
        manager.reset()
        #expect(manager.sessionState == .idle)
        #expect(manager.summary == nil)
        #expect(manager.items.isEmpty)
    }
}
