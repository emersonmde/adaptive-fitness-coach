import Foundation

/// Everything the interval engine needs to run one session.
///
/// Heart-rate zone *boundaries* are not stored here — those come from Apple's
/// `preferredZoneConfiguration` at the HealthKit layer. The engine works on the
/// classified zone number (1–5) Apple emits, so the only zone knowledge it needs is
/// which zone is the aerobic target.
public struct SessionConfig: Codable, Sendable, Hashable {
    public var plan: IntervalPlan

    /// The aerobic "conversational" target zone for run intervals. Above this is "too hot",
    /// at or below is "comfortable". Apple's Zone 2 is the default aerobic-base target (Q2).
    public var targetZone: Int

    public init(plan: IntervalPlan, targetZone: Int = 2) {
        self.plan = plan
        self.targetZone = targetZone
    }
}
