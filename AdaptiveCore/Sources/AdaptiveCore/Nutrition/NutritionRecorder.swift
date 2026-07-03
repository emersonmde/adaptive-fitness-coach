import Foundation

/// The Health seam (C5): Apple Health is the system of record for meals — the app is the pen,
/// Health is the paper. Protocol here, `HealthKitNutritionRecorder` phone-side,
/// `InMemoryNutritionRecorder` for the simulator and tests (the `WorkoutBackend` pattern).
public struct DailyIntake: Sendable, Equatable {
    public var totalKcal: Double
    /// Entries reconstructed from Health samples + metadata (only ours carry full metadata;
    /// the total also counts energy written by other apps).
    public var entries: [MealEntry]

    public init(totalKcal: Double = 0, entries: [MealEntry] = []) {
        self.totalKcal = totalKcal
        self.entries = entries
    }
}

public protocol NutritionRecorder: Sendable {
    /// Requests dietary share+read authorization. Deferred-contextual: called at the first
    /// Log, not app launch. Throwing means the *request* failed; a denial is not a throw —
    /// HealthKit reports denial through the write path.
    func requestAuthorization() async throws
    /// Writes one entry (energy + macros, provenance/meal in metadata). Returning without
    /// throwing means Health confirmed the save — only then may the UI say "Saved" (N6).
    func record(_ entry: MealEntry) async throws
    /// Deletes an entry previously written by us (day-screen swipe / edit sheet).
    func delete(entryID: UUID) async throws
    /// One day's intake, the day interpreted in the current calendar's timezone (build 8 —
    /// the Food screen's pager).
    func intake(on day: Date) async throws -> DailyIntake
    /// Total active energy burned that day (all sources), kcal. Informational only — the
    /// budget is fixed by decision; burn never expands it.
    func activeEnergyBurned(on day: Date) async throws -> Double
    /// Fires whenever dietary energy changes in Health (any source) — refresh the daily line.
    func observeChanges(_ handler: @escaping @Sendable () -> Void)
}

public extension NutritionRecorder {
    /// Convenience kept for existing call sites.
    func todayIntake() async throws -> DailyIntake {
        try await intake(on: Date())
    }

    /// Edit = delete + rewrite (Health samples are immutable). Delete-first (recording the
    /// edited entry before deleting would make delete-by-id ambiguous — same AFCEntryID
    /// twice); on rewrite failure, best-effort restore of the original, then rethrow so the
    /// UI can be honest ("Couldn't save the change").
    func replace(_ original: MealEntry, with edited: MealEntry) async throws {
        try await delete(entryID: original.id)
        do {
            try await record(edited)
        } catch {
            try? await record(original)
            throw error
        }
    }
}

/// Deterministic recorder for tests and `-simulateMealScan` (the sim can't grant HealthKit
/// auth reliably, and the demo shouldn't write to a real Health store anyway).
public final class InMemoryNutritionRecorder: NutritionRecorder, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [MealEntry] = []
    private var activeEnergy: [Date: Double] = [:]   // keyed by startOfDay
    private var observers: [@Sendable () -> Void] = []
    private let calendar: Calendar
    /// Test hooks: make authorization or writes fail to exercise the honest error paths.
    public var failAuthorization = false
    public var failWrites = false
    /// Fail exactly the next N writes, then succeed — lets tests exercise `replace`'s
    /// rollback (edited write fails, restore write succeeds).
    public var failNextWrites = 0

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public var entries: [MealEntry] {
        lock.withLock { stored }
    }

    /// Pre-populate (UI-test seeding, sim demos of past days).
    public func seed(_ entries: [MealEntry]) {
        lock.withLock { stored.append(contentsOf: entries) }
    }

    public func setActiveEnergy(_ kcal: Double, on day: Date) {
        let key = calendar.startOfDay(for: day)
        lock.withLock { activeEnergy[key] = kcal }
    }

    public func requestAuthorization() async throws {
        if failAuthorization { throw CocoaError(.featureUnsupported) }
    }

    public func record(_ entry: MealEntry) async throws {
        if failWrites { throw CocoaError(.fileWriteUnknown) }
        let shouldFail = lock.withLock {
            if failNextWrites > 0 {
                failNextWrites -= 1
                return true
            }
            return false
        }
        if shouldFail { throw CocoaError(.fileWriteUnknown) }
        let observers = lock.withLock {
            stored.append(entry)
            return self.observers
        }
        observers.forEach { $0() }
    }

    public func delete(entryID: UUID) async throws {
        let observers = lock.withLock {
            stored.removeAll { $0.id == entryID }
            return self.observers
        }
        observers.forEach { $0() }
    }

    public func intake(on day: Date) async throws -> DailyIntake {
        let calendar = self.calendar
        return lock.withLock {
            let dayEntries = stored
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .sorted { $0.date < $1.date }
            let total = dayEntries.reduce(0) { $0 + $1.facts.energy.midpointKcal * Double($1.quantity) }
            return DailyIntake(totalKcal: total, entries: dayEntries)
        }
    }

    public func activeEnergyBurned(on day: Date) async throws -> Double {
        let key = calendar.startOfDay(for: day)
        return lock.withLock { activeEnergy[key] ?? 0 }
    }

    public func observeChanges(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { observers.append(handler) }
    }
}
