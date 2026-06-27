import Foundation
import HealthKit

/// Requests the HealthKit permissions the workout needs.
///
/// `HKLiveWorkoutBuilder` writes the workout, heart-rate, energy, and distance samples on the
/// app's behalf (N2 — the OS is the system of record), so those are share types. We read heart
/// rate for the live BPM display; zones come from the builder's delegate, which needs heart-rate
/// access.
@MainActor
enum HealthKitAuthorization {
    static let healthStore = HKHealthStore()

    private static var shareTypes: Set<HKSampleType> {
        [
            HKQuantityType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
    }

    private static var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Request authorization. Returns false if Health data is unavailable or the request fails.
    /// A denial is not fatal — the session still runs; it just loses live HR/zone (N6).
    @discardableResult
    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }
}
