import Foundation

/// Tunable thresholds for the adaptation policy. Defaults encode the P1 design.
///
/// Runs are **back-off only** by default: heart-rate lag in deconditioned runners reads as
/// comfort for the first 1–2 minutes of a run, so "HR looks fine → run longer" extends runs
/// exactly when the user is fading (observed on the first real-world run). Extension survives
/// behind `allowRunExtension` for a future mode where the user's HR response is trusted.
///
/// Walks end on **recovery**, not a timer: the walk completes once heart rate has dropped
/// `recoveryDropBPM` from the run's peak (heart-rate recovery — HRR — a validated autonomic
/// readiness marker; Cole et al., NEJM 1999: <12 bpm drop in the first minute is the clinical
/// risk cutoff, so 20 bpm targets comfortable readiness) or the zone has fallen below target.
/// A wrong default still self-corrects because the seed durations bend to the body, not the
/// other way around (N7), and every asymmetry biases toward backing off.
public struct AdaptationConfig: Sendable, Hashable {
    /// Sustained seconds above target zone before a run is cut short. Shorter = quicker to ease off.
    public var backOffWindow: TimeInterval
    /// Sustained seconds far above target (`hardBackOffZoneDelta` or more over) before a run is
    /// cut short regardless of `backOffWindow` — the "genuinely redlining" fast path.
    public var hardBackOffWindow: TimeInterval
    /// How many zones above target counts as far above (2 → zone 4+ against a zone-2 target).
    public var hardBackOffZoneDelta: Int
    /// A run must last at least this long before the hard ceiling can end it.
    public var hardBackOffMinRun: TimeInterval
    /// Whether a comfortable run may always be extended past its planned end. Off by default
    /// (see above); independent of the per-session evidence gate the caller can pass to
    /// `evaluateRun(extensionUnlocked:)` once demonstrated recovery has earned it.
    public var allowRunExtension: Bool
    /// Sustained seconds at/below target zone before a run is extended (when extension is
    /// permitted by config or by the evidence gate).
    public var extendWindow: TimeInterval
    /// Sustained seconds recovered before a walk is ended early.
    public var recoverWindow: TimeInterval
    /// Heart-rate drop from the preceding run's peak that counts as recovered.
    public var recoveryDropBPM: Double
    /// A run must last at least this long before it can be shortened by `backOffWindow`.
    public var minRunDuration: TimeInterval
    /// A walk always lasts at least this long, so run/walk cues never yo-yo.
    public var minWalkDuration: TimeInterval
    /// Seconds added to a run each time it is extended.
    public var runExtendIncrement: TimeInterval
    /// Seconds added to a walk each time it is lengthened.
    public var walkLengthenIncrement: TimeInterval
    /// A walk is never lengthened beyond this total, to avoid an unbounded walk if HR never recovers.
    public var maxWalkDuration: TimeInterval
    /// Granularity future-segment convergence rounds to (runs round down — never credit
    /// undemonstrated seconds; walks round up — longer walks are the safe direction).
    public var convergenceRounding: TimeInterval
    /// Hard cap on how far one upward convergence event may raise a future run's target.
    /// A relative +25% bound applies alongside; the smaller wins. Single-session load spikes
    /// are the injury driver (sessions ≥10% beyond the recent longest raise risk), so upward
    /// convergence is slew-limited while downward converges in one jump (N7 bias).
    /// Source: 5,200-runner cohort — session-specific overdistance, not weekly progression,
    /// predicted overuse injury (Br J Sports Med 2025; PMC12421110).
    public var maxUpwardConvergenceStep: TimeInterval
    /// Consecutive struggled run intervals (a back-off with no fast recovery since) before the
    /// session converts its remaining run/walk block to one continuous easy walk. The evidence
    /// ladder for a struggling beginner is *slow → shorten → walk*: keep offering shortened
    /// run attempts while recovery keeps returning, but after this many failures in a row —
    /// recovery genuinely not coming back — make a single decisive switch to sub-threshold
    /// walking rather than push more run attempts (which delays autonomic recovery and reads as
    /// homogeneously unpleasant above the ventilatory threshold, hurting adherence). A fast
    /// recovery resets the count: a lone back-off is the live loop calibrating a too-long seed,
    /// not a failure. Source: convergent beginner-coaching consensus (NHS C25K, Galloway,
    /// ACSM-credentialed coaches) + Dual-Mode affect theory (Ekkekakis) + VT1 autonomic-recovery
    /// physiology (Seiler 2007); deep-research synthesis 2026-07-16. No primary novice trial
    /// tests the exact cap, so it is deliberately forgiving (3, not 2) — keep trying to run.
    public var struggleCap: Int

    public init(
        backOffWindow: TimeInterval = 20,
        hardBackOffWindow: TimeInterval = 8,
        hardBackOffZoneDelta: Int = 2,
        hardBackOffMinRun: TimeInterval = 15,
        allowRunExtension: Bool = false,
        extendWindow: TimeInterval = 45,
        recoverWindow: TimeInterval = 10,
        recoveryDropBPM: Double = 20,
        minRunDuration: TimeInterval = 20,
        minWalkDuration: TimeInterval = 60,
        runExtendIncrement: TimeInterval = 30,
        walkLengthenIncrement: TimeInterval = 15,
        maxWalkDuration: TimeInterval = 300,
        convergenceRounding: TimeInterval = 15,
        maxUpwardConvergenceStep: TimeInterval = 30,
        struggleCap: Int = 3
    ) {
        self.backOffWindow = backOffWindow
        self.hardBackOffWindow = hardBackOffWindow
        self.hardBackOffZoneDelta = hardBackOffZoneDelta
        self.hardBackOffMinRun = hardBackOffMinRun
        self.allowRunExtension = allowRunExtension
        self.extendWindow = extendWindow
        self.recoverWindow = recoverWindow
        self.recoveryDropBPM = recoveryDropBPM
        self.minRunDuration = minRunDuration
        self.minWalkDuration = minWalkDuration
        self.runExtendIncrement = runExtendIncrement
        self.walkLengthenIncrement = walkLengthenIncrement
        self.maxWalkDuration = maxWalkDuration
        self.convergenceRounding = convergenceRounding
        self.maxUpwardConvergenceStep = maxUpwardConvergenceStep
        self.struggleCap = struggleCap
    }
}

/// What to do with the current run, evaluated each tick.
public enum RunDecision: Sendable, Equatable {
    /// Keep running the planned duration.
    case keepGoing
    /// End the run now — HR has run hot for a sustained window.
    case shorten
    /// Push past the planned end — HR has stayed comfortable for a sustained window
    /// (only reachable with `allowRunExtension`).
    case extend
}

/// What to do with the current walk, evaluated each tick.
public enum WalkDecision: Sendable, Equatable {
    /// Keep walking the planned duration.
    case keepGoing
    /// Walk longer than planned — HR has not recovered by the planned end.
    case lengthen
    /// End the walk now — HR recovered.
    case shorten
}

/// Decides, tick by tick, whether to adjust the current run or walk from the live signals.
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
    /// Sustained time the current zone has been far above target (hard-ceiling accumulator).
    private var timeFarAboveTarget: TimeInterval = 0
    /// Sustained time the walk-recovery signal has read "recovered".
    private var timeRecovered: TimeInterval = 0

    public init(config: AdaptationConfig = AdaptationConfig()) {
        self.config = config
    }

    /// Clear sustained-time accumulators. Call at the start of every new segment.
    public mutating func resetAccumulators() {
        timeAboveTarget = 0
        timeAtOrBelowTarget = 0
        timeFarAboveTarget = 0
        timeRecovered = 0
    }

    /// Advance one leaky-integrator accumulator: the active side accrues `deltaTime`, the
    /// opposite side *decays* by `deltaTime` rather than resetting to zero. This is the
    /// hysteresis that makes "sustained" robust to flapping — a brief 1–2s excursion across a
    /// boundary (common as HR rides the Zone 2/3 line) only costs a couple of seconds off a
    /// nearly-complete window instead of wiping it, while a genuinely sustained excursion still
    /// drives the opposite side to zero. This honors the PRD's "smoothed/sustained, never a
    /// single reading" constraint at the decision layer.
    private static func integrate(_ accumulator: inout TimeInterval, active: Bool, deltaTime: TimeInterval) {
        accumulator = active ? accumulator + deltaTime : max(0, accumulator - deltaTime)
    }

    /// Evaluate the current run interval.
    ///
    /// Backing off has priority and can fire mid-run — a fast path for far-above-target
    /// (redlining) and the standard sustained-above window. Extending is only considered once
    /// the planned duration is reached, requires a longer confirming window, and is gated:
    /// off by config default (`allowRunExtension`) because in-run zone comfort is untrustworthy
    /// under HR lag, but the session can unlock it with `extensionUnlocked` once *demonstrated
    /// recovery* (a walk ended at the floor with a full HRR drop) has proven the user is fitter
    /// than the seeds — evidence-based, so a mis-seeded fit runner converges toward continuous
    /// running within one session while a struggling one never extends.
    public mutating func evaluateRun(
        currentZone: Int,
        targetZone: Int,
        intervalElapsed: TimeInterval,
        segmentTarget: TimeInterval,
        deltaTime: TimeInterval,
        extensionUnlocked: Bool = false
    ) -> RunDecision {
        let above = currentZone > targetZone
        Self.integrate(&timeAboveTarget, active: above, deltaTime: deltaTime)
        Self.integrate(&timeAtOrBelowTarget, active: !above, deltaTime: deltaTime)
        Self.integrate(&timeFarAboveTarget,
                       active: currentZone >= targetZone + config.hardBackOffZoneDelta,
                       deltaTime: deltaTime)

        if timeFarAboveTarget >= config.hardBackOffWindow, intervalElapsed >= config.hardBackOffMinRun {
            return .shorten
        }

        if timeAboveTarget >= config.backOffWindow, intervalElapsed >= config.minRunDuration {
            return .shorten
        }

        if config.allowRunExtension || extensionUnlocked,
           intervalElapsed >= segmentTarget, timeAtOrBelowTarget >= config.extendWindow {
            return .extend
        }

        return .keepGoing
    }

    /// Evaluate the current walk interval against the recovery signal.
    ///
    /// "Recovered" means heart rate has dropped `recoveryDropBPM` from the preceding run's
    /// peak (HRR) **or** the zone has fallen strictly below target — whichever signal is
    /// available. With neither signal the walk holds its planned duration (N6).
    ///
    /// Ending a walk early raises effort, so it needs a sustained confirming window
    /// (`recoverWindow`) *and* the `minWalkDuration` floor. Lengthening is the conservative
    /// direction and fires as soon as the planned end is reached while still unrecovered.
    public mutating func evaluateWalk(
        currentZone: Int?,
        heartRate: Double?,
        peakRunHeartRate: Double?,
        targetZone: Int,
        intervalElapsed: TimeInterval,
        segmentTarget: TimeInterval,
        deltaTime: TimeInterval
    ) -> WalkDecision {
        guard let recovered = isRecovered(zone: currentZone, heartRate: heartRate,
                                          peakRunHeartRate: peakRunHeartRate, targetZone: targetZone) else {
            // A signal gap never proves recovery (N6): leak the accumulator down exactly as
            // a not-recovered reading would, so credit earned before a dropout can't end
            // the walk on one post-gap tick. (Freezing it here was the one place stale
            // evidence survived a gap.)
            Self.integrate(&timeRecovered, active: false, deltaTime: deltaTime)
            return .keepGoing
        }

        Self.integrate(&timeRecovered, active: recovered, deltaTime: deltaTime)

        if timeRecovered >= config.recoverWindow, intervalElapsed >= config.minWalkDuration {
            return .shorten
        }

        if intervalElapsed >= segmentTarget, !recovered {
            return .lengthen
        }

        return .keepGoing
    }

    /// The instantaneous recovery signal, or nil when no usable signal exists this tick.
    private func isRecovered(zone: Int?, heartRate: Double?, peakRunHeartRate: Double?, targetZone: Int) -> Bool? {
        var signals: [Bool] = []
        if let hr = heartRate, let peak = peakRunHeartRate {
            signals.append(peak - hr >= config.recoveryDropBPM)
        }
        if let zone {
            signals.append(zone < targetZone)
        }
        guard !signals.isEmpty else { return nil }
        return signals.contains(true)
    }
}
