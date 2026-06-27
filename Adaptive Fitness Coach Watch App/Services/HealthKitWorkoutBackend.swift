import Foundation
import HealthKit

/// The production backend: a real Apple outdoor-run workout via `HKWorkoutSession` +
/// `HKLiveWorkoutBuilder` (N2). It surfaces live heart rate and Apple's *personalized* zone
/// classification (`didUpdateWorkoutZone`), and lets the builder persist everything to Health.
@MainActor
final class HealthKitWorkoutBackend: NSObject, WorkoutBackend {
    var onHeartRate: ((Double) -> Void)?
    var onZoneChange: ((Int?) -> Void)?

    private let healthStore = HealthKitAuthorization.healthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private var heartRateUnit: HKUnit { HKUnit.count().unitDivided(by: .minute()) }

    func start() async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
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
            let workout = try await builder?.finishWorkout()
            return readTotals(workout: workout)
        } catch {
            return readTotals(workout: nil)
        }
    }

    private func readTotals(workout: HKWorkout?) -> WorkoutTotals {
        let hr = builder?.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?.doubleValue(for: heartRateUnit)
        let distance = builder?.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter())
            ?? workout?.totalDistance?.doubleValue(for: .meter())
        return WorkoutTotals(distanceMeters: distance, averageHeartRate: hr)
    }

    func preferredTargetZoneIndex() async -> Int? {
        do {
            guard let config = try await healthStore.preferredWorkoutZoneConfiguration(for: HKQuantityType(.heartRate)) else {
                return nil
            }
            let sorted = config.zones.sorted { $0.index < $1.index }
            // Aerobic "Zone 2" = the second zone from the bottom.
            if sorted.count >= 2 { return sorted[1].index }
            return sorted.first?.index
        } catch {
            return nil
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HealthKitWorkoutBackend: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension HealthKitWorkoutBackend: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)) else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?.doubleValue(for: unit)
        Task { @MainActor in
            if let hr { self.onHeartRate?(hr) }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didUpdateWorkoutZone zoneUpdate: HKLiveWorkoutZoneUpdate
    ) {
        let index = zoneUpdate.currentZoneDuration?.zone.index
        Task { @MainActor in
            self.onZoneChange?(index)
        }
    }
}
