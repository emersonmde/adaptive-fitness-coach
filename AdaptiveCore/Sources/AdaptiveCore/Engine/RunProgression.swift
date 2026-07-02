import Foundation

/// How one run/walk session went, distilled to the signals progression cares about.
/// Built from the engine's counters (via `SessionSummary`) when a session ends.
public struct RunSessionOutcome: Sendable, Hashable {
    /// Run intervals the plan called for.
    public var plannedRunIntervals: Int
    /// Run intervals actually reached (including ones cut short — the user still ran them).
    public var completedRunIntervals: Int
    /// Runs the engine cut short because HR ran hot.
    public var runBackOffCount: Int
    /// Walks that hit the max-walk cap still unrecovered.
    public var walksHitCap: Int
    /// Mean heart-rate recovery drop (bpm) across walks, nil when HR was unavailable.
    public var meanRecoveryDrop: Double?
    /// True when the user ended the workout before the plan finished.
    public var endedEarly: Bool

    public init(
        plannedRunIntervals: Int,
        completedRunIntervals: Int,
        runBackOffCount: Int,
        walksHitCap: Int,
        meanRecoveryDrop: Double? = nil,
        endedEarly: Bool = false
    ) {
        self.plannedRunIntervals = plannedRunIntervals
        self.completedRunIntervals = completedRunIntervals
        self.runBackOffCount = runBackOffCount
        self.walksHitCap = walksHitCap
        self.meanRecoveryDrop = meanRecoveryDrop
        self.endedEarly = endedEarly
    }

    public init(summary: SessionSummary) {
        self.init(
            plannedRunIntervals: summary.plannedRunIntervals,
            completedRunIntervals: summary.intervalsCompleted,
            runBackOffCount: summary.runBackOffCount,
            walksHitCap: summary.walksHitCap,
            meanRecoveryDrop: summary.meanRecoveryDrop,
            endedEarly: summary.endedEarly
        )
    }
}

/// The run/walk interval seeds a run card carries between sessions.
public struct RunSeeds: Sendable, Hashable {
    public var runSeconds: Int
    public var walkSeconds: Int

    public init(runSeconds: Int, walkSeconds: Int) {
        self.runSeconds = runSeconds
        self.walkSeconds = walkSeconds
    }
}

/// Turns a session outcome into next session's seeds — the cross-session half of "adaptive"
/// (N7: defaults are self-correcting seeds, now across workouts, not just within one).
///
/// The rules are deliberately conservative in the effort direction (PRD bias toward backing
/// off): advancing needs a fully clean session, regressing needs a clear struggle, anything
/// ambiguous holds. Each step is small enough that a wrong move self-corrects next session.
public struct RunProgressionPolicy: Sendable {
    /// Seconds a clean session adds to the run seed: a quarter of the current seed, at least
    /// 15s, at most 60s — fast early gains (90 → 112 → 140…), gentler as runs get long.
    public var maxAdvanceStep: Int
    /// Seconds removed from the run seed after a struggle.
    public var regressStep: Int
    /// Run seed bounds. The floor keeps an interval meaningful; there is no ceiling — the
    /// plan factory turns a seed that covers the whole block into continuous running.
    public var minRunSeconds: Int
    /// Walk seed bounds. The walk only starts shrinking once runs reach `walkShrinkThreshold`
    /// (shrinking both dimensions at once would double the difficulty jump).
    public var minWalkSeconds: Int
    public var maxWalkSeconds: Int
    public var walkShrinkThreshold: Int
    /// Back-offs at/above this count regress (2+ cut-short runs is a pattern, not a blip).
    public var regressBackOffCount: Int

    public init(
        maxAdvanceStep: Int = 60,
        regressStep: Int = 15,
        minRunSeconds: Int = 30,
        minWalkSeconds: Int = 60,
        maxWalkSeconds: Int = 180,
        walkShrinkThreshold: Int = 180,
        regressBackOffCount: Int = 2
    ) {
        self.maxAdvanceStep = maxAdvanceStep
        self.regressStep = regressStep
        self.minRunSeconds = minRunSeconds
        self.minWalkSeconds = minWalkSeconds
        self.maxWalkSeconds = maxWalkSeconds
        self.walkShrinkThreshold = walkShrinkThreshold
        self.regressBackOffCount = regressBackOffCount
    }

    /// Next session's seeds given this session's outcome.
    public func nextSeeds(current: RunSeeds, outcome: RunSessionOutcome) -> RunSeeds {
        var seeds = current

        if isStruggle(outcome) {
            seeds.runSeconds = max(minRunSeconds, current.runSeconds - regressStep)
            seeds.walkSeconds = min(maxWalkSeconds, current.walkSeconds + regressStep)
        } else if isClean(outcome) {
            let step = min(maxAdvanceStep, max(15, current.runSeconds / 4))
            seeds.runSeconds = current.runSeconds + step
            if seeds.runSeconds >= walkShrinkThreshold {
                seeds.walkSeconds = max(minWalkSeconds, current.walkSeconds - 15)
            }
        }
        // Anything in between: hold. A held seed is a fine seed (N7).

        return seeds
    }

    /// A clean session: every planned run reached, none cut short, no walk pinned at the cap.
    /// (Recovery quality is already encoded in walk behavior — a slow recoverer lengthens
    /// walks or hits the cap, so `meanRecoveryDrop` isn't double-counted here.)
    private func isClean(_ outcome: RunSessionOutcome) -> Bool {
        !outcome.endedEarly
            && outcome.plannedRunIntervals > 0
            && outcome.completedRunIntervals >= outcome.plannedRunIntervals
            && outcome.runBackOffCount == 0
            && outcome.walksHitCap == 0
    }

    /// A struggle: repeated back-offs, or bailing out with under half the runs done.
    private func isStruggle(_ outcome: RunSessionOutcome) -> Bool {
        if outcome.runBackOffCount >= regressBackOffCount { return true }
        if outcome.endedEarly, outcome.plannedRunIntervals > 0,
           outcome.completedRunIntervals * 2 < outcome.plannedRunIntervals {
            return true
        }
        return false
    }
}
