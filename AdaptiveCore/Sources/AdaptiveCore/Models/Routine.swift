import Foundation

/// A user-defined training routine: a named workout that repeats on chosen days.
///
/// In P0 the only functional `type` is `.adaptiveRun`. Routines are created on the
/// phone and synced to the watch via WatchConnectivity. A routine is forward-looking
/// setup, never a log (N1).
public struct Routine: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var type: RoutineType
    public var repeatDays: Set<DayOfWeek>
    public var scheduleTime: ScheduleTime?
    /// User-chosen target session length in minutes — a *seed* the interval engine fills with
    /// run/walk cycles and then adapts (N7). Defaults to 30.
    public var durationMinutes: Int
    /// When true, the routine's schedule is mirrored to the user's Calendar as a recurring event.
    public var reminderEnabled: Bool
    /// The ordered exercise cards for a `.strength` routine. Empty for `.adaptiveRun` (whose
    /// session is generated from `durationMinutes`, not authored). The watch resolves each card's
    /// `exerciseId` against the shared `ExerciseLibrary`.
    public var exercises: [StrengthExerciseItem]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        type: RoutineType,
        repeatDays: Set<DayOfWeek> = [],
        scheduleTime: ScheduleTime? = nil,
        durationMinutes: Int = 30,
        reminderEnabled: Bool = false,
        exercises: [StrengthExerciseItem] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.repeatDays = repeatDays
        self.scheduleTime = scheduleTime
        self.durationMinutes = durationMinutes
        self.reminderEnabled = reminderEnabled
        self.exercises = exercises
        self.createdAt = createdAt
    }

    // Explicit Codable so routines persisted before a field existed still decode — each newer
    // field (`durationMinutes` from build 2, `exercises` from P1) is read with a default rather
    // than failing the whole decode.
    private enum CodingKeys: String, CodingKey {
        case id, name, type, repeatDays, scheduleTime, durationMinutes, reminderEnabled, exercises, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(RoutineType.self, forKey: .type)
        repeatDays = try c.decode(Set<DayOfWeek>.self, forKey: .repeatDays)
        scheduleTime = try c.decodeIfPresent(ScheduleTime.self, forKey: .scheduleTime)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 30
        reminderEnabled = try c.decode(Bool.self, forKey: .reminderEnabled)
        exercises = try c.decodeIfPresent([StrengthExerciseItem].self, forKey: .exercises) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

/// The kind of workout a routine drives.
///
/// P0 ships `.adaptiveRun` only. `.strength` lands in P1 and is declared here so the
/// data model and UI selectors are forward-compatible, but it is not yet runnable.
public enum RoutineType: String, Codable, Sendable, CaseIterable, Hashable {
    case adaptiveRun
    case strength

    public var displayName: String {
        switch self {
        case .adaptiveRun: "Adaptive Run"
        case .strength: "Strength"
        }
    }

    /// Whether this type is functional in the current build. Both run and strength ship in P1.
    public var isAvailable: Bool {
        switch self {
        case .adaptiveRun: true
        case .strength: true
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
