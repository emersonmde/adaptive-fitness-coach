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
    /// Haptic nudges per walk before going quiet — after that the pulsing screen carries it
    /// alone. A cap, not a loop: the app never buzzes indefinitely at a user who has chosen
    /// to keep running (Q5: no nagging).
    public let maxNudges: Int

    private var walkStartedAt: TimeInterval?
    private var lastCadence: (value: Double, at: TimeInterval)?
    private var nudgesSent = 0
    private var lastNudgeAt: TimeInterval?

    public init(
        runningThreshold: Double = 140,
        gracePeriod: TimeInterval = 8,
        staleAfter: TimeInterval = 6,
        nudgeInterval: TimeInterval = 6,
        maxNudges: Int = 3
    ) {
        self.runningThreshold = runningThreshold
        self.gracePeriod = gracePeriod
        self.staleAfter = staleAfter
        self.nudgeInterval = nudgeInterval
        self.maxNudges = maxNudges
    }

    /// A recovery walk began (call on the transition into `.walk`).
    public mutating func walkStarted(at time: TimeInterval) {
        walkStartedAt = time
        nudgesSent = 0
        lastNudgeAt = nil
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
    }

    /// Assess compliance at session-elapsed `time`. Mutating because a granted nudge is
    /// recorded against the cap/rate-limit.
    public mutating func assess(at time: TimeInterval) -> Assessment {
        guard let walkStart = walkStartedAt,
              time - walkStart >= gracePeriod,
              let sample = lastCadence,
              time - sample.at <= staleAfter,
              sample.value >= runningThreshold else {
            return Assessment(isMismatched: false, shouldNudge: false)
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
