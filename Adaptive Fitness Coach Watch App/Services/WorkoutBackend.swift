import Foundation

/// Read-back totals for the post-workout summary, sourced from the saved `HKWorkout` in the
/// real backend (the OS is the system of record — N2) or synthesized by the simulated one.
struct WorkoutTotals: Sendable {
    var distanceMeters: Double?
    var averageHeartRate: Double?
    /// Whether the OS confirmed the workout was finalized. False only when `finishWorkout`
    /// errored — the summary then avoids claiming "Saved to Health" (N6).
    var savedToHealth: Bool = true
}

/// Why a workout could not start, in user-meaningful terms (W5 — the start error must not be
/// discarded; the failed screen's copy branches on this). Foundation-only: the HealthKit
/// backends classify their own `HKError`s into a cause so the managers stay HealthKit-free.
enum StartFailureCause: Equatable, Sendable {
    /// Health authorization was denied — the one cause the user can actually fix themselves
    /// (iPhone → Health → Sharing), so it's the only one whose copy mentions permissions.
    case permissionsDenied
    case unknown
}

/// A typed start failure thrown across the `WorkoutBackend.start()` boundary: carries the
/// classified cause for the failed-to-start UI plus the underlying error for logging.
struct WorkoutStartFailure: Error {
    let cause: StartFailureCause
    let underlying: Error
}

extension StartFailureCause {
    /// The cause behind an arbitrary start error: typed failures carry their own; anything
    /// else (test doubles, unexpected throws) is honestly unknown.
    init(from error: Error) {
        self = (error as? WorkoutStartFailure)?.cause ?? .unknown
    }
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

    /// Stop the workout, attaching app-specific metadata to the saved `HKWorkout` first
    /// (P6.1 — the run digest; Health is the store, N2). Backends that don't persist to
    /// Health ignore the metadata via the default.
    func end(metadata: [String: String]) async -> WorkoutTotals

    /// Relate a perceived-effort score (1–10) to the finished workout in Health
    /// (`HKWorkoutEffortScore`), called after `end()` when the user rates on the complete
    /// screen (build 9). No-op for backends that don't persist to Health.
    func writeEffortScore(_ score: Int) async

    /// Delete the just-finished workout this backend saved (W20 — "Discard workout" on a
    /// mis-tap-sized ended-early session). Deletes only our own just-written `HKWorkout`,
    /// never anything else in Health (N2-adjacent). Returns whether the delete succeeded.
    func discardWorkout() async -> Bool
}

extension WorkoutBackend {
    /// Default: simulated backends and test doubles don't write to Health.
    func writeEffortScore(_ score: Int) async {}

    /// Default: backends that don't persist to Health have nothing to delete.
    func discardWorkout() async -> Bool { true }

    /// Default: metadata is a Health-persistence concern; everything else just ends.
    func end(metadata: [String: String]) async -> WorkoutTotals { await end() }
}
