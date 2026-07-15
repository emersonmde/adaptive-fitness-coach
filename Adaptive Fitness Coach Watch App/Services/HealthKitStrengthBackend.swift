import Foundation
import HealthKit
import os

/// The production strength backend: a real Apple Traditional Strength Training workout via
/// `HKWorkoutSession` + `HKLiveWorkoutBuilder` (N2). It records the session to Health — including
/// heart rate, which the data source collects automatically — and reads the average HR back for
/// the summary. Shares the run side's `WorkoutBackend` protocol; the zone/cadence callbacks are
/// simply never fired (strength guidance is the card sequence, not a live HR band — N3), which
/// leaves the door open for P2's HR-informed rest adaptation without another protocol.
@MainActor
final class HealthKitStrengthBackend: NSObject, WorkoutBackend {
    var onHeartRate: ((Double) -> Void)?
    var onZoneChange: ((Int?) -> Void)?
    var onCadence: ((Double) -> Void)?
    var onFailure: (() -> Void)?

    private let healthStore = HealthKitAuthorization.healthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private var heartRateUnit: HKUnit { HKUnit.count().unitDivided(by: .minute()) }

    func start() async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

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
            // Same leak guard as the run backend: `startActivity` already ran, so end the
            // session before rethrowing or the orphan blocks the next start (sensors hot).
            session.end()
            self.session = nil
            self.builder = nil
            throw WorkoutStartFailure(cause: StartFailureCause(classifying: error), underlying: error)
        }
    }

    /// Retained after `finishWorkout` so a post-summary effort rating can be related to it.
    private var finishedWorkout: HKWorkout?

    func end() async -> WorkoutTotals {
        let endDate = Date()
        session?.end()
        var saved = true
        do {
            // Retry-once endCollection: absorbs the session.end()/endCollection state race
            // that would otherwise intermittently report "not saved" for a healthy workout.
            try await HealthKitWorkoutBackend.endCollectionSettling(builder, at: endDate)
            finishedWorkout = try await builder?.finishWorkout()
        } catch {
            // Fall through to whatever stats the builder gathered; never fabricate a value —
            // and never claim the workout saved when the finalize errored (N6).
            saved = false
        }
        let hr = builder?.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?.doubleValue(for: heartRateUnit)
        return WorkoutTotals(distanceMeters: nil, averageHeartRate: hr, savedToHealth: saved)
    }

    func writeEffortScore(_ score: Int) async {
        // Strength gets no Apple-estimated effort at all, so this rating is the only
        // Training-Load signal the workout carries.
        await HealthKitWorkoutBackend.relateEffort(score, to: finishedWorkout, store: healthStore)
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
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "AdaptiveFitnessCoach", category: "WorkoutBackend")
            .error("HKWorkoutSession failed mid-strength: \(String(describing: error), privacy: .public)")
        Task { @MainActor in self.onFailure?() }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate (live heart rate)

extension HealthKitStrengthBackend: HKLiveWorkoutBuilderDelegate {
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
}
