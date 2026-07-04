import Foundation

/// A user-defined training routine: a named workout that repeats on chosen days.
///
/// A routine is an ordered list of `WorkoutCard`s (run, exercise, rest), optionally repeated
/// `rounds` times — repeating the whole list is how "sets" work, so a rest card at the end falls
/// between rounds. Routines are created on the phone and synced to the watch, which walks the
/// expanded sequence and starts/stops the right Apple workout per card type. A routine is
/// forward-looking setup, never a log (N1).
public struct Routine: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var repeatDays: Set<DayOfWeek>
    public var scheduleTime: ScheduleTime?
    /// When true, the routine's schedule is mirrored to the user's Calendar as a recurring event.
    public var reminderEnabled: Bool
    /// The ordered cards. The watch walks `expandedCards` (these repeated `rounds` times).
    public var cards: [WorkoutCard]
    /// How many times the whole card list repeats — the routine-level "sets" (≥ 1).
    public var rounds: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        repeatDays: Set<DayOfWeek> = [],
        scheduleTime: ScheduleTime? = nil,
        reminderEnabled: Bool = false,
        cards: [WorkoutCard] = [],
        rounds: Int = 1,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.repeatDays = repeatDays
        self.scheduleTime = scheduleTime
        self.reminderEnabled = reminderEnabled
        self.cards = cards
        self.rounds = max(1, rounds)
        self.createdAt = createdAt
    }

    // MARK: - Derived display

    /// The card list expanded by `rounds` — the actual ordered sequence the watch performs.
    ///
    /// IDENTITY TRAP: rounds > 1 repeats the same card VALUES, so the result contains
    /// duplicate `Identifiable` ids. Consume by position (as all current call sites do) —
    /// never feed this to `ForEach` or key state by card id.
    public var expandedCards: [WorkoutCard] {
        guard rounds > 1 else { return cards }
        return (0..<rounds).flatMap { _ in cards }
    }

    /// The exercise payloads, in order (excludes run/rest cards). Used for counts and summaries.
    public var exerciseItems: [StrengthExerciseItem] { cards.compactMap(\.exercise) }

    /// The first run card, if any — drives the run launch/estimate.
    public var firstRunCard: RunCard? {
        for case let .run(c) in cards { return c }
        return nil
    }

    public var hasStrength: Bool { cards.contains { $0.exercise != nil } }
    public var hasRun: Bool { cards.contains { if case .run = $0 { return true }; return false } }

    /// A display category derived from the cards: anything with strength reads as strength
    /// (its blue identity), otherwise run. Replaces the old stored `type`.
    public var type: RoutineType { hasStrength ? .strength : .adaptiveRun }

    /// A rough total length in minutes (for the calendar event and the "~N min" display). Runs
    /// count their full duration; an exercise set is estimated at ~45s, a hold at its length; rest
    /// at its length — all times `rounds`. It's an estimate, not a contract.
    public var estimatedMinutes: Int {
        let perCard: (WorkoutCard) -> Double = { card in
            switch card {
            case let .run(c): Double(c.totalMinutes)
            case let .exercise(item): (item.holdSeconds ?? 45) / 60
            case let .rest(c): c.seconds / 60
            }
        }
        let total = cards.reduce(0) { $0 + perCard($1) } * Double(max(1, rounds))
        return max(1, Int(total.rounded()))
    }

    // MARK: - Codable (forward format = cards/rounds; legacy = type/durationMinutes/exercises)

    private enum CodingKeys: String, CodingKey {
        case id, name, repeatDays, scheduleTime, reminderEnabled, cards, rounds, createdAt
        // Legacy keys, decoded only when `cards` is absent.
        case type, durationMinutes, exercises
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        repeatDays = try c.decode(Set<DayOfWeek>.self, forKey: .repeatDays)
        scheduleTime = try c.decodeIfPresent(ScheduleTime.self, forKey: .scheduleTime)
        reminderEnabled = try c.decode(Bool.self, forKey: .reminderEnabled)
        createdAt = try c.decode(Date.self, forKey: .createdAt)

        if let cards = try c.decodeIfPresent([WorkoutCard].self, forKey: .cards) {
            self.cards = cards
            rounds = max(1, try c.decodeIfPresent(Int.self, forKey: .rounds) ?? 1)
        } else {
            // Migrate a pre-card routine: a run becomes one run card; strength becomes its
            // exercise cards. Legacy per-exercise `sets` is dropped (pre-release data only).
            let legacyType = try c.decodeIfPresent(RoutineType.self, forKey: .type) ?? .adaptiveRun
            let duration = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 30
            let legacyExercises = try c.decodeIfPresent([StrengthExerciseItem].self, forKey: .exercises) ?? []
            switch legacyType {
            case .strength where !legacyExercises.isEmpty:
                cards = legacyExercises.map(WorkoutCard.exercise)
            case .strength:
                cards = []
            case .adaptiveRun:
                cards = [.run(RunCard(durationMinutes: duration))]
            }
            rounds = 1
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(repeatDays, forKey: .repeatDays)
        try c.encodeIfPresent(scheduleTime, forKey: .scheduleTime)
        try c.encode(reminderEnabled, forKey: .reminderEnabled)
        try c.encode(cards, forKey: .cards)
        try c.encode(rounds, forKey: .rounds)
        try c.encode(createdAt, forKey: .createdAt)
    }

    // MARK: - Progression (P1: persist the latest seed; extensible to a P2 history)

    /// Return a copy with the latest-value `updates` applied to every matching `.exercise` card.
    ///
    /// A progression only moves a seed the card *already has*: a `weight` update is ignored on a
    /// bodyweight card (`seedWeight == nil`) and a `reps` update is ignored on a hold (`reps == nil`),
    /// so progression can never turn a bodyweight card into a weighted one or a hold into reps (N6).
    /// Idempotent — applying the same values again yields an equal routine. If an exercise appears in
    /// more than one card, all of its cards advance together (one move = one seed).
    public func applyingProgressions(_ updates: [ProgressionUpdate]) -> Routine {
        guard !updates.isEmpty else { return self }
        // Last-write-wins per exerciseId, should a batch somehow carry duplicates.
        let byExercise = Dictionary(updates.map { ($0.exerciseId, $0) }, uniquingKeysWith: { _, latest in latest })
        var copy = self
        copy.cards = cards.map { card in
            guard case let .exercise(item) = card, let update = byExercise[item.exerciseId] else { return card }
            var updated = item
            if let weight = update.weight, item.seedWeight != nil { updated.seedWeight = weight }
            if let reps = update.reps, item.reps != nil { updated.reps = reps }
            if let hold = update.holdSeconds, item.holdSeconds != nil { updated.holdSeconds = hold }
            return .exercise(updated)
        }
        return copy
    }

    /// Return a copy with the latest-value run-seed `updates` applied to matching `.run` cards.
    ///
    /// Values are clamped to sane bounds rather than trusted blindly, so a bad payload can never
    /// produce a degenerate plan (N6). Idempotent — applying the same values again yields an
    /// equal routine. A `cardId` with no matching card is a graceful no-op.
    public func applyingRunProgressions(_ updates: [RunProgressionUpdate]) -> Routine {
        guard !updates.isEmpty else { return self }
        let byCard = Dictionary(updates.map { ($0.cardId, $0) }, uniquingKeysWith: { _, latest in latest })
        var copy = self
        copy.cards = cards.map { card in
            guard case var .run(runCard) = card, let update = byCard[runCard.id] else { return card }
            runCard.runSeconds = min(max(update.runSeconds, 15), 3600)
            runCard.walkSeconds = min(max(update.walkSeconds, 0), 600)
            runCard.seedsCalibrated = true // evidence has spoken; never re-run cold-start calibration
            return .run(runCard)
        }
        return copy
    }
}

/// A display category for a routine, derived from its cards (green = run, blue = strength).
public enum RoutineType: String, Codable, Sendable, CaseIterable, Hashable {
    case adaptiveRun
    case strength

    public var displayName: String {
        switch self {
        case .adaptiveRun: "Adaptive Run"
        case .strength: "Strength"
        }
    }
}

/// A day of the week, numbered to match `Calendar`'s `weekday` component (Sunday = 1).
///
/// Matching Calendar's numbering lets `DateComponents.weekday` be set directly from the
/// raw value when scheduling notifications, with no conversion table.
public enum DayOfWeek: Int, Codable, Sendable, CaseIterable, Comparable, Hashable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    public static func < (lhs: DayOfWeek, rhs: DayOfWeek) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Single-letter label for compact day-picker pills (M, T, W, ...).
    public var letter: String {
        switch self {
        case .sunday: "S"
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        }
    }

    /// Three-letter uppercase label (MON, TUE, ...).
    public var shortName: String {
        switch self {
        case .sunday: "SUN"
        case .monday: "MON"
        case .tuesday: "TUE"
        case .wednesday: "WED"
        case .thursday: "THU"
        case .friday: "FRI"
        case .saturday: "SAT"
        }
    }

    public var fullName: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    /// The seven days in week order beginning at `firstWeekday` (1 = Sunday … 7 = Saturday,
    /// matching `Calendar.firstWeekday`). Parameterised so it's deterministic in tests.
    public static func orderedWeek(firstWeekday: Int) -> [DayOfWeek] {
        (0..<7).map { DayOfWeek(rawValue: (firstWeekday - 1 + $0) % 7 + 1)! }
    }

    /// Days in the user's locale order (e.g. Sunday-first in the US, like the Alarm/Calendar
    /// apps) — the order shown in the week strip and day pickers.
    public static var localeWeekOrder: [DayOfWeek] {
        orderedWeek(firstWeekday: Calendar.current.firstWeekday)
    }
}

/// A wall-clock time of day (hour + minute) for scheduling a routine.
public struct ScheduleTime: Codable, Sendable, Hashable {
    public var hour: Int   // 0–23
    public var minute: Int // 0–59

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
}
