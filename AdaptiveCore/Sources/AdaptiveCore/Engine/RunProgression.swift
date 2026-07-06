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
    /// Walks the user chose to run through (cadence-verified). Their poor recovery numbers
    /// are an artifact of the choice — they never count as struggle signals.
    public var walksDefied: Int
    /// Walks that ended at the floor — recovery confirmed as early as the rules allow.
    public var fastRecoveries: Int
    /// Longest single run interval sustained this session, seconds. With extension unlocked
    /// this is the user's demonstrated capacity, which progression snaps to.
    public var longestRunSeconds: TimeInterval
    /// Mean heart-rate recovery drop (bpm) across walks, nil when HR was unavailable.
    public var meanRecoveryDrop: Double?
    /// True when the user ended the workout before the plan finished.
    public var endedEarly: Bool
    /// The user's post-run perceived effort, 1 (easy) – 10 (all-out); nil when unrated
    /// (build 9). The subjective signal the objective ones miss — HR can sit in-zone while
    /// the runner is gassed (the fatigue-blindness that drove run v2). It only ever *lowers*
    /// aggressiveness: a high rating holds an otherwise-clean advance.
    public var perceivedEffort: Int?

    public init(
        plannedRunIntervals: Int,
        completedRunIntervals: Int,
        runBackOffCount: Int,
        walksHitCap: Int,
        walksDefied: Int = 0,
        fastRecoveries: Int = 0,
        longestRunSeconds: TimeInterval = 0,
        meanRecoveryDrop: Double? = nil,
        endedEarly: Bool = false,
        perceivedEffort: Int? = nil
    ) {
        self.plannedRunIntervals = plannedRunIntervals
        self.completedRunIntervals = completedRunIntervals
        self.runBackOffCount = runBackOffCount
        self.walksHitCap = walksHitCap
        self.walksDefied = walksDefied
        self.fastRecoveries = fastRecoveries
        self.longestRunSeconds = longestRunSeconds
        self.meanRecoveryDrop = meanRecoveryDrop
        self.endedEarly = endedEarly
        self.perceivedEffort = perceivedEffort
    }

    public init(summary: SessionSummary) {
        self.init(
            plannedRunIntervals: summary.plannedRunIntervals,
            completedRunIntervals: summary.intervalsCompleted,
            runBackOffCount: summary.runBackOffCount,
            walksHitCap: summary.walksHitCap,
            walksDefied: summary.walksDefied,
            fastRecoveries: summary.fastRecoveries,
            longestRunSeconds: summary.longestRunSeconds,
            meanRecoveryDrop: summary.meanRecoveryDrop,
            endedEarly: summary.endedEarly,
            perceivedEffort: summary.perceivedEffort
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

    /// The factory seeds a brand-new run card starts with — the single source of truth used
    /// by `RunCard` defaults/decoding, `needsCalibration`, and `FitnessCalibration`. If these
    /// drift apart the cold-start calibration gate silently breaks, so they must not be
    /// duplicated as literals.
    public static let factoryDefault = RunSeeds(runSeconds: 90, walkSeconds: 120)
}

public extension RunSeeds {
    /// The one quiet line that makes cross-session adaptation perceivable on the summary
    /// screen ("Next run: 2 min run · 90s walk"). Nil when nothing changed — adaptation
    /// never nags (Q5).
    static func progressionNote(from old: RunSeeds, to new: RunSeeds, blockSeconds: Int) -> String? {
        guard new != old else { return nil }
        if new.runSeconds >= blockSeconds || new.walkSeconds <= 0 {
            return "Next run: continuous"
        }
        return "Next run: \(shortTime(new.runSeconds)) run · \(shortTime(new.walkSeconds)) walk"
    }

    private static func shortTime(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds % 60 == 0 { return "\(seconds / 60) min" }
        return "\(seconds / 60)m \(seconds % 60)s"
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
    /// Seconds the walk seed shrinks per advance notch past the threshold.
    public var walkShrinkStep: Int
    /// Back-offs at/above this count regress (2+ cut-short runs is a pattern, not a blip).
    public var regressBackOffCount: Int
    /// Snap fires when the longest sustained run reached this multiple of the seed
    /// (demonstrated capacity clearly beyond a notch's worth).
    public var snapRatio: Double
    /// The walk seed a snapped (long-run) plan is capped at — long runs pair with short
    /// recoveries.
    public var snapWalkCeiling: Int
    /// A perceived-effort rating at/above this (1–10) blocks advancing an otherwise-clean
    /// session and suppresses the demonstrated-capacity snap — a run that *felt* all-out
    /// isn't sustainable capacity to build on, regardless of what the objective counters say.
    /// Effort only ever holds; it never eases (that would punish a hard clean session).
    public var highEffortThreshold: Int

    public init(
        maxAdvanceStep: Int = 60,
        regressStep: Int = 15,
        minRunSeconds: Int = 30,
        minWalkSeconds: Int = 60,
        maxWalkSeconds: Int = 180,
        walkShrinkThreshold: Int = 180,
        walkShrinkStep: Int = 15,
        regressBackOffCount: Int = 2,
        snapRatio: Double = 1.5,
        snapWalkCeiling: Int = 90,
        highEffortThreshold: Int = 8
    ) {
        self.maxAdvanceStep = maxAdvanceStep
        self.regressStep = regressStep
        self.minRunSeconds = minRunSeconds
        self.minWalkSeconds = minWalkSeconds
        self.maxWalkSeconds = maxWalkSeconds
        self.walkShrinkThreshold = walkShrinkThreshold
        self.walkShrinkStep = walkShrinkStep
        self.regressBackOffCount = regressBackOffCount
        self.snapRatio = snapRatio
        self.snapWalkCeiling = snapWalkCeiling
        self.highEffortThreshold = highEffortThreshold
    }

    /// Whether the user rated this session at or above the high-effort threshold.
    private func isHighEffort(_ outcome: RunSessionOutcome) -> Bool {
        (outcome.perceivedEffort ?? 0) >= highEffortThreshold
    }

    /// The full result of one session's evaluation: next seeds plus the classification the
    /// P6 journal and structural-confirm gate need. `isStructural` marks advance-direction
    /// *shape* changes only — a walk shrink or the crossing into continuous running. Easing
    /// also moves the walk seed, but backing off is never gated behind a confirm (the PRD's
    /// bias toward backing off), so a struggle result is structural-false by construction.
    public struct Evaluation: Sendable, Hashable {
        public let seeds: RunSeeds
        public let reason: ProgressionReason
        public let isStructural: Bool
    }

    /// Next session's seeds given this session's outcome.
    public func nextSeeds(current: RunSeeds, outcome: RunSessionOutcome) -> RunSeeds {
        // Int.max block: the wrapper predates the continuous-graduation check and never
        // consumed the structural flag — seeds math is identical either way.
        evaluate(current: current, outcome: outcome, blockSeconds: Int.max).seeds
    }

    /// `nextSeeds` plus the reason and the structural flag. `blockSeconds` is the run block's
    /// planned length — the same denominator `RunSeeds.progressionNote` uses to say
    /// "continuous"; a seed reaching it is the run-shape graduation P6 gates.
    public func evaluate(current: RunSeeds, outcome: RunSessionOutcome, blockSeconds: Int) -> Evaluation {
        var seeds = current
        var reason: ProgressionReason = .mixedSession
        var snapped = false

        if isStruggle(outcome) {
            seeds.runSeconds = max(minRunSeconds, current.runSeconds - regressStep)
            // A struggle only ever *eases*: lengthen the walk toward the cap, but never pull
            // an already-longer walk seed down (that would raise effort on a struggle signal).
            seeds.walkSeconds = max(current.walkSeconds, min(maxWalkSeconds, current.walkSeconds + regressStep))
            reason = outcome.runBackOffCount >= regressBackOffCount ? .repeatedBackOffs : .endedEarly
        } else if isClean(outcome) && !isHighEffort(outcome) {
            // Advance only when the session was clean AND didn't feel all-out. A clean session
            // rated high effort falls through to hold — the runner is near their ceiling even
            // though the objective counters looked good (the fatigue-blindness run v2 exists
            // to catch, now with the missing subjective signal).
            // A strong session — every walk ended at the floor, i.e. the user out-recovered
            // the plan everywhere — jumps two notches instead of one, so a mis-seeded fit
            // runner reaches their real level in a couple of sessions, not a month.
            let strong = isStrong(outcome)
            let notches = strong ? 2 : 1
            for _ in 0..<notches {
                let step = min(maxAdvanceStep, max(15, seeds.runSeconds / 4))
                seeds.runSeconds += step
                if seeds.runSeconds >= walkShrinkThreshold {
                    seeds.walkSeconds = max(minWalkSeconds, seeds.walkSeconds - walkShrinkStep)
                }
            }
            reason = strong ? .strongSession : .cleanSession
        } else if isClean(outcome), let effort = outcome.perceivedEffort, isHighEffort(outcome) {
            reason = .highEffort(effort)
        }
        // Anything in between: hold. A held seed is a fine seed (N7).

        // Snap to demonstrated capacity: a run sustained well past the seed (extension
        // unlocked by fast recovery) is direct evidence of the user's real level — start
        // there next time instead of climbing notch by notch. Never on a struggle (a long
        // run that ended in repeated back-offs isn't capacity), and never downward. The
        // gate compares against the seed the user *ran with* (not the post-advance one) —
        // demonstrated capacity is relative to what was asked of them.
        // Also suppress the snap when the session felt all-out: a long run that was maximal
        // isn't repeatable capacity to start from next time.
        if !isStruggle(outcome) && !isHighEffort(outcome) {
            let demonstrated = Int(outcome.longestRunSeconds / 15) * 15
            if Double(demonstrated) >= Double(current.runSeconds) * snapRatio {
                if demonstrated > seeds.runSeconds { snapped = true }
                seeds.runSeconds = max(seeds.runSeconds, demonstrated)
                if seeds.runSeconds >= walkShrinkThreshold {
                    seeds.walkSeconds = max(minWalkSeconds, min(seeds.walkSeconds, snapWalkCeiling))
                }
            }
        }

        if snapped { reason = .snapToCapacity }

        // Advance-direction shape changes only: a shrunk walk, or the run seed crossing the
        // block length (the plan factory then emits a single continuous run). Easing lengthens
        // the walk but is never structural — backing off stays automatic.
        let becameContinuous = seeds.runSeconds >= blockSeconds && current.runSeconds < blockSeconds
        let isStructural = seeds.walkSeconds < current.walkSeconds || becameContinuous

        return Evaluation(seeds: seeds, reason: reason, isStructural: isStructural)
    }

    /// A clean session: every planned run reached, none cut short, no walk pinned at the cap.
    /// (Recovery quality is already encoded in walk behavior — a slow recoverer lengthens
    /// walks or hits the cap, so `meanRecoveryDrop` isn't double-counted here.) Walks the
    /// user ran through are excluded from the cap count: running through a walk drags HR
    /// recovery out by construction, and punishing the choice would regress a runner for
    /// being *too* capable.
    private func isClean(_ outcome: RunSessionOutcome) -> Bool {
        !outcome.endedEarly
            && outcome.plannedRunIntervals > 0
            && outcome.completedRunIntervals >= outcome.plannedRunIntervals
            && outcome.runBackOffCount == 0
            && max(0, outcome.walksHitCap - outcome.walksDefied) == 0
    }

    /// A strong session: clean, and every planned walk ended at the recovery floor.
    /// (Walks == planned runs in the plan factory; require all of them.)
    private func isStrong(_ outcome: RunSessionOutcome) -> Bool {
        outcome.fastRecoveries >= outcome.plannedRunIntervals && outcome.plannedRunIntervals > 0
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
