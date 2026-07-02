import CoreMotion
import Foundation
import HealthKit

/// The production backend: a real Apple outdoor-run workout via `HKWorkoutSession` +
/// `HKLiveWorkoutBuilder` (N2). It surfaces live heart rate and Apple's *personalized* zone
/// classification (`didUpdateWorkoutZone`), and lets the builder persist everything to Health.
@MainActor
final class HealthKitWorkoutBackend: NSObject, WorkoutBackend {
    var onHeartRate: ((Double) -> Void)?
    var onZoneChange: ((Int?) -> Void)?
    var onCadence: ((Double) -> Void)?
    /// Called if the session fails after starting (sensor loss, OS termination). Drives the
    /// manager out of the active state instead of ticking against a dead session (N6).
    var onFailure: (() -> Void)?

    private let healthStore = HealthKitAuthorization.healthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// Live cadence source for warmup run-detection. CMPedometer over the HK live builder's
    /// stepCount because the pedometer reports `currentCadence` every ~2.5s while builder
    /// samples batch far too slowly for a 10s detection window. Unavailable/denied → no
    /// callbacks, warmup keeps its fixed timer (N6).
    private var pedometer: CMPedometer?

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
        startCadenceUpdates(from: startDate)
    }

    private func startCadenceUpdates(from startDate: Date) {
        guard CMPedometer.isCadenceAvailable() else { return }
        let pedometer = CMPedometer()
        self.pedometer = pedometer
        pedometer.startUpdates(from: startDate) { [weak self] data, error in
            // currentCadence is steps/second; the detector speaks steps/minute.
            guard error == nil, let cadence = data?.currentCadence?.doubleValue else { return }
            Task { @MainActor in self?.onCadence?(cadence * 60) }
        }
    }

    func end() async -> WorkoutTotals {
        pedometer?.stopUpdates()
        pedometer = nil
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

    /// Map Apple's raw `HKWorkoutZone.index` to a 1-based position within the configuration's
    /// sorted zones, so the engine compares like-for-like regardless of Apple's index base.
    /// Returns nil if the update carries no usable zone/configuration.
    nonisolated private static func normalizedPosition(for update: HKLiveWorkoutZoneUpdate) -> Int? {
        guard let current = update.currentZoneDuration?.zone,
              let zones = update.zoneGroup?.configuration.zones, !zones.isEmpty else {
            return nil
        }
        let sorted = zones.sorted { $0.index < $1.index }
        guard let position = sorted.firstIndex(where: { $0.index == current.index }) else { return nil }
        return position + 1 // 1-based: lowest zone = 1
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

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // The session died after starting — never fabricate continued guidance (N6).
        Task { @MainActor in self.onFailure?() }
    }
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
        let position = Self.normalizedPosition(for: zoneUpdate)
        Task { @MainActor in
            self.onZoneChange?(position)
        }
    }
}
