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

/// A run card: an adaptive run/walk session. The user configures the shape (warmup / run
/// block / cooldown, in minutes); the engine fills the run block with run/walk cycles from
/// the card's *seeds* (`runSeconds`/`walkSeconds`) and adapts them live to heart rate (N7).
///
/// The seeds are the cross-session memory: after each completed session the watch reports a
/// `RunProgressionUpdate` and the phone rewrites them (longer runs / shorter walks after a
/// clean session, the reverse after a struggle), so the plan scales automatically toward
/// continuous running. Latest-value-only, like strength progression (P1).
public struct RunCard: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// Run-block length in minutes — the adaptive middle between warmup and cooldown.
    /// (Pre-P1.5 payloads used this as the *total* session length; decoded values keep their
    /// number and gain the default warmup/cooldown around it — accepted drift.)
    public var durationMinutes: Int
    /// Warmup walk length in minutes. 0 omits the warmup.
    public var warmupMinutes: Int
    /// Cooldown walk length in minutes. 0 omits the cooldown.
    public var cooldownMinutes: Int
    /// Seed run-interval length in seconds. Progression rewrites this across sessions.
    public var runSeconds: Int
    /// Seed walk-interval length in seconds. Progression rewrites this across sessions.
    public var walkSeconds: Int
    /// Whether the seeds have ever been set from evidence (Health-history calibration or a
    /// recorded session outcome). While false and the seeds are still factory defaults, the
    /// watch runs a one-time silent calibration at first session start — the zero-config
    /// cold start. Set by `applyingRunProgressions`.
    public var seedsCalibrated: Bool

    public init(
        id: UUID = UUID(),
        durationMinutes: Int = 20,
        warmupMinutes: Int = 5,
        cooldownMinutes: Int = 5,
        runSeconds: Int = 90,
        walkSeconds: Int = 120,
        seedsCalibrated: Bool = false
    ) {
        self.id = id
        self.durationMinutes = durationMinutes
        self.warmupMinutes = warmupMinutes
        self.cooldownMinutes = cooldownMinutes
        self.runSeconds = runSeconds
        self.walkSeconds = walkSeconds
        self.seedsCalibrated = seedsCalibrated
    }

    /// True while the seeds are the untouched factory defaults with no evidence behind them.
    public var needsCalibration: Bool {
        !seedsCalibrated && runSeconds == 90 && walkSeconds == 120
    }

    /// Total planned session length in minutes (warmup + run block + cooldown).
    public var totalMinutes: Int { warmupMinutes + durationMinutes + cooldownMinutes }

    private enum CodingKeys: String, CodingKey {
        case id, durationMinutes, warmupMinutes, cooldownMinutes, runSeconds, walkSeconds, seedsCalibrated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        // Older payloads predate these fields — default rather than fail (routines.json on
        // both devices must keep decoding across the upgrade).
        warmupMinutes = try container.decodeIfPresent(Int.self, forKey: .warmupMinutes) ?? 5
        cooldownMinutes = try container.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 5
        runSeconds = try container.decodeIfPresent(Int.self, forKey: .runSeconds) ?? 90
        walkSeconds = try container.decodeIfPresent(Int.self, forKey: .walkSeconds) ?? 120
        seedsCalibrated = try container.decodeIfPresent(Bool.self, forKey: .seedsCalibrated) ?? false
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
