import Foundation

/// A scripted stand-in for the strength HealthKit backend: starts and ends without touching
/// HealthKit so the strength flow runs end-to-end in the Simulator (`-simulateStrength`) and in
/// tests. Reports a plausible average HR so the summary has something to show. Cannot fail.
@MainActor
final class SimulatedStrengthBackend: StrengthWorkoutBackend {
    var onFailure: (() -> Void)? // never invoked; the simulated workout cannot fail

    func start() async throws {}

    func end() async -> WorkoutTotals {
        WorkoutTotals(distanceMeters: nil, averageHeartRate: 121)
    }
}
