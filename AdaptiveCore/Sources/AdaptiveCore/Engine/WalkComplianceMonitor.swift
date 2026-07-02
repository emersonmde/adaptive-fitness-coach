import Foundation

/// Detects "the watch said WALK but the user is still running" from live cadence, so the cue
/// can be repeated by feel and the screen can visibly protest — the real-run failure this
/// fixes is a missed walk haptic followed by a misread glance.
///
/// Deliberately one-directional: only the *overdoing* direction nudges (PRD bias toward
/// backing off). Walking during a run phase never nags — the engine's adaptation already
/// absorbs that, and prodding a tired user to run harder is the one thing this app must
/// never do.
///
/// Pure and clock-free like the other detectors: the caller reports phase changes and
/// cadence samples with session-elapsed timestamps, and polls `assess(at:)` each tick.
public struct WalkComplianceMonitor: Sendable {
    /// Cadence at/above this counts as still running (same bar as run-start detection).
    public let runningThreshold: Double
    /// Seconds after the walk cue before non-compliance can register — time to actually
    /// decelerate (nobody stops on a dime, and the cue itself takes ~1s to play out).
    public let gracePeriod: TimeInterval
    /// A cadence sample older than this says nothing about the current gait.
    public let staleAfter: TimeInterval
    /// Minimum spacing between repeated haptic nudges.
    public let nudgeInterval: TimeInterval
    /// Haptic nudges per walk before the monitor concedes (Q5: no nagging).
    public let maxNudges: Int
    /// Seconds after the last nudge before continued running is *accepted*: the user has
    /// been reminded three times and is still running — that's a decision, not a miss. The
    /// screen calms down, the haptics stay quiet, and the walk is flagged as defied so
    /// progression doesn't misread it as a struggle. This is what keeps the loop from ever
    /// fighting an experienced runner who knows what they're doing.
    public let acceptanceDelay: TimeInterval

    private var walkStartedAt: TimeInterval?
    private var lastCadence: (value: Double, at: TimeInterval)?
    private var nudgesSent = 0
    private var lastNudgeAt: TimeInterval?
    private var acceptedThisWalk = false

    public init(
        runningThreshold: Double = 140,
        gracePeriod: TimeInterval = 8,
        staleAfter: TimeInterval = 6,
        nudgeInterval: TimeInterval = 6,
        maxNudges: Int = 3,
        acceptanceDelay: TimeInterval = 10
    ) {
        self.runningThreshold = runningThreshold
        self.gracePeriod = gracePeriod
        self.staleAfter = staleAfter
        self.nudgeInterval = nudgeInterval
        self.maxNudges = maxNudges
        self.acceptanceDelay = acceptanceDelay
    }

    /// A recovery walk began (call on the transition into `.walk`).
    public mutating func walkStarted(at time: TimeInterval) {
        walkStartedAt = time
        nudgesSent = 0
        lastNudgeAt = nil
        acceptedThisWalk = false
    }

    /// The walk ended (any transition away from `.walk`).
    public mutating func walkEnded() {
        walkStartedAt = nil
    }

    /// Feed a cadence sample (steps/minute) at session-elapsed `time`.
    public mutating func recordCadence(_ cadence: Double, at time: TimeInterval) {
        lastCadence = (cadence, time)
    }

    /// What the caller should do this tick.
    public struct Assessment: Sendable, Equatable {
        /// The user is demonstrably still running during a walk phase — drive the visual pulse.
        public var isMismatched: Bool
        /// Fire a haptic nudge right now (already rate-limited and capped).
        public var shouldNudge: Bool
        /// The full nudge budget was spent and the user is still running: their call. The
        /// pulse stops (`isMismatched` goes false with it), and the caller should record the
        /// walk as defied so progression treats its metrics as a choice, not a struggle.
        public var accepted: Bool

        public init(isMismatched: Bool = false, shouldNudge: Bool = false, accepted: Bool = false) {
            self.isMismatched = isMismatched
            self.shouldNudge = shouldNudge
            self.accepted = accepted
        }
    }

    /// Assess compliance at session-elapsed `time`. Mutating because a granted nudge is
    /// recorded against the cap/rate-limit.
    public mutating func assess(at time: TimeInterval) -> Assessment {
        guard let walkStart = walkStartedAt,
              time - walkStart >= gracePeriod,
              let sample = lastCadence,
              time - sample.at <= staleAfter,
              sample.value >= runningThreshold else {
            return Assessment(accepted: acceptedThisWalk)
        }

        if acceptedThisWalk {
            return Assessment(accepted: true)
        }

        if nudgesSent >= maxNudges, let last = lastNudgeAt, time - last >= acceptanceDelay {
            acceptedThisWalk = true
            return Assessment(accepted: true)
        }

        var nudge = false
        if nudgesSent < maxNudges, lastNudgeAt.map({ time - $0 >= nudgeInterval }) ?? true {
            nudgesSent += 1
            lastNudgeAt = time
            nudge = true
        }
        return Assessment(isMismatched: true, shouldNudge: nudge)
    }
}
