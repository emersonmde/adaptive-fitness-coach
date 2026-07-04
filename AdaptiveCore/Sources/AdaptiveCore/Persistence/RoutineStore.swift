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

    /// The App Group that shares the routines file between the app and its extensions
    /// (widgets, complications — build 9). Widgets/complications read `nextOccurrence()` from
    /// the same store, so the file must live in a container both processes can reach.
    public nonisolated static let appGroupIdentifier = "group.com.memerson.Adaptive-Fitness-Coach"

    /// The default routines file: the App Group container when available (so extensions see
    /// it), else the app's Documents directory (defensive fallback — e.g. entitlement missing
    /// in a test host). A one-time migration copies a pre-build-9 Documents file into the group.
    public nonisolated static func defaultFileURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let documentsFile = documents.appendingPathComponent("routines.json")

        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return documentsFile   // no App Group (fallback) — behave exactly as before
        }
        let groupFile = container.appendingPathComponent("routines.json")
        migrateIfNeeded(from: documentsFile, to: groupFile)
        return groupFile
    }

    /// One-time copy of a pre-build-9 Documents routines file into the App Group container.
    /// Idempotent: never overwrites an existing group file (that would clobber newer data).
    nonisolated static func migrateIfNeeded(from source: URL, to destination: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path),
              fm.fileExists(atPath: source.path) else { return }
        try? fm.copyItem(at: source, to: destination)
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
    /// A write failure keeps the in-memory copy authoritative and is logged rather than
    /// swallowed — silent persistence loss is the worst kind.
    private func save(broadcast: Bool) {
        do {
            let data = try JSONEncoder().encode(routines)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("RoutineStore: failed to persist routines: %@", String(describing: error))
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

    // MARK: - Progression (apply a recorded weight/rep bump to a routine's seeds)

    /// Apply progressions to the routine with `id` and persist. Returns `true` if anything changed.
    ///
    /// - `broadcast`: the phone passes `true` so its corrected routine re-syncs to the watch; the
    ///   watch passes `false` (it never broadcasts). The apply is idempotent latest-value, and a
    ///   no-op change short-circuits without writing — together these keep a watch→phone→watch round
    ///   trip from oscillating (it reaches a fixed point in one pass).
    /// - A missing routine (deleted/never present) is a graceful no-op returning `false` (N6).
    @discardableResult
    public func applyProgressions(_ updates: [ProgressionUpdate], toRoutineId id: Routine.ID, broadcast: Bool) -> Bool {
        applyProgressions(ProgressionBatch(routineId: id, updates: updates), broadcast: broadcast)
    }

    /// Apply a full progression batch (strength + run seeds) in one pass. Same fixed-point
    /// contract as above: idempotent apply + no-op short-circuit, so a round trip converges.
    @discardableResult
    public func applyProgressions(_ batch: ProgressionBatch, broadcast: Bool) -> Bool {
        guard let index = routines.firstIndex(where: { $0.id == batch.routineId }) else { return false }
        let updated = routines[index]
            .applyingProgressions(batch.updates)
            .applyingRunProgressions(batch.runUpdates)
        guard updated != routines[index] else { return false } // already converged → no write, no echo
        routines[index] = updated
        save(broadcast: broadcast)
        return true
    }

    // MARK: - Import (e.g. routines revised in Claude and brought back via RoutineExchange)

    /// Merge imported routines by **name**: a routine whose name matches an existing one replaces
    /// that one's contents (keeping its id, so schedules/calendar links survive); a new name is
    /// added. Broadcasts so the watch picks up the changes. Returns (updated, added) counts.
    ///
    /// **Run progression survives the round trip.** The exchange schema deliberately omits run
    /// seeds (they're the user's demonstrated fitness, not routine design), so imported run
    /// cards arrive factory-fresh with new ids. The merge grafts each existing run card's
    /// identity and progression state (`id`, `runSeconds`, `walkSeconds`, `seedsCalibrated`)
    /// onto the imported card in the same ordinal position — otherwise every Claude round-trip
    /// would silently wipe earned progression and orphan in-flight watch updates keyed by
    /// `cardId`. Imported *shape* (durations) still wins; only earned state carries over.
    @discardableResult
    public func importRoutines(_ incoming: [Routine]) -> (updated: Int, added: Int) {
        var updated = 0, added = 0
        // Names match folded (trimmed, case-insensitive): the exchange contract tells the
        // model "the app matches routines by name", and an LLM's "morning run" for
        // "Morning Run" must merge — a miss adds a duplicate and silently skips the
        // progression graft. The existing routine keeps its own casing.
        func folded(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        // De-duplicate incoming by name (last wins) so two same-named payload entries can't
        // both merge into one existing routine and inflate the counts.
        var seenNames = Set<String>()
        let deduped = incoming.reversed().filter { seenNames.insert(folded($0.name)).inserted }.reversed()

        for routine in deduped {
            if let index = routines.firstIndex(where: { folded($0.name) == folded(routine.name) }) {
                let existing = routines[index]
                // Preserve identity + scheduling; take the imported cards/rounds (and days/time if set).
                var merged = existing
                merged.cards = Self.graftingRunProgression(from: existing.cards, onto: routine.cards)
                merged.rounds = routine.rounds
                if !routine.repeatDays.isEmpty { merged.repeatDays = routine.repeatDays }
                if routine.scheduleTime != nil { merged.scheduleTime = routine.scheduleTime }
                routines[index] = merged
                updated += 1
            } else {
                routines.append(routine)
                added += 1
            }
        }
        if updated + added > 0 { save(broadcast: true) }
        return (updated, added)
    }

    /// Carry run-card identity + earned progression from `existing` onto `imported`, matching
    /// run cards by ordinal position among the run cards (routines rarely have more than one).
    private static func graftingRunProgression(from existing: [WorkoutCard], onto imported: [WorkoutCard]) -> [WorkoutCard] {
        let existingRunCards = existing.compactMap { card -> RunCard? in
            if case let .run(c) = card { return c }
            return nil
        }
        guard !existingRunCards.isEmpty else { return imported }

        var runOrdinal = 0
        return imported.map { card in
            guard case let .run(importedCard) = card else { return card }
            defer { runOrdinal += 1 }
            guard runOrdinal < existingRunCards.count else { return card }
            let donor = existingRunCards[runOrdinal]
            return .run(RunCard(
                id: donor.id,
                durationMinutes: importedCard.durationMinutes,
                warmupMinutes: importedCard.warmupMinutes,
                cooldownMinutes: importedCard.cooldownMinutes,
                runSeconds: donor.runSeconds,
                walkSeconds: donor.walkSeconds,
                seedsCalibrated: donor.seedsCalibrated
            ))
        }
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
        Self.nextOccurrence(in: routines, now: now, calendar: calendar)
    }

    // MARK: - Nonisolated reads for extensions (widgets / complications, build 9)

    /// Decode the routines file without the `@MainActor` store — for a widget/complication
    /// timeline provider running off the main actor. Defaults to the App Group file.
    public nonisolated static func routinesFromDisk(fileURL: URL? = nil) -> [Routine] {
        let url = fileURL ?? defaultFileURL()
        guard let data = try? Data(contentsOf: url),
              let routines = try? JSONDecoder().decode([Routine].self, from: data) else { return [] }
        return routines
    }

    /// The next scheduled occurrence across a routine set — pure, nonisolated (the instance
    /// method delegates here, and extensions call it directly on `routinesFromDisk()`).
    public nonisolated static func nextOccurrence(
        in routines: [Routine], now: Date = Date(), calendar: Calendar = .current
    ) -> (routine: Routine, date: Date)? {
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
