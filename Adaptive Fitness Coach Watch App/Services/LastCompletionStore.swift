import Foundation
import AdaptiveCore

/// Watch-local "done today" marker (W22): when a session completes, the routine's id and
/// completion date land here so the launch screens can show "Done today ✓ · Next: Thu" and
/// demote Start to "Start again" — a finished loop must read as finished, not reset.
///
/// Deliberately tiny and local: one UserDefaults dictionary keyed by routine id, latest
/// completion only. This is a UI receipt, not a training log — Health owns the real record
/// (N2) — so nothing here syncs or persists beyond what the label needs. The state applies
/// for the rest of the calendar day; Start stays fully functional (the user may genuinely
/// go again — N4).
struct LastCompletionStore {
    static let shared = LastCompletionStore()

    private static let key = "lastCompletionByRoutine"

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    /// Record that `routineId` finished a session just now. Latest-wins per routine.
    func recordCompletion(routineId: UUID) {
        var completions = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
        completions[routineId.uuidString] = now().timeIntervalSince1970
        defaults.set(completions, forKey: Self.key)
    }

    /// Whether `routineId` completed a session earlier today (same calendar day).
    func completedToday(routineId: UUID, calendar: Calendar = .current) -> Bool {
        guard let completions = defaults.dictionary(forKey: Self.key) as? [String: Double],
              let stamp = completions[routineId.uuidString] else { return false }
        return calendar.isDate(Date(timeIntervalSince1970: stamp), inSameDayAs: now())
    }

    /// The short label for the routine's next repeat day strictly AFTER today ("Tomorrow",
    /// "Thu", or "next Tue" when the only occurrence is the same weekday next week). nil when
    /// the routine has no repeat days — no fabricated schedule (N6).
    static func nextDayLabel(repeatDays: Set<DayOfWeek>, after date: Date = Date(),
                             calendar: Calendar = .current) -> String? {
        guard !repeatDays.isEmpty else { return nil }
        let todayRaw = calendar.component(.weekday, from: date)
        for offset in 1...7 {
            let raw = (todayRaw - 1 + offset) % 7 + 1
            guard let day = DayOfWeek(rawValue: raw), repeatDays.contains(day) else { continue }
            if offset == 1 { return "Tomorrow" }
            let name = day.shortName.capitalized // "THU" → "Thu"
            return offset == 7 ? "next \(name)" : name
        }
        return nil
    }
}
