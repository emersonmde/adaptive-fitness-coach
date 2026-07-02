import Foundation

/// A scripted stand-in for HealthKit: emits a fixed timeline of heart-rate/zone values so the
/// full workout — run, walk, adaptation, completion — runs deterministically in the Simulator
/// and in tests, where no real sensor data exists. Never used in normal device runs.
@MainActor
final class SimulatedWorkoutBackend: WorkoutBackend {
    var onHeartRate: ((Double) -> Void)?
    var onZoneChange: ((Int?) -> Void)?
    var onCadence: ((Double) -> Void)?
    var onFailure: (() -> Void)? // never invoked; the simulated workout cannot fail

    /// One scripted reading: at `at` seconds into the session, report `zone` (1-based position)
    /// and `hr`, plus optionally a `cadence` (steps/minute — drives warmup run-detection).
    struct Step: Sendable {
        let at: TimeInterval
        let zone: Int
        let hr: Double
        var cadence: Double?

        init(at: TimeInterval, zone: Int, hr: Double, cadence: Double? = nil) {
            self.at = at
            self.zone = zone
            self.hr = hr
            self.cadence = cadence
        }
    }

    private let script: [Step]
    private var task: Task<Void, Never>?

    init(script: [Step] = SimulatedWorkoutBackend.demoScript) {
        self.script = script.sorted { $0.at < $1.at }
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
                if let cadence = step.cadence { self?.onCadence?(cadence) }
            }
        }
    }

    func end() async -> WorkoutTotals {
        task?.cancel()
        task = nil
        return WorkoutTotals(distanceMeters: 2400, averageHeartRate: 138)
    }

    /// A ~60s timeline for the compressed demo plan (25s warmup, 6s runs / 5s walks): walking
    /// cadence turns into a sustained running cadence that cuts the warmup short ~13s in, then
    /// the zones/HR exercise back-off (hot run) and HR-drop recovery (walk ends early).
    /// Target zone is 2.
    nonisolated static var demoScript: [Step] {
        [
            Step(at: 0, zone: 1, hr: 102, cadence: 112),   // warmup walking
            Step(at: 3, zone: 1, hr: 106, cadence: 152),   // user starts jogging...
            Step(at: 6, zone: 1, hr: 112, cadence: 154),
            Step(at: 9, zone: 1, hr: 118, cadence: 155),
            Step(at: 13, zone: 2, hr: 128, cadence: 156),  // ...10s sustained → warmup skips
            Step(at: 18, zone: 4, hr: 168),                // running hot → back off (shorten run)
            Step(at: 20, zone: 2, hr: 140),                // walking, HR falling immediately
            Step(at: 24, zone: 2, hr: 136),                // 32bpm below peak → fast recovery
                                                           //   (also unlocks run extension)
            Step(at: 34, zone: 2, hr: 136),                // run 2, comfortable → extends
            Step(at: 44, zone: 3, hr: 152),                // drifting hot → extended run ends
            Step(at: 52, zone: 1, hr: 128),                // recovered again → walk ends → cooldown
        ]
    }
}
