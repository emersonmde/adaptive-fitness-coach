import Foundation
import HealthKit
import AdaptiveCore

/// Reads the aggregate fitness numbers a context pack's "fitness snapshot" carries — VO2max,
/// resting HR, respiratory rate, weight (+30-day delta), our-workout frequency and the days
/// since the last one. Aggregates and latest values only, never raw sample streams.
///
/// Same discipline as `HealthKitBodyProfileSource`: deferred-contextual auth (requested when
/// the export sheet first needs it, `toShare: []`), and any missing/denied datum → a nil
/// field, which the pack composer renders as an omitted line (N6 — HealthKit hides read
/// denial, so absence is never labeled).
final class HealthSnapshotBuilder: @unchecked Sendable {

    private let store = HKHealthStore()
    /// The watch app's bundle id is the phone's + ".watchkitapp" — prefix-match covers both.
    private let bundlePrefix = Bundle.main.bundleIdentifier ?? "—"

    private static let vo2MaxType = HKQuantityType(.vo2Max)
    private static let restingHRType = HKQuantityType(.restingHeartRate)
    private static let respiratoryType = HKQuantityType(.respiratoryRate)
    private static let massType = HKQuantityType(.bodyMass)

    func requestAuthorization() async throws {
        // UI tests must never raise the system Health sheet; snapshot() is empty there too.
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        guard HKHealthStore.isHealthDataAvailable() else { throw CocoaError(.featureUnsupported) }
        try await store.requestAuthorization(
            toShare: [],
            read: [
                Self.vo2MaxType, Self.restingHRType, Self.respiratoryType, Self.massType,
                HKObjectType.workoutType(),
            ]
        )
    }

    /// Build the snapshot. Every field independent — one denied read never empties the rest.
    func snapshot(now: Date = Date()) async -> HealthSnapshot {
        guard HKHealthStore.isHealthDataAvailable(),
              !ProcessInfo.processInfo.arguments.contains("-uiTesting") else {
            return HealthSnapshot()
        }
        var snapshot = HealthSnapshot()

        // Source: Apple exposes VO2max in ml/kg·min (HKUnit string per HealthFitnessCalibrator).
        let vo2Unit = HKUnit(from: "ml/kg*min")
        snapshot.vo2Max = await latestValue(of: Self.vo2MaxType, unit: vo2Unit)
        snapshot.restingHeartRate = await latestValue(
            of: Self.restingHRType, unit: HKUnit.count().unitDivided(by: .minute()))
        snapshot.respiratoryRate = await latestValue(
            of: Self.respiratoryType, unit: HKUnit.count().unitDivided(by: .minute()))

        let kg = HKUnit.gramUnit(with: .kilo)
        if let current = await latestSample(of: Self.massType) {
            let currentKg = current.quantity.doubleValue(for: kg)
            snapshot.bodyMassKg = currentKg
            // Delta vs the latest sample at least ~30 days old (nil when history is thinner).
            if let past = await latestSample(
                of: Self.massType,
                before: now.addingTimeInterval(-30 * 86_400)
            ) {
                snapshot.bodyMassDelta30dKg = currentKg - past.quantity.doubleValue(for: kg)
            }
        }

        let ninetyDaysAgo = now.addingTimeInterval(-90 * 86_400)
        let workouts = await ourWorkouts(from: ninetyDaysAgo, to: now)
        if !workouts.isEmpty {
            snapshot.workoutsPerWeek90d = Double(workouts.count) / (90.0 / 7.0)
            if let last = workouts.map(\.startDate).max() {
                snapshot.daysSinceLastWorkout = Calendar.current
                    .dateComponents([.day], from: last, to: now).day
            }
        }
        return snapshot
    }

    /// Days since the last workout of ours in a wider window — the return-from-break signal.
    /// nil when no workout of ours exists in the window (a brand-new user isn't "returning").
    func daysSinceLastWorkout(windowDays: Int = 120, now: Date = Date()) async -> Int? {
        guard HKHealthStore.isHealthDataAvailable(),
              !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return nil }
        let workouts = await ourWorkouts(
            from: now.addingTimeInterval(-Double(windowDays) * 86_400), to: now)
        guard let last = workouts.map(\.startDate).max() else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: now).day
    }

    // MARK: - Queries

    private func ourWorkouts(from start: Date, to end: Date) async -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples: [HKSample] = (try? await samples(
            of: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit)) ?? []
        return (samples as? [HKWorkout] ?? []).filter {
            $0.sourceRevision.source.bundleIdentifier.hasPrefix(bundlePrefix)
        }
    }

    private func latestValue(of type: HKQuantityType, unit: HKUnit) async -> Double? {
        (await latestSample(of: type))?.quantity.doubleValue(for: unit)
    }

    private func latestSample(of type: HKQuantityType, before: Date? = nil) async -> HKQuantitySample? {
        let predicate = before.map {
            HKQuery.predicateForSamples(withStart: nil, end: $0, options: [])
        }
        let samples = try? await samples(of: type, predicate: predicate, limit: 1)
        return samples?.first as? HKQuantitySample
    }

    private func samples(
        of type: HKSampleType, predicate: NSPredicate?, limit: Int
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }
}
