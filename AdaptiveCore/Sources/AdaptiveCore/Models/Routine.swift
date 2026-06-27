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
    public var reminderEnabled: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        type: RoutineType,
        repeatDays: Set<DayOfWeek> = [],
        scheduleTime: ScheduleTime? = nil,
        reminderEnabled: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.repeatDays = repeatDays
        self.scheduleTime = scheduleTime
        self.reminderEnabled = reminderEnabled
        self.createdAt = createdAt
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

    /// Whether this type is functional in the current build. Only adaptive runs run in P0.
    public var isAvailable: Bool {
        switch self {
        case .adaptiveRun: true
        case .strength: false
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

    /// Days in week order starting Monday — the order shown in day pickers.
    public static var weekOrder: [DayOfWeek] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
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
