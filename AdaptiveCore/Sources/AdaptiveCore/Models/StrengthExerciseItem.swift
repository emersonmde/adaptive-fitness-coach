import Foundation

/// One exercise card in a routine: a reference to a library `Exercise` plus the prescription for
/// a single bout — the reps and seed load, or a hold duration. Repetition (sets) comes from the
/// routine repeating as a whole (`Routine.rounds`), not from a per-card count, so there is no
/// `sets` field here. The prescription is seeded from the library entry's defaults (`init(from:)`)
/// and may be adjusted; it is never a log of what happened (N1) — only what to attempt next.
public struct StrengthExerciseItem: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// References `ExerciseLibrary` by `Exercise.id`.
    public var exerciseId: String
    /// Target reps for rep-based work; `nil` for an isometric hold.
    public var reps: Int?
    /// Seed load; `nil` for bodyweight or hold work.
    public var seedWeight: Weight?
    /// Hold duration for isometric work; `nil` for rep-based work.
    public var holdSeconds: TimeInterval?

    public init(
        id: UUID = UUID(),
        exerciseId: String,
        reps: Int? = nil,
        seedWeight: Weight? = nil,
        holdSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.reps = reps
        self.seedWeight = seedWeight
        self.holdSeconds = holdSeconds
    }

    /// Build a card seeded from a library entry's conservative defaults.
    public init(id: UUID = UUID(), from exercise: Exercise) {
        self.id = id
        self.exerciseId = exercise.id
        switch exercise.kind {
        case let .reps(defaultReps, seedWeight):
            self.reps = defaultReps
            self.seedWeight = seedWeight
            self.holdSeconds = nil
        case let .hold(defaultSeconds):
            self.reps = nil
            self.seedWeight = nil
            self.holdSeconds = defaultSeconds
        }
    }

    /// True when this card is an isometric hold (timer card) rather than reps.
    public var isHold: Bool { holdSeconds != nil }
}

/// An exercise card paired with its resolved library `Exercise` (name, form demo, archetype).
public struct ResolvedStrengthItem: Sendable, Hashable, Identifiable {
    public var item: StrengthExerciseItem
    public var exercise: Exercise
    public var id: UUID { item.id }

    public init(item: StrengthExerciseItem, exercise: Exercise) {
        self.item = item
        self.exercise = exercise
    }
}

public extension StrengthExerciseItem {
    /// Resolve this card against the shared library, or `nil` if the id is unknown — the caller
    /// drops unknowns rather than fabricating a movement the app can't coach (N6).
    func resolved(using library: [Exercise] = ExerciseLibrary.all) -> ResolvedStrengthItem? {
        library.first { $0.id == exerciseId }.map { ResolvedStrengthItem(item: self, exercise: $0) }
    }
}
