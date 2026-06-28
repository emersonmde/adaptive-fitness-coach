import Foundation

/// A scripted stand-in for the strength HealthKit backend: starts and ends without touching
/// HealthKit so the strength flow runs end-to-end in the Simulator (`-simulateStrength`) and in
/// tests. Emits a gently varying heart rate so the live readout is populated, and reports a
/// plausible average at the end. Cannot fail.
@MainActor
final class SimulatedStrengthBackend: StrengthWorkoutBackend {
    var onHeartRate: ((Double) -> Void)?
    var onFailure: (() -> Void)? // never invoked; the simulated workout cannot fail

    private var task: Task<Void, Never>?

    /// A short loop of believable lifting heart rates (rises under load, recovers between sets).
    private let script: [Double] = [108, 118, 126, 132, 124, 114, 121, 130]

    func start() async throws {
        let script = self.script
        task = Task { [weak self] in
            var i = 0
            while !Task.isCancelled {
                self?.onHeartRate?(script[i % script.count])
                i += 1
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func end() async -> WorkoutTotals {
        task?.cancel()
        task = nil
        return WorkoutTotals(distanceMeters: nil, averageHeartRate: 121)
    }
}
