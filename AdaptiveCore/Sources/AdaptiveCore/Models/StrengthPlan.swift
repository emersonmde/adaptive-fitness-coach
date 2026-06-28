import Foundation

/// One card in an authored strength routine: a reference to a library `Exercise` plus the
/// prescription the user will perform. The prescription is seeded from the library entry's
/// defaults (`init(from:)`) and may be adjusted in the phone builder; it is never a log of what
/// happened (N1) — only what to attempt next.
public struct StrengthExerciseItem: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// References `ExerciseLibrary` by `Exercise.id`.
    public var exerciseId: String
    public var sets: Int
    /// Target reps for rep-based work; `nil` for an isometric hold.
    public var reps: Int?
    /// Seed load; `nil` for bodyweight or hold work.
    public var seedWeight: Weight?
    /// Hold duration for isometric work; `nil` for rep-based work.
    public var holdSeconds: TimeInterval?

    public init(
        id: UUID = UUID(),
        exerciseId: String,
        sets: Int,
        reps: Int? = nil,
        seedWeight: Weight? = nil,
        holdSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.sets = sets
        self.reps = reps
        self.seedWeight = seedWeight
        self.holdSeconds = holdSeconds
    }

    /// Build a card seeded from a library entry's conservative defaults.
    public init(id: UUID = UUID(), from exercise: Exercise) {
        self.id = id
        self.exerciseId = exercise.id
        self.sets = exercise.defaultSets
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

/// An ordered sequence of strength cards — the watch walks through these in order. Built on the
/// phone from a `Routine.exercises` list and handed to the watch's strength session.
public struct StrengthPlan: Codable, Sendable, Hashable {
    public var items: [StrengthExerciseItem]

    public init(items: [StrengthExerciseItem]) {
        self.items = items
    }

    /// Total number of sets across the whole session — the denominator for the progress readout.
    public var totalSets: Int {
        items.reduce(0) { $0 + max(0, $1.sets) }
    }
}

/// A strength card paired with its resolved library `Exercise` (name, form demo, archetype).
public struct ResolvedStrengthItem: Sendable, Hashable, Identifiable {
    public var item: StrengthExerciseItem
    public var exercise: Exercise
    public var id: UUID { item.id }

    public init(item: StrengthExerciseItem, exercise: Exercise) {
        self.item = item
        self.exercise = exercise
    }
}

public extension StrengthPlan {
    /// Resolve each card against the shared library, **dropping** any card whose `exerciseId`
    /// is unknown rather than fabricating a placeholder or crashing (N6 — never present a
    /// movement the app can't actually coach). With a matched library on both sides this is a
    /// no-op; it only bites if a routine outlives a library entry.
    func resolved(using library: [Exercise] = ExerciseLibrary.all) -> [ResolvedStrengthItem] {
        let byID = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        return items.compactMap { item in
            byID[item.exerciseId].map { ResolvedStrengthItem(item: item, exercise: $0) }
        }
    }
}
