import Foundation
import HealthKit
import AdaptiveCore

/// Reads back this routine's run digests from Health for the summary's comparison lines
/// (P6.1). Pure decision logic (`RunComparison`) lives in the package; this file is only the
/// HealthKit plumbing — the `HealthFitnessCalibrator` split, exactly.
///
/// History = our own saved running workouts whose metadata carries a decodable `RunDigest`
/// attributed to the routine. Pre-feature workouts have no digest and simply don't appear;
/// failure of any kind yields empty history and the summary's comparison slot stays silent
/// (N6 — no number is better than a fabricated one).
@MainActor
enum HealthRunDigestReader {

    struct History: Sendable {
        /// All prior digests of this routine (any age), **newest-first** — the shape
        /// `RunComparison.lastComparable(in:)` expects for picking the last non-abort run.
        var all: [DatedRunDigest] = []
        /// This routine's digests inside the 28-day baseline window, oldest to newest.
        var window: [DatedRunDigest]
    }

    /// All digest-bearing runs of `routineId` that ended before `sessionStart` (the
    /// just-finished workout also carries a digest — it must not compare against itself).
    static func history(routineId: UUID?, before sessionStart: Date) async -> History {
        guard let routineId, HealthKitAuthorization.isAvailable else { return History(window: []) }
        let bundlePrefix = Bundle.main.bundleIdentifier?
            .replacingOccurrences(of: ".watchkitapp", with: "") ?? "—"

        let since = sessionStart.addingTimeInterval(
            -Double(RunComparison.baselineWindowDays + 62) * 86_400)   // window + slack for "previous"
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: since, end: sessionStart),
        ])

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(), predicate: predicate,
                limit: 100,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            HealthKitAuthorization.healthStore.execute(query)
        }

        let dated: [DatedRunDigest] = workouts.compactMap { workout in
            guard workout.sourceRevision.source.bundleIdentifier.hasPrefix(bundlePrefix),
                  workout.endDate < sessionStart,
                  let digest = RunDigest(metadata: stringMetadata(workout.metadata)),
                  digest.routineId == routineId
            else { return nil }
            return DatedRunDigest(date: workout.endDate, digest: digest)
        }

        let windowStart = sessionStart.addingTimeInterval(
            -Double(RunComparison.baselineWindowDays) * 86_400)
        return History(
            all: dated.reversed(),
            window: dated.filter { $0.date >= windowStart }
        )
    }

    /// HK metadata is `[String: Any]`; the digest codec is all-string. Stringify defensively —
    /// numbers written by a future build (or mangled in sync) still decode.
    static func stringMetadata(_ metadata: [String: Any]?) -> [String: String] {
        (metadata ?? [:]).compactMapValues { value in
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }
    }
}
