import Foundation

/// The app-specific record of one run, written as custom metadata on the saved `HKWorkout`
/// (P6.1). **Health itself is the store** — no private file, no TTL: deleting the workout
/// deletes the digest, and both devices read history back through their existing our-workouts
/// queries. This is what makes "vs last run" / "vs 28-day baseline" and the phone trends
/// possible without violating N2 (the interval semantics aren't health samples; they're
/// annotations on the one real workout record).
///
/// All-string metadata values: HK metadata accepts strings losslessly, and an all-string
/// codec keeps this type pure (no HealthKit import) and round-trip-testable on macOS.
/// `AFCDigestVersion` gates decoding — a future shape change bumps it and old readers
/// simply see no digest (honest absence, never a mis-read).
public struct RunDigest: Sendable, Hashable {
    public var routineId: UUID?
    public var runSeconds: TimeInterval
    public var walkSeconds: TimeInterval
    public var runIntervals: Int
    public var walkIntervals: Int
    public var longestRunSeconds: TimeInterval
    public var timeInTargetZoneSeconds: TimeInterval
    /// Mean heart-rate recovery drop (bpm); omitted from metadata when nil (N6 — a sensor
    /// gap must never round-trip into a fabricated 0).
    public var meanRecoveryDrop: Double?
    public var backOffs: Int
    public var fastRecoveries: Int
    /// The session was ended by hand before completing. Aborts still save to Health (N2)
    /// but must not become comparison baselines — a 20-second bail would inflate the next
    /// real run's "vs last run" and drag the 28-day mean.
    public var endedEarly: Bool

    public init(
        routineId: UUID? = nil,
        runSeconds: TimeInterval = 0,
        walkSeconds: TimeInterval = 0,
        runIntervals: Int = 0,
        walkIntervals: Int = 0,
        longestRunSeconds: TimeInterval = 0,
        timeInTargetZoneSeconds: TimeInterval = 0,
        meanRecoveryDrop: Double? = nil,
        backOffs: Int = 0,
        fastRecoveries: Int = 0,
        endedEarly: Bool = false
    ) {
        self.routineId = routineId
        self.runSeconds = runSeconds
        self.walkSeconds = walkSeconds
        self.runIntervals = runIntervals
        self.walkIntervals = walkIntervals
        self.longestRunSeconds = longestRunSeconds
        self.timeInTargetZoneSeconds = timeInTargetZoneSeconds
        self.meanRecoveryDrop = meanRecoveryDrop
        self.backOffs = backOffs
        self.fastRecoveries = fastRecoveries
        self.endedEarly = endedEarly
    }

    public init(summary: SessionSummary, routineId: UUID?) {
        self.init(
            routineId: routineId,
            runSeconds: summary.totalRunDuration,
            walkSeconds: summary.totalWalkDuration,
            runIntervals: summary.intervalsCompleted,
            walkIntervals: summary.walksCompleted,
            longestRunSeconds: summary.longestRunSeconds,
            timeInTargetZoneSeconds: summary.timeInTargetZone,
            meanRecoveryDrop: summary.meanRecoveryDrop,
            backOffs: summary.runBackOffCount,
            fastRecoveries: summary.fastRecoveries,
            endedEarly: summary.endedEarly
        )
    }

    /// Fraction of moving interval time spent running (0…1), or nil when nothing was tracked.
    public var runFraction: Double? {
        let total = runSeconds + walkSeconds
        guard total > 0 else { return nil }
        return runSeconds / total
    }

    // MARK: - Metadata codec

    public enum Key {
        public static let version = "AFCDigestVersion"
        public static let routineID = "AFCRoutineID"
        public static let runSeconds = "AFCRunSeconds"
        public static let walkSeconds = "AFCWalkSeconds"
        public static let runIntervals = "AFCRunIntervals"
        public static let walkIntervals = "AFCWalkIntervals"
        public static let longestRunSeconds = "AFCLongestRunSeconds"
        public static let timeInTargetZone = "AFCTimeInTargetZoneSeconds"
        public static let meanRecoveryDrop = "AFCMeanRecoveryDrop"
        public static let backOffs = "AFCBackOffs"
        public static let fastRecoveries = "AFCFastRecoveries"
        public static let endedEarly = "AFCEndedEarly"
    }

    /// Still "1": `endedEarly` is an additive optional key whose absence decodes as false —
    /// bumping the version would make every pre-existing digest read as "no digest" and
    /// erase the user's comparison history for a field old digests can't carry anyway.
    public static let currentVersion = "1"

    public func metadata() -> [String: String] {
        var dict: [String: String] = [
            Key.version: Self.currentVersion,
            Key.runSeconds: String(Int(runSeconds.rounded())),
            Key.walkSeconds: String(Int(walkSeconds.rounded())),
            Key.runIntervals: String(runIntervals),
            Key.walkIntervals: String(walkIntervals),
            Key.longestRunSeconds: String(Int(longestRunSeconds.rounded())),
            Key.timeInTargetZone: String(Int(timeInTargetZoneSeconds.rounded())),
            Key.backOffs: String(backOffs),
            Key.fastRecoveries: String(fastRecoveries),
        ]
        if endedEarly { dict[Key.endedEarly] = "1" }
        if let routineId { dict[Key.routineID] = routineId.uuidString }
        if let meanRecoveryDrop {
            dict[Key.meanRecoveryDrop] = String(format: "%.1f", meanRecoveryDrop)
        }
        return dict
    }

    /// Decode from workout metadata. nil unless the version key parses as one we understand —
    /// non-digest workouts (pre-feature history, other apps) simply read as "no digest".
    /// Individual malformed values decode as absent/zero, never as invented numbers.
    public init?(metadata: [String: String]) {
        guard metadata[Key.version] == Self.currentVersion else { return nil }
        self.init(
            routineId: metadata[Key.routineID].flatMap(UUID.init(uuidString:)),
            runSeconds: metadata[Key.runSeconds].flatMap(TimeInterval.init) ?? 0,
            walkSeconds: metadata[Key.walkSeconds].flatMap(TimeInterval.init) ?? 0,
            runIntervals: metadata[Key.runIntervals].flatMap(Int.init) ?? 0,
            walkIntervals: metadata[Key.walkIntervals].flatMap(Int.init) ?? 0,
            longestRunSeconds: metadata[Key.longestRunSeconds].flatMap(TimeInterval.init) ?? 0,
            timeInTargetZoneSeconds: metadata[Key.timeInTargetZone].flatMap(TimeInterval.init) ?? 0,
            meanRecoveryDrop: metadata[Key.meanRecoveryDrop].flatMap(Double.init),
            backOffs: metadata[Key.backOffs].flatMap(Int.init) ?? 0,
            fastRecoveries: metadata[Key.fastRecoveries].flatMap(Int.init) ?? 0,
            endedEarly: metadata[Key.endedEarly] == "1"
        )
    }
}
