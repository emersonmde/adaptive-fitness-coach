import Foundation
import HealthKit
import AdaptiveCore

/// Which days THIS WEEK have a completed workout of ours — the hub strip's backward glance.
/// N2 working in our favor: the OS is the system of record, so "did I train Tuesday" is a
/// HealthKit read, not an app-side log. Only workouts written by this app family (phone or
/// watch) count — a walk auto-logged by the watch shouldn't mark a training day done.
///
/// Deliberately NOT a streak: the strip marks facts for the current week and never counts,
/// chains, or scolds (design principles — no streaks/shame).
@MainActor
final class WorkoutWeekHistory {
    static let shared = WorkoutWeekHistory()
    private let store = HKHealthStore()
    /// The watch app's bundle id is the phone's + ".watchkitapp" — prefix-match covers both.
    private let bundlePrefix = Bundle.main.bundleIdentifier ?? "—"

    func doneDays(now: Date = Date()) async -> Set<DayOfWeek> {
        // UI tests need a deterministic (unmarked) strip; the sim generally has no workouts.
        guard HKHealthStore.isHealthDataAvailable(),
              !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return [] }
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }

        // Read auth for workouts rides the nutrition recorder's request (deferred to the
        // first meal Log — never a launch-time prompt). Unauthorized reads just return
        // nothing: the strip quietly shows scheduled dots only, never an error.
        let predicate = HKQuery.predicateForSamples(withStart: weekStart, end: now, options: [])
        let workouts: [HKWorkout] = (try? await samples(predicate: predicate)) ?? []
        let ours = workouts.filter {
            $0.sourceRevision.source.bundleIdentifier.hasPrefix(bundlePrefix)
        }
        return Set(ours.compactMap {
            DayOfWeek(rawValue: calendar.component(.weekday, from: $0.startDate))
        })
    }

    private func samples(predicate: NSPredicate) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            store.execute(query)
        }
    }
}
