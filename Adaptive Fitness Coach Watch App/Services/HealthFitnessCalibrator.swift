import Foundation
import HealthKit
import AdaptiveCore

/// Reads the Health history `FitnessCalibration` maps to starting seeds: running workouts
/// from the last 90 days and the latest VO2max estimate. Pure decision logic lives in the
/// package; this file is only the HealthKit plumbing.
///
/// Failure of any kind — no permission, no data, HealthKit unavailable — yields `nil`, and
/// the caller keeps the conservative defaults (N6: infer from real data or not at all).
@MainActor
enum HealthFitnessCalibrator {

    /// Query Health and return calibrated seeds, or nil when there's no usable signal.
    static func calibratedSeeds() async -> RunSeeds? {
        guard HealthKitAuthorization.isAvailable else { return nil }
        let store = HealthKitAuthorization.healthStore

        async let runs = recentRunningWorkouts(store: store)
        async let vo2 = latestVO2Max(store: store)
        let (recentRuns, vo2Max) = await (runs, vo2)

        guard vo2Max != nil || !recentRuns.isEmpty else { return nil }
        return FitnessCalibration.seeds(vo2Max: vo2Max, recentRuns: recentRuns)
    }

    private static func recentRunningWorkouts(store: HKHealthStore) async -> [FitnessCalibration.PriorRun] {
        let since = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: since, end: nil),
        ])

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(), predicate: predicate,
                limit: 50, sortDescriptors: nil
            ) { _, samples, _ in
                let runs = (samples as? [HKWorkout] ?? []).map { workout in
                    FitnessCalibration.PriorRun(
                        duration: workout.duration,
                        distanceMeters: workout.totalDistance?.doubleValue(for: .meter())
                    )
                }
                continuation.resume(returning: runs)
            }
            store.execute(query)
        }
    }

    private static func latestVO2Max(store: HKHealthStore) async -> Double? {
        let unit = HKUnit(from: "ml/kg*min")
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.vo2Max), predicate: nil, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
