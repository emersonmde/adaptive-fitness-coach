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
    /// The routine being worked out, when this is a real (non-demo) session — the key any recorded
    /// weight/rep progression reports against. `nil` for the scripted demo (nothing to persist).
    private(set) var routineId: UUID?
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
    /// Rep adjustments keyed by exercise id, mirroring `weightOverrides` (applies to every round).
    private var repsOverrides: [String: Int] = [:]

    /// Fired on finish with the routine's id and the progressions recorded this session (one per
    /// adjusted exercise). Empty/absent when nothing was changed or this is a demo. A closure so the
    /// manager stays free of WatchConnectivity/store (same purity discipline as the run manager).
    var onProgressions: (@MainActor (UUID, [ProgressionUpdate]) -> Void)?

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

    /// The current exercise card's prescription, with any weight/rep overrides applied.
    var currentItem: StrengthExerciseItem? {
        guard case let .exercise(item) = currentCard else { return nil }
        var adjusted = item
        if let weight = weightOverrides[item.exerciseId] { adjusted.seedWeight = weight }
        if let reps = repsOverrides[item.exerciseId] { adjusted.reps = reps }
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

    func start(cards: [WorkoutCard], routineId: UUID? = nil, routineName: String) {
        guard sessionState == .idle else { return }
        Task { await begin(cards: cards, routineId: routineId, routineName: routineName) }
    }

    /// Resolve the block, start the backend, go active. A block with no coachable exercise fails
    /// rather than starting an empty workout (N6).
    func begin(cards: [WorkoutCard], routineId: UUID? = nil, routineName: String) async {
        guard sessionState == .idle else { return }
        self.routineId = routineId
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

    /// Adjust the current exercise's proposed reps by a delta (clamped at 1 — a set is ≥ 1 rep). A
    /// no-op on hold/rest cards (no rep count). Applies to every round of the exercise (N7 seed).
    func adjustReps(by delta: Int) {
        guard sessionState == .active, case let .exercise(item) = currentCard,
              let reps = currentItem?.reps ?? item.reps else { return }
        repsOverrides[item.exerciseId] = max(1, reps + delta)
    }

    /// The progressions recorded this session — one `ProgressionUpdate` per adjusted exercise,
    /// carrying whichever of weight/reps was changed (the other stays `nil` = "no change").
    func pendingProgressions(now: Date) -> [ProgressionUpdate] {
        let ids = Set(weightOverrides.keys).union(repsOverrides.keys)
        return ids.map { id in
            ProgressionUpdate(exerciseId: id, weight: weightOverrides[id], reps: repsOverrides[id], date: now)
        }
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

    /// Complete immediately from local state; HealthKit finalizes in the background and the
    /// average HR fills in when it returns (same instant-end contract as the run manager —
    /// never freeze the UI on OS bookkeeping).
    private func end() async {
        let duration = sessionStartDate.map { now().timeIntervalSince($0) } ?? 0
        let exercisesDone = min(currentIndex, cards.count).reduceExerciseCount(in: cards)
        summary = StrengthSummary(
            totalDuration: duration,
            exercisesCompleted: exercisesDone,
            averageHeartRate: nil
        )

        // Report any weight/rep bumps against the routine so they persist as the new seed (and
        // sync back to the phone). Only for a real routine with actual changes.
        let progressions = pendingProgressions(now: now())
        if let routineId, !progressions.isEmpty {
            onProgressions?(routineId, progressions)
        }

        sessionState = .complete
        haptics.playComplete()

        let finishingBackend = backend
        backend = nil
        Task { [weak self] in
            let totals = await finishingBackend?.end() ?? WorkoutTotals()
            guard let self, self.sessionState == .complete else { return }
            if var filled = self.summary {
                filled.averageHeartRate = totals.averageHeartRate
                self.summary = filled
            }
        }
    }

    func reset() {
        isFinishing = false
        backend = nil
        cards = []
        exerciseMeta = [:]
        weightOverrides = [:]
        repsOverrides = [:]
        routineId = nil
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
