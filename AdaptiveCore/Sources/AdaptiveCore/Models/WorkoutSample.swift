import Foundation

/// One tick's worth of live signals fed to the interval engine.
///
/// Both fields are optional because either can drop out independently mid-workout (sensor
/// gap, zone not yet classified). The engine degrades per-field rather than all-or-nothing:
/// no zone → no run back-off; no heart rate → no recovery tracking; neither → fixed
/// intervals (N6 — adapt on real signals or not at all, never fabricate).
public struct WorkoutSample: Sendable, Equatable {
    /// The classified heart-rate zone as a 1-based position within the user's zone
    /// configuration (see the watch backend's normalization). Never Apple's raw index.
    public var zone: Int?
    /// Raw heart rate in bpm. The engine uses it only for recovery math (peak tracking and
    /// heart-rate-recovery drop during walks) — zone remains the effort signal for runs.
    public var heartRate: Double?

    public init(zone: Int? = nil, heartRate: Double? = nil) {
        self.zone = zone
        self.heartRate = heartRate
    }
}
