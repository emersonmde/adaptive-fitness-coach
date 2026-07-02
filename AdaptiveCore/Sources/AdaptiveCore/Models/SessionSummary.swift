import Foundation

/// Post-workout read-back shown on the watch (A5).
///
/// Every metric is read back from the saved `HKWorkout` (distance, time, avg HR) or
/// derived from the engine's own session tracking (run/walk splits, adaptations). The app
/// writes nothing of its own to Health (N2) — this is acknowledgement, not a log (N1).
public struct SessionSummary: Sendable, Hashable {
    public var totalDuration: TimeInterval
    public var totalDistance: Double? // meters, nil if unavailable
    public var averageHeartRate: Double? // bpm, nil if unavailable
    public var totalRunDuration: TimeInterval
    public var totalWalkDuration: TimeInterval
    public var intervalsCompleted: Int
    public var adaptationsApplied: Int
    /// Run intervals the plan called for (before adaptation) — with `intervalsCompleted`,
    /// the completion signal for cross-session progression.
    public var plannedRunIntervals: Int
    /// Runs the engine cut short (HR back-off) — the struggle signal for progression.
    public var runBackOffCount: Int
    /// Walks that hit the max-walk cap still unrecovered.
    public var walksHitCap: Int
    /// Walks the user ran straight through (cadence-verified, nudges exhausted, accepted).
    /// Their recovery metrics reflect a choice, not a struggle — progression discounts them.
    public var walksDefied: Int
    /// Walks that ended at the floor (recovery confirmed as early as allowed) — the
    /// "fitter than the seeds" evidence for multi-notch progression.
    public var fastRecoveries: Int
    /// Longest single run interval sustained this session, seconds.
    public var longestRunSeconds: TimeInterval
    /// Mean heart-rate recovery drop (bpm) across the session's walks, nil if unmeasurable.
    public var meanRecoveryDrop: Double?
    /// True when the user ended the workout before the plan finished.
    public var endedEarly: Bool

    public init(
        totalDuration: TimeInterval,
        totalDistance: Double? = nil,
        averageHeartRate: Double? = nil,
        totalRunDuration: TimeInterval = 0,
        totalWalkDuration: TimeInterval = 0,
        intervalsCompleted: Int = 0,
        adaptationsApplied: Int = 0,
        plannedRunIntervals: Int = 0,
        runBackOffCount: Int = 0,
        walksHitCap: Int = 0,
        walksDefied: Int = 0,
        fastRecoveries: Int = 0,
        longestRunSeconds: TimeInterval = 0,
        meanRecoveryDrop: Double? = nil,
        endedEarly: Bool = false
    ) {
        self.totalDuration = totalDuration
        self.totalDistance = totalDistance
        self.averageHeartRate = averageHeartRate
        self.totalRunDuration = totalRunDuration
        self.totalWalkDuration = totalWalkDuration
        self.intervalsCompleted = intervalsCompleted
        self.adaptationsApplied = adaptationsApplied
        self.plannedRunIntervals = plannedRunIntervals
        self.runBackOffCount = runBackOffCount
        self.walksHitCap = walksHitCap
        self.walksDefied = walksDefied
        self.fastRecoveries = fastRecoveries
        self.longestRunSeconds = longestRunSeconds
        self.meanRecoveryDrop = meanRecoveryDrop
        self.endedEarly = endedEarly
    }
}
