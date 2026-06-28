import Foundation

/// A routine is an ordered list of `WorkoutCard`s, optionally repeated `Routine.rounds` times.
/// Cards are heterogeneous on purpose — a routine might be a single run, or a series of strength
/// moves with rests between them. The watch walks the expanded sequence and starts/stops the
/// right Apple workout per card type (a run card → a running session; strength/rest cards → a
/// strength session), so the user never manages that.
///
/// Holds (e.g. a plank) are not a separate case: they're an `.exercise` card whose library entry
/// is isometric (`ExerciseKind.hold`).
public enum WorkoutCard: Codable, Sendable, Hashable, Identifiable {
    case run(RunCard)
    case exercise(StrengthExerciseItem)
    case rest(RestCard)

    public var id: UUID {
        switch self {
        case let .run(c): c.id
        case let .exercise(c): c.id
        case let .rest(c): c.id
        }
    }

    /// The exercise payload, when this is an exercise card.
    public var exercise: StrengthExerciseItem? {
        if case let .exercise(item) = self { return item }
        return nil
    }

    /// The kind of Apple workout this card belongs to, used to group consecutive cards into one
    /// `HKWorkoutSession`. Rest belongs to whatever workout surrounds it, so it reports `nil`
    /// (it never forces a session switch on its own).
    public var workoutKind: WorkoutKind? {
        switch self {
        case .run: .run
        case .exercise: .strength
        case .rest: nil
        }
    }
}

/// The Apple-workout family a card needs. A run card needs a running session (for native HR
/// zones); exercise cards need a Traditional Strength Training session.
public enum WorkoutKind: String, Codable, Sendable, Hashable {
    case run
    case strength
}

/// A run card: an adaptive run/walk block of a chosen length. The interval engine generates and
/// adapts the plan from `durationMinutes` — the existing run flow handles the card.
public struct RunCard: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// Target length in minutes — a seed the interval engine fills with run/walk cycles and then
    /// adapts to heart rate (N7).
    public var durationMinutes: Int

    public init(id: UUID = UUID(), durationMinutes: Int = 30) {
        self.id = id
        self.durationMinutes = durationMinutes
    }
}

/// A rest card: a fixed pause. Placed between exercises it's a transition; placed at the end of a
/// routine it falls between rounds — i.e. it becomes rest between sets when the routine repeats.
public struct RestCard: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// Rest length in seconds. Seeded to a sensible value when added; adjustable.
    public var seconds: TimeInterval

    public init(id: UUID = UUID(), seconds: TimeInterval = 60) {
        self.id = id
        self.seconds = seconds
    }
}
