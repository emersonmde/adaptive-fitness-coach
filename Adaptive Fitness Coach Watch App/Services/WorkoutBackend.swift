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
@MainActor
protocol WorkoutBackend: AnyObject {
    /// Called with each new heart-rate sample (bpm) for the live display.
    var onHeartRate: ((Double) -> Void)? { get set }
    /// Called when the live zone classification changes; nil means "no zone data yet".
    var onZoneChange: ((Int?) -> Void)? { get set }

    /// Begin the underlying workout. Throws if it cannot be started.
    func start() async throws

    /// Stop the workout and return read-back totals.
    func end() async -> WorkoutTotals

    /// The user's aerobic target zone index, if the source can provide it.
    func preferredTargetZoneIndex() async -> Int?
}
