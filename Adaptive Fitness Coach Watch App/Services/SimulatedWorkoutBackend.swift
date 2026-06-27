import Foundation

/// A scripted stand-in for HealthKit: emits a fixed timeline of heart-rate/zone values so the
/// full workout — run, walk, adaptation, completion — runs deterministically in the Simulator
/// and in tests, where no real sensor data exists. Never used in normal device runs.
@MainActor
final class SimulatedWorkoutBackend: WorkoutBackend {
    var onHeartRate: ((Double) -> Void)?
    var onZoneChange: ((Int?) -> Void)?

    /// One scripted reading: at `at` seconds into the session, report `zone` and `hr`.
    struct Step: Sendable {
        let at: TimeInterval
        let zone: Int
        let hr: Double
    }

    private let script: [Step]
    private let target: Int?
    private var task: Task<Void, Never>?

    init(script: [Step] = SimulatedWorkoutBackend.demoScript, targetZoneIndex: Int? = 2) {
        self.script = script.sorted { $0.at < $1.at }
        self.target = targetZoneIndex
    }

    func start() async throws {
        let script = self.script
        let startDate = Date()
        task = Task { [weak self] in
            for step in script {
                let wait = step.at - Date().timeIntervalSince(startDate)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                if Task.isCancelled { return }
                self?.onHeartRate?(step.hr)
                self?.onZoneChange?(step.zone)
            }
        }
    }

    func end() async -> WorkoutTotals {
        task?.cancel()
        task = nil
        return WorkoutTotals(distanceMeters: 2400, averageHeartRate: 138)
    }

    func preferredTargetZoneIndex() async -> Int? { target }

    /// A ~60s timeline that exercises both adaptation directions: comfortable → hot (back off)
    /// → recovered (shorten walk) → comfortable (extend). Target zone is 2.
    nonisolated static var demoScript: [Step] {
        [
            Step(at: 0, zone: 1, hr: 102),   // warmup, easy
            Step(at: 4, zone: 2, hr: 128),   // running, in the aerobic band
            Step(at: 9, zone: 4, hr: 168),   // running hot → back off (shorten run)
            Step(at: 16, zone: 1, hr: 118),  // walking, recovered fast → shorten walk
            Step(at: 24, zone: 2, hr: 132),  // running, comfortable
            Step(at: 30, zone: 1, hr: 120),  // sustained easy → extend run
            Step(at: 44, zone: 3, hr: 150),  // drifting up
            Step(at: 52, zone: 2, hr: 134),  // settled back
        ]
    }
}
