import Foundation

/// The workout session behind a strength routine. The sibling of `WorkoutBackend`, scoped down
/// to what strength needs: a session lifecycle that records a real Apple workout (N2), with no
/// live zone/heart-rate streaming — strength guidance is the card sequence, not a live HR band.
///
/// Abstracting it (like the run side) keeps the strength flow deterministically testable and
/// demoable in the Simulator, where no workout can actually be recorded.
@MainActor
protocol StrengthWorkoutBackend: AnyObject {
    /// Called with each new heart-rate sample (bpm). Live HR is shown for ambient awareness and
    /// between-set recovery — it does **not** govern strength load (that's set outcome, N3), so
    /// there is no zone signal here, only the rate.
    var onHeartRate: ((Double) -> Void)? { get set }
    /// Called if the workout fails *after* starting, so the manager can stop rather than keep a
    /// dead session on screen (N6). Never called by the simulated backend.
    var onFailure: (() -> Void)? { get set }

    /// Begin the underlying strength workout. Throws if it cannot be started.
    func start() async throws

    /// Stop the workout and return read-back totals (avg HR from the saved workout).
    func end() async -> WorkoutTotals
}
