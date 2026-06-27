import Foundation

/// Tunable thresholds for the adaptation policy. Defaults encode the P0 design.
///
/// The asymmetry between `backOffWindow` and `extendWindow` is where the
/// "bias toward backing off over extending" constraint lives: backing off needs only a
/// short confirming window and can fire mid-run, while extending effort (longer run,
/// shorter walk) requires a longer confirming window. A wrong default still self-corrects
/// because the seed durations bend to the body, not the other way around (N7).
public struct AdaptationConfig: Sendable, Hashable {
    /// Sustained seconds above target zone before a run is cut short. Shorter = quicker to ease off.
    public var backOffWindow: TimeInterval
    /// Sustained seconds at/below target zone before a run is extended past its planned end.
    public var extendWindow: TimeInterval
    /// Sustained seconds recovered (at/below target) before a walk is ended early.
    public var recoverWindow: TimeInterval
    /// A run must last at least this long before it can be shortened.
    public var minRunDuration: TimeInterval
    /// A walk must last at least this long before it can be shortened.
    public var minWalkDuration: TimeInterval
    /// Seconds added to a run each time it is extended.
    public var runExtendIncrement: TimeInterval
    /// Seconds added to a walk each time it is lengthened.
    public var walkLengthenIncrement: TimeInterval
    /// A walk is never lengthened beyond this total, to avoid an unbounded walk if HR never recovers.
    public var maxWalkDuration: TimeInterval

    public init(
        backOffWindow: TimeInterval = 20,
        extendWindow: TimeInterval = 45,
        recoverWindow: TimeInterval = 30,
        minRunDuration: TimeInterval = 20,
        minWalkDuration: TimeInterval = 15,
        runExtendIncrement: TimeInterval = 30,
        walkLengthenIncrement: TimeInterval = 15,
        maxWalkDuration: TimeInterval = 300
    ) {
        self.backOffWindow = backOffWindow
        self.extendWindow = extendWindow
        self.recoverWindow = recoverWindow
        self.minRunDuration = minRunDuration
        self.minWalkDuration = minWalkDuration
        self.runExtendIncrement = runExtendIncrement
        self.walkLengthenIncrement = walkLengthenIncrement
        self.maxWalkDuration = maxWalkDuration
    }
}

/// What to do with the current run, evaluated each tick.
public enum RunDecision: Sendable, Equatable {
    /// Keep running the planned duration.
    case keepGoing
    /// End the run now — HR has run hot for a sustained window.
    case shorten
    /// Push past the planned end — HR has stayed comfortable for a sustained window.
    case extend
}

/// What to do with the current walk, evaluated each tick.
public enum WalkDecision: Sendable, Equatable {
    /// Keep walking the planned duration.
    case keepGoing
    /// Walk longer than planned — HR has not recovered by the planned end.
    case lengthen
    /// End the walk now — HR recovered quickly.
    case shorten
}

/// Decides, tick by tick, whether to adjust the current run or walk based on the live
/// heart-rate zone Apple classifies during the workout.
///
/// The policy is a pure value type holding only time accumulators, so it is fully
/// deterministic and unit-testable without HealthKit or a clock. The owning state machine
/// applies the decisions to a working copy of the plan and calls `resetAccumulators()`
/// whenever a new segment begins.
public struct AdaptationPolicy: Sendable {
    public let config: AdaptationConfig

    /// Sustained time the current zone has been above the target zone.
    private var timeAboveTarget: TimeInterval = 0
    /// Sustained time the current zone has been at or below the target zone.
    private var timeAtOrBelowTarget: TimeInterval = 0

    public init(config: AdaptationConfig = AdaptationConfig()) {
        self.config = config
    }

    /// Clear sustained-time accumulators. Call at the start of every new segment.
    public mutating func resetAccumulators() {
        timeAboveTarget = 0
        timeAtOrBelowTarget = 0
    }

    /// Advance the sustained-time accumulators for this tick using a leaky integrator: the
    /// active side accrues `deltaTime`, the opposite side *decays* by `deltaTime` rather than
    /// resetting to zero. This is the hysteresis that makes "sustained" robust to flapping —
    /// a brief 1–2s excursion across the zone boundary (common as HR rides the Zone 2/3 line)
    /// only costs a couple of seconds off a nearly-complete window instead of wiping it, while
    /// a genuinely sustained excursion still drives the opposite side to zero. This honors the
    /// PRD's "smoothed/sustained, never a single reading" constraint at the decision layer even
    /// though the zone itself is Apple's already-classified signal.
    private mutating func accumulate(currentZone: Int, targetZone: Int, deltaTime: TimeInterval) {
        if currentZone > targetZone {
            timeAboveTarget += deltaTime
            timeAtOrBelowTarget = max(0, timeAtOrBelowTarget - deltaTime)
        } else {
            timeAtOrBelowTarget += deltaTime
            timeAboveTarget = max(0, timeAboveTarget - deltaTime)
        }
    }

    /// Evaluate the current run interval.
    ///
    /// Backing off has priority and can fire mid-run; extending is only considered once the
    /// planned duration is reached and requires a longer confirming window.
    public mutating func evaluateRun(
        currentZone: Int,
        targetZone: Int,
        intervalElapsed: TimeInterval,
        segmentTarget: TimeInterval,
        deltaTime: TimeInterval
    ) -> RunDecision {
        accumulate(currentZone: currentZone, targetZone: targetZone, deltaTime: deltaTime)

        if timeAboveTarget >= config.backOffWindow, intervalElapsed >= config.minRunDuration {
            return .shorten
        }

        if intervalElapsed >= segmentTarget, timeAtOrBelowTarget >= config.extendWindow {
            return .extend
        }

        return .keepGoing
    }

    /// Evaluate the current walk interval.
    ///
    /// Cutting a walk short raises effort, so it requires a longer confirming window
    /// (`recoverWindow`). Lengthening a walk is the conservative direction and fires as soon
    /// as the planned end is reached with HR still above target.
    public mutating func evaluateWalk(
        currentZone: Int,
        targetZone: Int,
        intervalElapsed: TimeInterval,
        segmentTarget: TimeInterval,
        deltaTime: TimeInterval
    ) -> WalkDecision {
        accumulate(currentZone: currentZone, targetZone: targetZone, deltaTime: deltaTime)

        if timeAtOrBelowTarget >= config.recoverWindow, intervalElapsed >= config.minWalkDuration {
            return .shorten
        }

        if intervalElapsed >= segmentTarget, currentZone > targetZone {
            return .lengthen
        }

        return .keepGoing
    }
}
