import Foundation
import AdaptiveCore

/// Post-strength read-back (the strength analogue of `SessionSummary`). Acknowledgement, not a
/// log: the session is already a native Apple workout in Health (N1/N2).
struct StrengthSummary: Sendable, Hashable {
    var totalDuration: TimeInterval
    var exercisesCompleted: Int
    var averageHeartRate: Double?
}

/// Drives one **strength block** — a flat run of exercise and rest cards (already expanded by the
/// routine's rounds) — over a `StrengthWorkoutBackend`. User-driven, not ticked: the user does
/// each exercise bout and taps "Done set" to advance; rest cards show a countdown the view drives.
/// Reuses the run side's `SessionState` and `WorkoutTotals`.
///
/// Testability mirrors `WorkoutSessionManager`: inject a backend, call `begin`, then drive
/// `advance()` directly — no clock, no HealthKit.
@MainActor
@Observable
final class StrengthSessionManager {
    /// What the current card is — drives which screen the view shows.
    enum Activity: Equatable { case exercise, rest }

    private(set) var sessionState: SessionState = .idle
    private(set) var routineName: String = "Strength"
    /// Latest heart rate (bpm), 0 until the first sample. Ambient, not a load signal (N3).
    private(set) var currentHeartRate: Double = 0
    private(set) var sessionStartDate: Date?
    private(set) var summary: StrengthSummary?

    /// The block's cards (exercise/rest), with unknown-id exercise cards dropped (N6).
    private(set) var cards: [WorkoutCard] = []
    private var exerciseMeta: [Int: Exercise] = [:]   // resolved library entry per exercise card
    private(set) var currentIndex = 0
    /// Weight adjustments keyed by exercise id, so a change applies to every round of that move.
    private var weightOverrides: [String: Weight] = [:]

    private let injectedBackend: StrengthWorkoutBackend?
    private var backend: StrengthWorkoutBackend?
    private let now: () -> Date
    private var isFinishing = false

    private let haptics = HapticManager()

    init(backend: StrengthWorkoutBackend? = nil, now: @escaping () -> Date = Date.init) {
        self.injectedBackend = backend
        self.now = now
    }

    // MARK: - Derived state (the view reads these)

    var currentCard: WorkoutCard? { cards.indices.contains(currentIndex) ? cards[currentIndex] : nil }

    var activity: Activity {
        if case .rest = currentCard { return .rest }
        return .exercise
    }

    var currentExercise: Exercise? { exerciseMeta[currentIndex] }

    /// The current exercise card's prescription, with any weight override applied.
    var currentItem: StrengthExerciseItem? {
        guard case let .exercise(item) = currentCard else { return nil }
        guard let override = weightOverrides[item.exerciseId] else { return item }
        var adjusted = item
        adjusted.seedWeight = override
        return adjusted
    }

    var currentRestSeconds: TimeInterval? {
        if case let .rest(c) = currentCard { return c.seconds }
        return nil
    }

    /// 1-based position among **exercise** cards, and the total — the glance's "n of N".
    var exercisePosition: (current: Int, total: Int) {
        let total = cards.reduce(0) { $0 + ($1.exercise != nil ? 1 : 0) }
        let done = cards.prefix(currentIndex).reduce(0) { $0 + ($1.exercise != nil ? 1 : 0) }
        // While on an exercise card, count it as the current one.
        let current = min(done + (activity == .exercise ? 1 : 0), total)
        return (max(1, current), max(1, total))
    }

    // MARK: - Start

    func start(cards: [WorkoutCard], routineName: String) {
        guard sessionState == .idle else { return }
        Task { await begin(cards: cards, routineName: routineName) }
    }

    /// Resolve the block, start the backend, go active. A block with no coachable exercise fails
    /// rather than starting an empty workout (N6).
    func begin(cards: [WorkoutCard], routineName: String) async {
        guard sessionState == .idle else { return }
        self.routineName = routineName

        var resolved: [WorkoutCard] = []
        var meta: [Int: Exercise] = [:]
        for card in cards {
            switch card {
            case let .exercise(item):
                guard let ex = ExerciseLibrary.exercise(id: item.exerciseId) else { continue } // drop unknown (N6)
                meta[resolved.count] = ex
                resolved.append(card)
            case .rest:
                resolved.append(card)
            case .run:
                continue // a run never appears in a strength block
            }
        }
        guard meta.values.contains(where: { _ in true }) else {
            sessionState = .failed
            return
        }
        self.cards = resolved
        self.exerciseMeta = meta
        currentIndex = 0

        let backend = injectedBackend ?? HealthKitStrengthBackend()
        self.backend = backend
        backend.onHeartRate = { [weak self] hr in self?.currentHeartRate = hr }
        backend.onFailure = { [weak self] in self?.handleFailure() }

        do {
            try await backend.start()
        } catch {
            self.backend = nil
            sessionState = .failed
            return
        }

        // Skip any leading rest cards — a block shouldn't open on a rest.
        while case .rest = currentCard { currentIndex += 1 }
        sessionStartDate = now()
        sessionState = .active
    }

    private func handleFailure() {
        guard sessionState == .active else { return }
        backend = nil
        sessionState = .failed
    }

    // MARK: - Progression (test seams)

    /// Adjust the current exercise's proposed weight by a delta in pounds (clamped at zero). A
    /// no-op on bodyweight/hold/rest cards. Applies to every round of the exercise (N7 seed).
    func adjustWeight(byPounds delta: Double) {
        guard sessionState == .active, case let .exercise(item) = currentCard,
              let weight = currentItem?.seedWeight ?? item.seedWeight else { return }
        weightOverrides[item.exerciseId] = weight.adjusted(byPounds: delta)
    }

    /// Advance to the next card. Used by "Done set" (exercise) and by the rest countdown finishing
    /// or being skipped. Plays a haptic for the kind of thing coming next.
    func advance() {
        guard sessionState == .active else { return }
        currentIndex += 1
        if currentIndex >= cards.count {
            finish()
            return
        }
        switch currentCard {
        case .rest: haptics.playSetComplete()
        default: haptics.playExerciseChange()
        }
    }

    // MARK: - End

    func finish() {
        guard sessionState == .active, !isFinishing else { return }
        isFinishing = true
        Task { await end() }
    }

    func endManually() { finish() }

    private func end() async {
        let totals = await backend?.end() ?? WorkoutTotals()
        let duration = sessionStartDate.map { now().timeIntervalSince($0) } ?? 0
        let exercisesDone = min(currentIndex, cards.count).reduceExerciseCount(in: cards)
        summary = StrengthSummary(
            totalDuration: duration,
            exercisesCompleted: exercisesDone,
            averageHeartRate: totals.averageHeartRate
        )
        sessionState = .complete
        haptics.playComplete()
    }

    func reset() {
        isFinishing = false
        backend = nil
        cards = []
        exerciseMeta = [:]
        weightOverrides = [:]
        currentIndex = 0
        currentHeartRate = 0
        summary = nil
        sessionStartDate = nil
        sessionState = .idle
    }
}

private extension Int {
    /// Count exercise cards in the first `self` cards — exercises completed at end.
    func reduceExerciseCount(in cards: [WorkoutCard]) -> Int {
        cards.prefix(self).reduce(0) { $0 + ($1.exercise != nil ? 1 : 0) }
    }
}
