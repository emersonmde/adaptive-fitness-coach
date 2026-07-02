import Foundation

/// Read-back totals for the post-workout summary, sourced from the saved `HKWorkout` in the
/// real backend (the OS is the system of record — N2) or synthesized by the simulated one.
struct WorkoutTotals: Sendable {
    var distanceMeters: Double?
    var averageHeartRate: Double?
}

/// The sensor/zone source behind a workout. Abstracting it lets the adaptive loop run against
/// either real HealthKit (`HealthKitWorkoutBackend`) or a scripted source
/// (`SimulatedWorkoutBackend`) — the latter makes the whole workout deterministically testable
/// and demoable in the Simulator, where no real heart-rate or zone data exists.
///
/// The backend only *produces* signals (heart rate, zone) and persists the workout; all
/// adaptation logic stays in `WorkoutSessionManager` + `AdaptiveCore`.
///
/// **Zone contract:** `onZoneChange` reports a **1-based zone position** (1 = lowest zone),
/// not Apple's raw `HKWorkoutZone.index` (whose base is unspecified). The HealthKit backend
/// normalizes the raw index to a position within the user's zone configuration so the engine's
/// fixed `targetZone == 2` ("second zone from the bottom" = aerobic) is meaningful regardless
/// of Apple's indexing. `nil` means "no zone data yet" (graceful degradation, N6).
@MainActor
protocol WorkoutBackend: AnyObject {
    /// Called with each new heart-rate sample (bpm) for the live display.
    var onHeartRate: ((Double) -> Void)? { get set }
    /// Called when the live zone changes; carries a 1-based zone position (see the type doc).
    var onZoneChange: ((Int?) -> Void)? { get set }
    /// Called with each new cadence sample (steps per minute), used to detect that the user
    /// started running during the warmup. Optional signal: a backend that can't measure
    /// cadence (denied motion permission, old hardware) simply never calls it, and warmup
    /// falls back to its fixed timer (N6).
    var onCadence: ((Double) -> Void)? { get set }
    /// Called if the workout fails *after* starting, so the manager can stop rather than tick
    /// against a dead session (N6). Never called by the simulated backend.
    var onFailure: (() -> Void)? { get set }

    /// Begin the underlying workout. Throws if it cannot be started.
    func start() async throws

    /// Stop the workout and return read-back totals.
    func end() async -> WorkoutTotals
}
