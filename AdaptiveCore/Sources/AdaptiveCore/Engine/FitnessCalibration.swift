import Foundation

/// Zero-configuration cold start: infer starting run/walk seeds from what Apple Health
/// already knows about the user, so nobody is asked "how fit are you?" — the experienced
/// runner's first session is already a normal run, and a true beginner gets the
/// conservative build-up. The mapping is deliberately coarse (three tiers): it only picks
/// the *starting* rung, and the in-session evidence gate plus cross-session progression do
/// the fine adjustment either way, so a wrong tier costs at most a session (N7).
public enum FitnessCalibration {

    /// One prior running workout read from Health: how long it lasted and how far it went.
    public struct PriorRun: Sendable, Hashable {
        public var duration: TimeInterval
        public var distanceMeters: Double?

        public init(duration: TimeInterval, distanceMeters: Double? = nil) {
            self.duration = duration
            self.distanceMeters = distanceMeters
        }
    }

    /// The default seeds for a user with no signal at all.
    public static let beginnerSeeds = RunSeeds(runSeconds: 90, walkSeconds: 120)
    /// Some running history / decent VO2max: 5-minute intervals with short recoveries.
    public static let intermediateSeeds = RunSeeds(runSeconds: 300, walkSeconds: 90)
    /// A demonstrated regular runner: effectively continuous (the plan factory turns a run
    /// seed that covers the block into a single run segment).
    public static let continuousSeeds = RunSeeds(runSeconds: 3600, walkSeconds: 60)

    /// Map Health history to starting seeds.
    ///
    /// Signals, in order of trust:
    /// - **Recent running workouts** (last ~90 days): actual behavior. A "real run" is one
    ///   sustaining ≥ 7 min at a running pace (< 9 min/km when distance is known; duration
    ///   alone when it isn't, since a logged *running* workout at unknown pace is still a
    ///   deliberate run). Three or more with the longest ≥ 20 min → continuous. Any real
    ///   run at all → intermediate.
    /// - **VO2max** (Apple's estimate, updates after outdoor walks/runs): physiology when
    ///   behavior is absent. ≥ 42 mL/kg/min (roughly "good" for middle-aged adults per the
    ///   Cooper Institute bands Apple's Cardio Fitness categories are based on) → intermediate,
    ///   not continuous — capacity without recent running practice shouldn't skip the
    ///   musculoskeletal build-up entirely.
    /// - Nothing → beginner.
    public static func seeds(vo2Max: Double?, recentRuns: [PriorRun]) -> RunSeeds {
        let realRuns = recentRuns.filter { isRealRun($0) }

        if realRuns.count >= 3, realRuns.contains(where: { $0.duration >= 20 * 60 }) {
            return continuousSeeds
        }
        if !realRuns.isEmpty {
            return intermediateSeeds
        }
        if let vo2Max, vo2Max >= 42 {
            return intermediateSeeds
        }
        return beginnerSeeds
    }

    /// A workout that shows sustained running: ≥ 7 minutes, and — when distance is known —
    /// a pace better than 9 min/km (slower than that over a whole workout is walking).
    private static func isRealRun(_ run: PriorRun) -> Bool {
        guard run.duration >= 7 * 60 else { return false }
        guard let distance = run.distanceMeters, distance > 0 else { return true }
        let minutesPerKm = (run.duration / 60) / (distance / 1000)
        return minutesPerKm < 9
    }
}
