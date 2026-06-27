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

    public init(
        totalDuration: TimeInterval,
        totalDistance: Double? = nil,
        averageHeartRate: Double? = nil,
        totalRunDuration: TimeInterval = 0,
        totalWalkDuration: TimeInterval = 0,
        intervalsCompleted: Int = 0,
        adaptationsApplied: Int = 0
    ) {
        self.totalDuration = totalDuration
        self.totalDistance = totalDistance
        self.averageHeartRate = averageHeartRate
        self.totalRunDuration = totalRunDuration
        self.totalWalkDuration = totalWalkDuration
        self.intervalsCompleted = intervalsCompleted
        self.adaptationsApplied = adaptationsApplied
    }
}
