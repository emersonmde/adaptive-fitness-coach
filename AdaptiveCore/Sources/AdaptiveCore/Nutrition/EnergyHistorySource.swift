import Foundation

/// A trailing daily series of the three signals the calibration needs from Apple Health:
/// body-weight samples, daily dietary energy, and daily active energy. Mirrors the
/// `NutritionRecorder`/`BodyProfileSource` seam — protocol + in-package fake here,
/// `HealthKitEnergyHistorySource` phone-side.

public struct DatedValue: Sendable, Equatable {
    public var date: Date
    public var value: Double
    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct EnergyHistory: Sendable, Equatable {
    /// Body-mass samples (kg), one or more per day, over the window.
    public var weights: [DatedValue]
    /// Dietary energy consumed per day (kcal). Missing days simply absent (they lower coverage).
    public var dailyIntakeKcal: [DatedValue]
    /// Active energy burned per day (kcal), raw watch numbers (the trust haircut is applied later).
    public var dailyActiveKcal: [DatedValue]

    public init(weights: [DatedValue] = [], dailyIntakeKcal: [DatedValue] = [], dailyActiveKcal: [DatedValue] = []) {
        self.weights = weights
        self.dailyIntakeKcal = dailyIntakeKcal
        self.dailyActiveKcal = dailyActiveKcal
    }
}

public protocol EnergyHistorySource: Sendable {
    /// Deferred-contextual authorization (weight/energy reads). A denial is not a throw —
    /// HealthKit hides read denial, so the calibration just falls back to the safe prior.
    func requestAuthorization() async throws
    /// The trailing `days`-day window ending on `day` (inclusive).
    func history(trailingDays days: Int, endingOn day: Date) async throws -> EnergyHistory
}

public extension EnergyHistorySource {
    func requestAuthorization() async throws {}   // fakes need no permission
}

/// Deterministic source for the simulator and tests — seed a window and it returns it verbatim.
public final class InMemoryEnergyHistorySource: EnergyHistorySource, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: EnergyHistory

    public init(_ history: EnergyHistory = EnergyHistory()) {
        self.stored = history
    }

    public func set(_ history: EnergyHistory) {
        lock.withLock { stored = history }
    }

    public func history(trailingDays days: Int, endingOn day: Date) async throws -> EnergyHistory {
        lock.withLock { stored }
    }
}

public extension EnergyBalanceCalibrator {
    /// Convenience over `EnergyHistory` — maps the series onto the tuple API.
    static func calibrate(
        history: EnergyHistory,
        profile: BodyProfile,
        activeTrust: Double = EnergyBudgetConstants.activeTrustDefault,
        calendar: Calendar = .current
    ) -> Calibration {
        calibrate(
            weights: history.weights.map { (date: $0.date, kg: $0.value) },
            dailyIntakeKcal: history.dailyIntakeKcal.map { (date: $0.date, kcal: $0.value) },
            dailyActiveKcal: history.dailyActiveKcal.map { (date: $0.date, kcal: $0.value) },
            profile: profile,
            activeTrust: activeTrust,
            calendar: calendar
        )
    }
}
