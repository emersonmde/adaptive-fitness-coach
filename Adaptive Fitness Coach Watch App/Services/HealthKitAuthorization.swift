import Foundation
import HealthKit

/// Requests the HealthKit permissions the workout needs.
///
/// `HKLiveWorkoutBuilder` writes the workout, heart-rate, energy, and distance samples on the
/// app's behalf (N2 — the OS is the system of record), so those are share types. We read heart
/// rate for the live BPM display. Zones come from Apple's live classification
/// (`didUpdateWorkoutZone`) — the personalized native zones the project deliberately uses
/// instead of an app-computed estimate — which is driven by heart-rate access.
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
            // Cold-start calibration: past workouts + Apple's VO2max estimate seed the first
            // run/walk plan so nobody is asked "how fit are you?" (FitnessCalibration).
            HKObjectType.workoutType(),
            HKQuantityType(.vo2Max),
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
