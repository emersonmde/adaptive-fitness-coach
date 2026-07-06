import Foundation
import HealthKit
import AdaptiveCore

/// Phone-side source of one routine's run digests (P6.1) — the LAST WORKOUT section and the
/// Trends screen read through this. Pure aggregation (`RunTrend`) lives in the package; this
/// is only the query, following `HealthSnapshotBuilder`'s pattern (deferred-contextual, every
/// failure = empty, `-uiTesting` never touches HealthKit).
protocol RunHistoryProviding: Sendable {
    /// Dated digests for the routine over the trend window, any order.
    func history(for routineId: UUID) async -> [DatedRunDigest]
}

enum RunHistoryProvider {
    /// `-uiTestInsights` swaps in a canned history (the phone has no HK test seam by design —
    /// the pure/plumbing split keeps everything but the query exercised).
    static func make() -> any RunHistoryProviding {
        ProcessInfo.processInfo.arguments.contains("-uiTestInsights")
            ? CannedRunHistory()
            : HealthRoutineRunHistory()
    }
}

final class HealthRoutineRunHistory: RunHistoryProviding, @unchecked Sendable {
    private let store = HKHealthStore()
    private let bundlePrefix = Bundle.main.bundleIdentifier ?? "—"

    func history(for routineId: UUID) async -> [DatedRunDigest] {
        guard HKHealthStore.isHealthDataAvailable(),
              !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return [] }
        // Window + slack so the "latest session" can predate the 28-day chart window.
        let since = Date().addingTimeInterval(-90 * 86_400)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: since, end: nil),
        ])
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(), predicate: predicate,
                limit: 200, sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
        return workouts.compactMap { workout in
            guard workout.sourceRevision.source.bundleIdentifier.hasPrefix(bundlePrefix),
                  let digest = RunDigest(metadata: Self.stringMetadata(workout.metadata)),
                  digest.routineId == routineId
            else { return nil }
            return DatedRunDigest(date: workout.endDate, digest: digest)
        }
    }

    /// HK metadata is `[String: Any]`; the digest codec is all-string — stringify defensively.
    static func stringMetadata(_ metadata: [String: Any]?) -> [String: String] {
        (metadata ?? [:]).compactMapValues { value in
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }
    }
}

/// Deterministic five-session history for the UI tests / demos: an upward month for any
/// routine id, gate-passing so the baseline suffixes render.
struct CannedRunHistory: RunHistoryProviding {
    func history(for routineId: UUID) async -> [DatedRunDigest] {
        let now = Date()
        func session(_ daysAgo: Int, run: TimeInterval, longest: TimeInterval) -> DatedRunDigest {
            DatedRunDigest(
                date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                digest: RunDigest(routineId: routineId,
                                  runSeconds: run, walkSeconds: 600,
                                  runIntervals: 6, walkIntervals: 5,
                                  longestRunSeconds: longest,
                                  timeInTargetZoneSeconds: run * 0.8,
                                  meanRecoveryDrop: 22,
                                  backOffs: 0, fastRecoveries: 2)
            )
        }
        return [
            session(26, run: 480, longest: 100),
            session(19, run: 540, longest: 120),
            session(12, run: 600, longest: 150),
            session(5, run: 660, longest: 180),
            session(1, run: 780, longest: 240),
        ]
    }
}
