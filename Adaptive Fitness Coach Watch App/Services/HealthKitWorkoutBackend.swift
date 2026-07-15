import CoreMotion
import Foundation
import HealthKit
import os

extension StartFailureCause {
    /// Classify a HealthKit start error into a user-meaningful cause (W5). Lives in the
    /// HealthKit-importing layer so the managers — which branch on the cause — never need
    /// to know `HKError` exists.
    init(classifying error: Error) {
        if (error as? HKError)?.code == .errorAuthorizationDenied {
            self = .permissionsDenied
        } else {
            self = .unknown
        }
    }
}

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

        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        } catch {
            throw WorkoutStartFailure(cause: StartFailureCause(classifying: error), underlying: error)
        }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder

        let startDate = Date()
        session.startActivity(with: startDate)
        do {
            try await builder.beginCollection(at: startDate)
        } catch {
            // `startActivity` already ran, so a failed `beginCollection` would otherwise leak
            // a live session — sensors hot, and the *next* start blocked by the orphan. End it
            // before surfacing the failure so "couldn't start" really means nothing is running.
            session.end()
            self.session = nil
            self.builder = nil
            throw WorkoutStartFailure(cause: StartFailureCause(classifying: error), underlying: error)
        }
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

    /// Retained after `finishWorkout` so a post-summary effort rating can be related to it.
    private var finishedWorkout: HKWorkout?

    func end() async -> WorkoutTotals {
        await end(metadata: [:])
    }

    func end(metadata: [String: String]) async -> WorkoutTotals {
        pedometer?.stopUpdates()
        pedometer = nil
        let endDate = Date()
        session?.end()
        do {
            try await Self.endCollectionSettling(builder, at: endDate)
            // The run digest (P6.1) rides the workout as custom metadata — attached once the
            // engine's numbers are final, and BEST-EFFORT: a failed metadata write must never
            // fail the workout save (the workout is the record; the digest is enrichment).
            // If on-device testing shows addMetadata rejects post-endCollection, move this
            // above endCollectionSettling — both orders precede finishWorkout.
            if !metadata.isEmpty {
                try? await builder?.addMetadata(metadata)
            }
            let workout = try await builder?.finishWorkout()
            finishedWorkout = workout
            return readTotals(workout: workout, saved: true)
        } catch {
            return readTotals(workout: nil, saved: false)
        }
    }

    /// `session.end()` is asynchronous under the hood, so an immediate `endCollection` can race
    /// the state transition and throw even though the workout is perfectly healthy — which would
    /// falsely report "not saved" (N6 says be honest, not pessimistic). One short-sleep retry
    /// absorbs the race; a second failure is a real error and propagates to the failure path.
    static func endCollectionSettling(_ builder: HKLiveWorkoutBuilder?, at endDate: Date) async throws {
        do {
            try await builder?.endCollection(at: endDate)
        } catch {
            try? await Task.sleep(for: .seconds(1))
            try await builder?.endCollection(at: endDate)
        }
    }

    func writeEffortScore(_ score: Int) async {
        await Self.relateEffort(score, to: finishedWorkout, store: healthStore)
    }

    /// Delete the just-finished saved workout (W20). Only the `HKWorkout` this backend wrote
    /// via `finishWorkout` is ever deleted — deleting the workout also removes the samples
    /// the builder collected for it.
    func discardWorkout() async -> Bool {
        guard let finishedWorkout else { return false }
        do {
            try await healthStore.delete(finishedWorkout)
            self.finishedWorkout = nil
            return true
        } catch {
            return false
        }
    }

    /// Write an `HKWorkoutEffortScore` (1–10) sample and relate it to the workout — the same
    /// field Apple's Fitness "Effort" writes, feeding Training Load (N2: the OS is the record).
    static func relateEffort(_ score: Int, to workout: HKWorkout?, store: HKHealthStore) async {
        guard let workout else { return }
        let clamped = min(max(score, 1), 10)
        let type = HKQuantityType(.workoutEffortScore)
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: Double(clamped)),
            start: workout.startDate,
            end: workout.endDate
        )
        do {
            try await store.save(sample)
            try await store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
        } catch {
            // Best-effort: a failed effort write never blocks the summary (N6).
        }
    }

    private func readTotals(workout: HKWorkout?, saved: Bool) -> WorkoutTotals {
        let hr = builder?.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?.doubleValue(for: heartRateUnit)
        let distance = builder?.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter())
            ?? workout?.totalDistance?.doubleValue(for: .meter())
        return WorkoutTotals(distanceMeters: distance, averageHeartRate: hr, savedToHealth: saved)
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
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "AdaptiveFitnessCoach", category: "WorkoutBackend")
            .error("HKWorkoutSession failed mid-run: \(String(describing: error), privacy: .public)")
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
