import Foundation

/// A phase change the user should be told about, via a switch haptic and the watch face.
public struct TransitionEvent: Sendable, Equatable {
    public let from: IntervalPhase
    public let to: IntervalPhase

    public init(from: IntervalPhase, to: IntervalPhase) {
        self.from = from
        self.to = to
    }
}

/// The outcome of one `tick`. A tick can produce a phase transition (fire a haptic), an
/// adaptation (show the calm banner), both (a shortened run ends *and* transitions), or
/// neither. `isComplete` becomes true on the tick that finishes the final segment.
public struct TickResult: Sendable, Equatable {
    public var transition: TransitionEvent?
    public var adaptation: AdaptationEvent?
    public var isComplete: Bool

    public init(transition: TransitionEvent? = nil, adaptation: AdaptationEvent? = nil, isComplete: Bool = false) {
        self.transition = transition
        self.adaptation = adaptation
        self.isComplete = isComplete
    }
}

/// Drives a run/walk session forward one tick at a time, applying live adaptation.
///
/// Pure value type: it owns a *working copy* of the plan's segments (so adaptation never
/// mutates the seed plan) and an `AdaptationPolicy`. It takes the classified heart-rate
/// zone as input and emits transitions/adaptations as output. No HealthKit, no clock —
/// the caller supplies `deltaTime`, which makes the whole engine deterministic and testable.
///
/// Passing `currentZone: nil` (zone data unavailable) runs the plan as fixed intervals with
/// no adaptation — the graceful-degradation path (N6).
public struct IntervalStateMachine: Sendable {
    public private(set) var segments: [IntervalSegment]
    public let targetZone: Int
    private var policy: AdaptationPolicy

    public private(set) var currentIndex: Int
    public private(set) var intervalElapsed: TimeInterval
    public private(set) var sessionElapsed: TimeInterval
    public private(set) var isComplete: Bool

    public private(set) var totalRunDuration: TimeInterval
    public private(set) var totalWalkDuration: TimeInterval
    /// Run intervals reached (including those cut short by adaptation — the user still ran them).
    public private(set) var intervalsCompleted: Int
    public private(set) var adaptationsApplied: Int

    /// Non-transition adaptations (extend/lengthen) already surfaced for the current segment,
    /// used to show each banner at most once per segment.
    private var announcedThisSegment: Set<AdaptationAction> = []

    public init(config: SessionConfig, adaptationConfig: AdaptationConfig = AdaptationConfig()) {
        self.segments = config.plan.segments
        self.targetZone = config.targetZone
        self.policy = AdaptationPolicy(config: adaptationConfig)
        self.currentIndex = 0
        self.intervalElapsed = 0
        self.sessionElapsed = 0
        self.isComplete = config.plan.segments.isEmpty
        self.totalRunDuration = 0
        self.totalWalkDuration = 0
        self.intervalsCompleted = 0
        self.adaptationsApplied = 0
    }

    /// The phase currently in progress, or nil once the session is complete.
    public var currentPhase: IntervalPhase? {
        isComplete || segments.isEmpty ? nil : segments[currentIndex].phase
    }

    /// The current segment's working target duration (after any adaptation), or nil if complete.
    public var currentTargetDuration: TimeInterval? {
        isComplete || segments.isEmpty ? nil : segments[currentIndex].targetDuration
    }

    /// Advance the session by `deltaTime` seconds given the live `currentZone` (a 1-based zone
    /// position; see the watch backend's normalization), or nil if zone data is unavailable.
    /// Returns what changed this tick. Callers should tick at roughly ≤1s granularity and clamp
    /// `deltaTime` against background catch-up; a non-positive delta is ignored.
    public mutating func tick(deltaTime: TimeInterval, currentZone: Int?) -> TickResult {
        guard !isComplete, !segments.isEmpty else {
            return TickResult(isComplete: true)
        }
        guard deltaTime > 0 else { return TickResult() }

        intervalElapsed += deltaTime
        sessionElapsed += deltaTime

        let phase = segments[currentIndex].phase
        if phase.isRun {
            totalRunDuration += deltaTime
        } else {
            totalWalkDuration += deltaTime
        }

        // Adaptation only applies to the repeating run/walk intervals, and only when we have
        // a live zone. Warmup/cooldown walks run their fixed seed duration.
        if let zone = currentZone, phase == .run || phase == .walk {
            if let result = adapt(phase: phase, zone: zone, deltaTime: deltaTime) {
                return result
            }
        }

        // Natural transition: the (possibly adapted) target duration has elapsed.
        if intervalElapsed >= segments[currentIndex].targetDuration {
            let transition = advance()
            return TickResult(transition: transition, isComplete: isComplete)
        }

        return TickResult()
    }

    /// Apply the adaptation policy for the current run/walk phase. Returns a `TickResult` if
    /// the policy acted this tick, or nil to fall through to the natural-transition check.
    private mutating func adapt(phase: IntervalPhase, zone: Int, deltaTime: TimeInterval) -> TickResult? {
        let target = segments[currentIndex].targetDuration

        switch phase {
        case .run:
            switch policy.evaluateRun(currentZone: zone, targetZone: targetZone,
                                      intervalElapsed: intervalElapsed, segmentTarget: target, deltaTime: deltaTime) {
            case .shorten:
                let event = AdaptationEvent(action: .shortenedRun, atSessionTime: sessionElapsed, zone: zone)
                adaptationsApplied += 1
                let transition = advance()
                return TickResult(transition: transition, adaptation: event, isComplete: isComplete)
            case .extend:
                // Keep extending the run while the user stays comfortable — a fit runner may
                // run continuously and never reach a walk (per the PRD's vision). The target
                // keeps growing each qualifying tick, but the banner is announced only once per
                // run so the change never nags (Q5).
                segments[currentIndex].targetDuration = target + policy.config.runExtendIncrement
                return announceOnce(.extendedRun, zone: zone)
            case .keepGoing:
                return nil
            }

        case .walk:
            switch policy.evaluateWalk(currentZone: zone, targetZone: targetZone,
                                       intervalElapsed: intervalElapsed, segmentTarget: target, deltaTime: deltaTime) {
            case .shorten:
                let event = AdaptationEvent(action: .shortenedWalk, atSessionTime: sessionElapsed, zone: zone)
                adaptationsApplied += 1
                let transition = advance()
                return TickResult(transition: transition, adaptation: event, isComplete: isComplete)
            case .lengthen:
                guard target < policy.config.maxWalkDuration else { return nil } // at cap → let it transition
                segments[currentIndex].targetDuration = min(target + policy.config.walkLengthenIncrement, policy.config.maxWalkDuration)
                return announceOnce(.lengthenedWalk, zone: zone)
            case .keepGoing:
                return nil
            }

        default:
            return nil
        }
    }

    /// Record a non-transition adaptation (extend/lengthen) and surface its banner at most once
    /// per segment. Subsequent qualifying ticks still adjust the plan but stay silent, so the
    /// run/walk can keep stretching without the banner re-appearing every increment.
    private mutating func announceOnce(_ action: AdaptationAction, zone: Int) -> TickResult {
        guard !announcedThisSegment.contains(action) else { return TickResult() }
        announcedThisSegment.insert(action)
        adaptationsApplied += 1
        return TickResult(adaptation: AdaptationEvent(action: action, atSessionTime: sessionElapsed, zone: zone))
    }

    /// Move to the next segment, or complete the session. Returns the transition for haptics,
    /// or nil when the session completes (signaled via `isComplete`).
    private mutating func advance() -> TransitionEvent? {
        let fromPhase = segments[currentIndex].phase
        if fromPhase.isRun {
            intervalsCompleted += 1
        }

        let nextIndex = currentIndex + 1
        guard nextIndex < segments.count else {
            isComplete = true
            return nil
        }

        currentIndex = nextIndex
        intervalElapsed = 0
        policy.resetAccumulators()
        announcedThisSegment.removeAll()
        return TransitionEvent(from: fromPhase, to: segments[currentIndex].phase)
    }
}
