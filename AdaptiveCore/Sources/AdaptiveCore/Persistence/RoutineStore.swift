import Foundation
import Observation

/// The single source of truth for the user's routines, shared by phone and watch.
///
/// Persists `[Routine]` as JSON to a file and exposes it as observable state for SwiftUI.
/// Mutations on the phone fire `onChange` so the connectivity layer can push the latest set
/// to the watch — `RoutineStore` itself imports no WatchConnectivity, keeping it pure and
/// testable. The watch constructs a store with no `onChange` (it receives, never broadcasts).
@MainActor
@Observable
public final class RoutineStore {
    public private(set) var routines: [Routine]

    private let fileURL: URL
    private let onChange: (@MainActor ([Routine]) -> Void)?

    /// - Parameters:
    ///   - fileURL: where to persist. Defaults to `routines.json` in the documents directory.
    ///   - onChange: called after any local mutation with the new full set (phone → watch sync).
    public init(
        fileURL: URL? = nil,
        onChange: (@MainActor ([Routine]) -> Void)? = nil
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.onChange = onChange
        self.routines = Self.loadRoutines(from: self.fileURL)
    }

    public static func defaultFileURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("routines.json")
    }

    private static func loadRoutines(from url: URL) -> [Routine] {
        // No file yet is the normal first-launch case → start empty.
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        if let data = try? Data(contentsOf: url),
           let routines = try? JSONDecoder().decode([Routine].self, from: data) {
            return routines
        }

        // The file exists but couldn't be read/decoded. Preserve it as a `.corrupt` sidecar
        // before we ever risk overwriting it with an empty set, then start empty rather than
        // silently and permanently destroying the user's routines.
        let backup = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.copyItem(at: url, to: backup)
        return []
    }

    /// Persist to disk and notify the sync hook. Called after every mutation.
    private func save(broadcast: Bool) {
        if let data = try? JSONEncoder().encode(routines) {
            try? data.write(to: fileURL, options: [.atomic])
        }
        if broadcast { onChange?(routines) }
    }

    // MARK: - Mutations (local, broadcast to watch)

    public func add(_ routine: Routine) {
        routines.append(routine)
        save(broadcast: true)
    }

    /// Upsert: replaces the routine with the same id, or inserts it if not present.
    public func update(_ routine: Routine) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else {
            add(routine)
            return
        }
        routines[index] = routine
        save(broadcast: true)
    }

    public func remove(id: Routine.ID) {
        routines.removeAll { $0.id == id }
        save(broadcast: true)
    }

    // MARK: - Sync (incoming from the other device, persisted but not re-broadcast)

    /// Replace the whole set from a received sync. Persists without firing `onChange`, so a
    /// received update never echoes back to the sender.
    public func replaceFromSync(_ incoming: [Routine]) {
        routines = incoming
        save(broadcast: false)
    }

    // MARK: - Queries

    /// Routines that repeat on `day`, ordered by their scheduled time then name.
    public func routines(on day: DayOfWeek) -> [Routine] {
        routines
            .filter { $0.repeatDays.contains(day) }
            .sorted { lhs, rhs in
                let l = lhs.scheduleTime.map { $0.hour * 60 + $0.minute } ?? Int.max
                let r = rhs.scheduleTime.map { $0.hour * 60 + $0.minute } ?? Int.max
                return l == r ? lhs.name < rhs.name : l < r
            }
    }

    /// The next routine to run on or after a given weekday/time, scanning the week forward.
    /// Used by the watch launch screen to show "up next". Returns nil if no routines exist.
    public func nextRoutine(fromWeekday weekday: DayOfWeek, hour: Int, minute: Int) -> Routine? {
        guard !routines.isEmpty else { return nil }
        let nowMinutes = hour * 60 + minute
        // Search today (only occurrences at/after now) then each following day, wrapping the week.
        for offset in 0..<7 {
            let day = DayOfWeek(rawValue: (weekday.rawValue - 1 + offset) % 7 + 1)!
            let candidates = routines(on: day).filter { routine in
                guard offset == 0, let t = routine.scheduleTime else { return true }
                return (t.hour * 60 + t.minute) >= nowMinutes
            }
            if let first = candidates.first { return first }
        }
        // Nothing remains this week — the only occurrences are earlier today. Wrap to the
        // earliest routine today, i.e. its next occurrence is the same weekday next week.
        return routines(on: weekday).first
    }

    /// The next scheduled occurrence across all routines: the routine and the exact `Date` it
    /// next fires (its repeat-day at its scheduled time, or midnight if no time is set). Drives
    /// the phone's "Up Next" hero ("Tomorrow · 7:00 AM"). Returns nil if nothing is scheduled.
    public func nextOccurrence(now: Date = Date(), calendar: Calendar = .current) -> (routine: Routine, date: Date)? {
        var best: (routine: Routine, date: Date)?
        for routine in routines where !routine.repeatDays.isEmpty {
            for day in routine.repeatDays {
                var components = DateComponents()
                components.weekday = day.rawValue
                if let time = routine.scheduleTime {
                    components.hour = time.hour
                    components.minute = time.minute
                } else {
                    components.hour = 0
                    components.minute = 0
                }
                guard let date = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) else { continue }
                if best == nil || date < best!.date {
                    best = (routine, date)
                }
            }
        }
        return best
    }
}
