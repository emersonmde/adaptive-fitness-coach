import Foundation

/// A scripted stand-in for the strength HealthKit backend: starts and ends without touching
/// HealthKit so the strength flow runs end-to-end in the Simulator (`-simulateStrength`) and in
/// tests. Emits a gently varying heart rate so the live readout is populated, and reports a
/// plausible average at the end. Cannot fail.
@MainActor
final class SimulatedStrengthBackend: WorkoutBackend {
    var onHeartRate: ((Double) -> Void)?
    var onZoneChange: ((Int?) -> Void)?   // strength emits no zones
    var onCadence: ((Double) -> Void)?    // and no cadence
    var onFailure: (() -> Void)? // never invoked; the simulated workout cannot fail

    private var task: Task<Void, Never>?

    /// A session-shaped HR curve at 2s cadence, matched to the self-driving demo's timeline:
    /// climbs during each ~7s "set", then decays and *stays low* through the 25s rests so the
    /// recovery ring fills, sustains the recovered window, and hits READY at the seed — the
    /// Simulator's only way to watch P2's adaptive rest work. Holds the last value once the
    /// script ends (no loop — a loop climbs mid-rest and flaps the recovery signal).
    private let script: [Double] = [
        112, 124, 133, 138,                                              // set 1 → peak 138
        134, 128, 121, 114, 108, 105, 104, 104, 104, 104, 104, 104,     // rest 1: recovered
        118, 130, 138, 142,                                              // set 2 → peak 142
        136, 128, 120, 112, 106, 104, 104, 104, 104, 104, 104, 104,     // rest 2: recovered
        108,                                                             // hold / summary
    ]

    func start() async throws {
        let script = self.script
        task = Task { [weak self] in
            var i = 0
            while !Task.isCancelled {
                self?.onHeartRate?(script[min(i, script.count - 1)])
                i += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func end() async -> WorkoutTotals {
        task?.cancel()
        task = nil
        return WorkoutTotals(distanceMeters: nil, averageHeartRate: 121)
    }
}
