import Foundation
import AdaptiveCore

/// Post-strength read-back (the strength analogue of `SessionSummary`). Acknowledgement, not a
/// log: the session is already a native Apple workout in Health (N1/N2).
struct StrengthSummary: Sendable, Hashable {
    var totalDuration: TimeInterval
    var exercisesCompleted: Int
    var setsCompleted: Int
    var averageHeartRate: Double?
}

/// Drives an on-watch strength session over a `StrengthWorkoutBackend`. Unlike the run manager
/// this is **user-driven, not clock-ticked**: there is no real-time adaptation in P1 (that's P2),
/// so the user advances set by set (`completeSet`) and the manager tracks position, the
/// adjustable proposed weight, and session timing. It reuses the run side's `SessionState` and
/// `WorkoutTotals`.
///
/// Testability mirrors `WorkoutSessionManager`: inject a backend and call `begin` then
/// `completeSet()`/`adjustWeight` directly — no clock, no HealthKit.
@MainActor
@Observable
final class StrengthSessionManager {
    private(set) var sessionState: SessionState = .idle
    private(set) var routineName: String = "Strength"

    /// The resolved exercise/form metadata for each card, fixed for the session.
    private(set) var exercises: [Exercise] = []
    /// Working prescriptions (weight is adjustable in place); parallel to `exercises`.
    private(set) var items: [StrengthExerciseItem] = []

    /// Index of the card on screen and the 1-based set within it.
    private(set) var currentIndex = 0
    private(set) var currentSet = 1

    private(set) var summary: StrengthSummary?

    private let injectedBackend: StrengthWorkoutBackend?
    private var backend: StrengthWorkoutBackend?
    private var startDate: Date?
    /// Time source; injectable so tests advance the clock deterministically.
    private let now: () -> Date
    private var isFinishing = false
    /// True when the session ends by completing the final set (vs. a manual early End) — lets the
    /// summary credit the whole plan rather than recomputing from the half-advanced cursor.
    private var finishedNaturally = false

    private let haptics = HapticManager()

    init(backend: StrengthWorkoutBackend? = nil, now: @escaping () -> Date = Date.init) {
        self.injectedBackend = backend
        self.now = now
    }

    // MARK: - Derived state

    /// Total sets across the whole session — the denominator for progress.
    var totalSets: Int { items.reduce(0) { $0 + max(0, $1.sets) } }

    /// Sets fully completed before the current card + sets done within it.
    var setsCompleted: Int {
        let priorSets = items.prefix(currentIndex).reduce(0) { $0 + max(0, $1.sets) }
        return priorSets + (currentSet - 1)
    }

    var currentItem: StrengthExerciseItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    var currentExercise: Exercise? {
        exercises.indices.contains(currentIndex) ? exercises[currentIndex] : nil
    }

    var setsInCurrentExercise: Int { currentItem.map { max(1, $0.sets) } ?? 0 }

    // MARK: - Start

    /// Production entry: kick off the session asynchronously.
    func start(plan: StrengthPlan, routineName: String) {
        guard sessionState == .idle else { return }
        Task { await begin(plan: plan, routineName: routineName) }
    }

    /// Set up the backend and resolved sequence and go active. Awaitable so tests can drive
    /// `completeSet()` after. A plan that resolves to no coachable exercises (every id unknown,
    /// or empty) fails rather than starting an empty workout (N6) — nothing is saved.
    func begin(plan: StrengthPlan, routineName: String) async {
        guard sessionState == .idle else { return }
        self.routineName = routineName

        let resolved = plan.resolved()
        guard !resolved.isEmpty else {
            sessionState = .failed
            return
        }
        exercises = resolved.map(\.exercise)
        items = resolved.map(\.item)
        currentIndex = 0
        currentSet = 1

        let backend = injectedBackend ?? HealthKitStrengthBackend()
        self.backend = backend
        backend.onFailure = { [weak self] in self?.handleFailure() }

        do {
            try await backend.start()
        } catch {
            // Couldn't start the workout — surface failure, save nothing (N2/N6).
            self.backend = nil
            sessionState = .failed
            return
        }

        startDate = now()
        sessionState = .active
    }

    private func handleFailure() {
        guard sessionState == .active else { return }
        backend = nil
        sessionState = .failed
    }

    // MARK: - Progression (the test seams)

    /// Adjust the current exercise's proposed weight by a delta in pounds (clamped at zero). A
    /// no-op for bodyweight or hold cards, which carry no load. Applies to every set of the
    /// exercise — it's a seed for the movement, not a per-set log (N7).
    func adjustWeight(byPounds delta: Double) {
        guard sessionState == .active, items.indices.contains(currentIndex),
              let weight = items[currentIndex].seedWeight else { return }
        items[currentIndex].seedWeight = weight.adjusted(byPounds: delta)
    }

    /// Mark the current set done and advance: next set, then next exercise, then finish. Rep and
    /// hold cards advance identically — the hold timer is the view's concern; progression is not.
    func completeSet() {
        guard sessionState == .active, let item = currentItem else { return }

        if currentSet < max(1, item.sets) {
            currentSet += 1
            haptics.playSetComplete()
            return
        }

        // Last set of this exercise → move on.
        if currentIndex < items.count - 1 {
            currentIndex += 1
            currentSet = 1
            haptics.playExerciseChange()
        } else {
            // Final set of the final exercise — the whole plan is done.
            finishedNaturally = true
            finish()
        }
    }

    // MARK: - End

    /// End the session (natural completion or user-initiated). Guarded so a tap racing the final
    /// set can't double-finalize.
    func finish() {
        guard sessionState == .active, !isFinishing else { return }
        isFinishing = true
        Task { await end() }
    }

    func endManually() { finish() }

    private func end() async {
        let totals = await backend?.end() ?? WorkoutTotals()
        let duration = startDate.map { now().timeIntervalSince($0) } ?? 0
        // A natural finish credits the whole plan; a manual early End counts only what was passed
        // (the cursor sits on the in-progress set, whose completed sets `setsCompleted` already has).
        let exercisesDone = finishedNaturally ? items.count : currentIndex
        let setsDone = finishedNaturally ? totalSets : setsCompleted
        summary = StrengthSummary(
            totalDuration: duration,
            exercisesCompleted: max(exercisesDone, 0),
            setsCompleted: setsDone,
            averageHeartRate: totals.averageHeartRate
        )
        sessionState = .complete
        haptics.playComplete()
    }

    /// Reset to idle so a new session can start (e.g. after dismissing the summary).
    func reset() {
        isFinishing = false
        finishedNaturally = false
        backend = nil
        exercises = []
        items = []
        currentIndex = 0
        currentSet = 1
        summary = nil
        startDate = nil
        sessionState = .idle
    }
}
