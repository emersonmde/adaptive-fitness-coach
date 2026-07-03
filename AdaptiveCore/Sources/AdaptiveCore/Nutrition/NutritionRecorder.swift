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
    /// Writes one entry (energy + macros, provenance in metadata). Returning without
    /// throwing means Health confirmed the save — only then may the UI say "Saved" (N6).
    func record(_ entry: MealEntry) async throws
    /// Deletes an entry previously written by us (daily-line swipe-to-delete).
    func delete(entryID: UUID) async throws
    func todayIntake() async throws -> DailyIntake
    /// Fires whenever dietary energy changes in Health (any source) — refresh the daily line.
    func observeChanges(_ handler: @escaping @Sendable () -> Void)
}

/// Deterministic recorder for tests and `-simulateMealScan` (the sim can't grant HealthKit
/// auth reliably, and the demo shouldn't write to a real Health store anyway).
public final class InMemoryNutritionRecorder: NutritionRecorder, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [MealEntry] = []
    private var observers: [@Sendable () -> Void] = []
    /// Test hook: make authorization or writes fail to exercise the honest error paths.
    public var failAuthorization = false
    public var failWrites = false

    public init() {}

    public var entries: [MealEntry] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func requestAuthorization() async throws {
        if failAuthorization { throw CocoaError(.featureUnsupported) }
    }

    public func record(_ entry: MealEntry) async throws {
        if failWrites { throw CocoaError(.fileWriteUnknown) }
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

    public func todayIntake() async throws -> DailyIntake {
        let calendar = Calendar.current
        return lock.withLock {
            let today = stored.filter { calendar.isDateInToday($0.date) }
            let total = today.reduce(0) { $0 + $1.facts.energy.midpointKcal * Double($1.quantity) }
            return DailyIntake(totalKcal: total, entries: today)
        }
    }

    public func observeChanges(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { observers.append(handler) }
    }
}
