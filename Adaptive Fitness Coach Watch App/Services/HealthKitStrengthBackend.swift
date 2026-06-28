import Foundation
import HealthKit

/// The production strength backend: a real Apple Traditional Strength Training workout via
/// `HKWorkoutSession` + `HKLiveWorkoutBuilder` (N2). It records the session to Health — including
/// heart rate, which the data source collects automatically — and reads the average HR back for
/// the summary. No live signal is surfaced mid-session; the card sequence is the guidance.
@MainActor
final class HealthKitStrengthBackend: NSObject, StrengthWorkoutBackend {
    var onFailure: (() -> Void)?

    private let healthStore = HealthKitAuthorization.healthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private var heartRateUnit: HKUnit { HKUnit.count().unitDivided(by: .minute()) }

    func start() async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        self.session = session
        self.builder = builder

        let startDate = Date()
        session.startActivity(with: startDate)
        try await builder.beginCollection(at: startDate)
    }

    func end() async -> WorkoutTotals {
        let endDate = Date()
        session?.end()
        do {
            try await builder?.endCollection(at: endDate)
            _ = try await builder?.finishWorkout()
        } catch {
            // Fall through to whatever stats the builder gathered; never fabricate a value (N6).
        }
        let hr = builder?.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?.doubleValue(for: heartRateUnit)
        return WorkoutTotals(distanceMeters: nil, averageHeartRate: hr)
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HealthKitStrengthBackend: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // The session died after starting — stop rather than keep a dead session on screen (N6).
        Task { @MainActor in self.onFailure?() }
    }
}
