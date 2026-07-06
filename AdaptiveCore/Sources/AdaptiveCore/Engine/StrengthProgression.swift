import Foundation

/// One completed set (or hold) as the session experienced it — the raw material progression
/// works from. Recorded by the watch manager at each "Done set"; `completedReps` comes from
/// the Digital Crown (defaults to prescribed — hitting the prescription costs zero taps).
public struct StrengthSetRecord: Sendable, Hashable {
    public var exerciseId: String
    public var prescribedReps: Int?
    public var completedReps: Int?
    public var prescribedHoldSeconds: TimeInterval?
    public var completedHoldSeconds: TimeInterval?
    /// The load actually in effect for this set (seed + any manual override) — truthful history.
    public var weight: Weight?
    /// Whether the rest after this set ended recovered (heart rate dropped) or hit the cap
    /// still elevated. nil = no HR signal or no trailing rest — absence is never a signal (N6).
    public var restRecovered: Bool?

    public init(
        exerciseId: String,
        prescribedReps: Int? = nil,
        completedReps: Int? = nil,
        prescribedHoldSeconds: TimeInterval? = nil,
        completedHoldSeconds: TimeInterval? = nil,
        weight: Weight? = nil,
        restRecovered: Bool? = nil
    ) {
        self.exerciseId = exerciseId
        self.prescribedReps = prescribedReps
        self.completedReps = completedReps
        self.prescribedHoldSeconds = prescribedHoldSeconds
        self.completedHoldSeconds = completedHoldSeconds
        self.weight = weight
        self.restRecovered = restRecovered
    }
}

/// One exercise's session, aggregated across its sets. Grouping is by `exerciseId` across all
/// card occurrences (rounds included) — deliberately consistent with `applyingProgressions`'
/// one-move-one-seed rule.
public struct StrengthExerciseOutcome: Sendable, Hashable {
    public var exerciseId: String
    /// Card occurrences of this exercise in the block actually run (rounds-expanded).
    public var setsPlanned: Int
    public var setsCompleted: Int
    public var completedRepsPerSet: [Int]
    public var prescribedReps: Int?
    public var completedHoldSecondsPerSet: [TimeInterval]
    public var prescribedHoldSeconds: TimeInterval?
    /// Rests after this exercise's sets that hit the cap still unrecovered.
    public var unrecoveredRests: Int
    /// The user manually lowered this dimension mid-session — direct struggle evidence.
    public var weightManuallyLowered: Bool
    /// The user manually raised this dimension mid-session — that IS this session's
    /// progression; the policy holds rather than stacking an advance on top.
    public var weightManuallyRaised: Bool
    public var repsManuallyChanged: Bool

    public init(
        exerciseId: String,
        setsPlanned: Int,
        setsCompleted: Int,
        completedRepsPerSet: [Int] = [],
        prescribedReps: Int? = nil,
        completedHoldSecondsPerSet: [TimeInterval] = [],
        prescribedHoldSeconds: TimeInterval? = nil,
        unrecoveredRests: Int = 0,
        weightManuallyLowered: Bool = false,
        weightManuallyRaised: Bool = false,
        repsManuallyChanged: Bool = false
    ) {
        self.exerciseId = exerciseId
        self.setsPlanned = setsPlanned
        self.setsCompleted = setsCompleted
        self.completedRepsPerSet = completedRepsPerSet
        self.prescribedReps = prescribedReps
        self.completedHoldSecondsPerSet = completedHoldSecondsPerSet
        self.prescribedHoldSeconds = prescribedHoldSeconds
        self.unrecoveredRests = unrecoveredRests
        self.weightManuallyLowered = weightManuallyLowered
        self.weightManuallyRaised = weightManuallyRaised
        self.repsManuallyChanged = repsManuallyChanged
    }
}

/// A whole strength session distilled for progression.
public struct StrengthSessionOutcome: Sendable, Hashable {
    public var exercises: [StrengthExerciseOutcome]
    public var endedEarly: Bool
    /// Post-session perceived effort 1–10 (build 9), nil when unrated. Session-level: it
    /// applies to every exercise's decision. Only ever holds an advance, never eases.
    public var perceivedEffort: Int?

    public init(exercises: [StrengthExerciseOutcome], endedEarly: Bool = false, perceivedEffort: Int? = nil) {
        self.exercises = exercises
        self.endedEarly = endedEarly
        self.perceivedEffort = perceivedEffort
    }

    /// Aggregate a raw set log into per-exercise outcomes.
    /// - Parameters:
    ///   - setLog: the session's recorded sets, in order.
    ///   - plannedSetsByExercise: card occurrences per exerciseId in the block actually run.
    ///   - manual: exercise ids the user manually adjusted this session, by direction.
    public init(
        setLog: [StrengthSetRecord],
        plannedSetsByExercise: [String: Int],
        loweredWeight: Set<String> = [],
        raisedWeight: Set<String> = [],
        changedReps: Set<String> = [],
        endedEarly: Bool = false,
        perceivedEffort: Int? = nil
    ) {
        self.perceivedEffort = perceivedEffort
        var byExercise: [String: StrengthExerciseOutcome] = [:]
        for (id, planned) in plannedSetsByExercise {
            byExercise[id] = StrengthExerciseOutcome(
                exerciseId: id, setsPlanned: planned, setsCompleted: 0,
                weightManuallyLowered: loweredWeight.contains(id),
                weightManuallyRaised: raisedWeight.contains(id),
                repsManuallyChanged: changedReps.contains(id)
            )
        }
        for record in setLog {
            var outcome = byExercise[record.exerciseId] ?? StrengthExerciseOutcome(
                exerciseId: record.exerciseId, setsPlanned: 0, setsCompleted: 0
            )
            outcome.setsCompleted += 1
            if let reps = record.completedReps {
                outcome.completedRepsPerSet.append(reps)
                outcome.prescribedReps = record.prescribedReps ?? outcome.prescribedReps
            }
            if let hold = record.completedHoldSeconds {
                outcome.completedHoldSecondsPerSet.append(hold)
                outcome.prescribedHoldSeconds = record.prescribedHoldSeconds ?? outcome.prescribedHoldSeconds
            }
            if record.restRecovered == false { outcome.unrecoveredRests += 1 }
            byExercise[record.exerciseId] = outcome
        }
        self.exercises = byExercise.values.sorted { $0.exerciseId < $1.exerciseId }
        self.endedEarly = endedEarly
    }
}

/// Tunables for strength progression, with their evidence base.
public struct StrengthProgressionConfig: Sendable, Hashable {
    /// A set is "short" when completed ≤ prescribed − this. Two reps distinguishes genuine
    /// failure from a miscount, mirroring the granularity of the NSCA 2-for-2 rule
    /// (Baechle & Earle, Essentials of Strength Training and Conditioning).
    public var shortfallReps: Int
    /// Short sets at/above this count ease the prescription — ≥2 is a pattern, not a blip
    /// (same threshold philosophy as the run policy's regressBackOffCount).
    public var struggleShortSets: Int
    /// Rests that hit the cap unrecovered at/above this count block an advance (suspicion
    /// downgrades advance→hold; it never eases — easing requires rep-shortfall evidence).
    public var suspicionUnrecoveredRests: Int
    /// Hold progression step/bounds. +5s per clean session is the smallest meaningful move;
    /// 15s floor keeps a hold coachable, 120s cap because longer front planks add endurance,
    /// not strength (isometric progressions then move to harder variations — P3's job).
    public var holdStep: TimeInterval
    public var holdFloor: TimeInterval
    public var holdCap: TimeInterval
    /// Easing never produces a load below the smallest real dumbbell (5 lb — the grid unit).
    public var minWeightPounds: Double
    /// A perceived-effort rating at/above this (1–10) downgrades an otherwise-clean advance to
    /// hold — same "block advance without easing" philosophy as `suspicionUnrecoveredRests`.
    public var highEffortThreshold: Int

    public init(
        shortfallReps: Int = 2,
        struggleShortSets: Int = 2,
        suspicionUnrecoveredRests: Int = 2,
        holdStep: TimeInterval = 5,
        holdFloor: TimeInterval = 15,
        holdCap: TimeInterval = 120,
        minWeightPounds: Double = Weight.gridPounds,
        highEffortThreshold: Int = 8
    ) {
        self.shortfallReps = shortfallReps
        self.struggleShortSets = struggleShortSets
        self.suspicionUnrecoveredRests = suspicionUnrecoveredRests
        self.holdStep = holdStep
        self.holdFloor = holdFloor
        self.holdCap = holdCap
        self.minWeightPounds = minWeightPounds
        self.highEffortThreshold = highEffortThreshold
    }
}

/// The prescription for one exercise — both the policy's input (seed + manual overrides
/// folded in) and its output (next session's seed).
public struct StrengthPrescription: Sendable, Hashable {
    public var reps: Int?
    public var weight: Weight?
    public var holdSeconds: TimeInterval?

    public init(reps: Int? = nil, weight: Weight? = nil, holdSeconds: TimeInterval? = nil) {
        self.reps = reps
        self.weight = weight
        self.holdSeconds = holdSeconds
    }
}

/// Turns one exercise's session outcome into next session's prescription — **double
/// progression**: reps climb one per clean session through the exercise's rep band; when the
/// band tops out, load steps up and reps reset to the bottom. This implements the ACSM
/// Position Stand's progression model (load +2–10% once reps exceed the target range —
/// "Progression Models in Resistance Training for Healthy Adults," MSSE 41(3), 2009) more
/// conservatively than the NSCA 2-for-2 rule: topping a 8–12 band takes ≥4 clean sessions
/// before any load increase. Tri-state like the run policy: advance needs a fully clean
/// session, easing needs clear shortfall evidence, everything ambiguous holds (N7 — a held
/// seed is a fine seed; bias toward backing off).
public struct StrengthProgressionPolicy: Sendable {
    public var config: StrengthProgressionConfig

    public init(config: StrengthProgressionConfig = StrengthProgressionConfig()) {
        self.config = config
    }

    public enum Decision: Sendable, Hashable { case advance, hold, ease }

    /// Classify the session for one exercise. `perceivedEffort` (session-level, 1–10, nil when
    /// unrated) only ever *holds* an advance — a high rating means near-ceiling even when the
    /// sets looked clean.
    public func decision(for outcome: StrengthExerciseOutcome, endedEarly: Bool, perceivedEffort: Int? = nil) -> Decision {
        if isStruggle(outcome, endedEarly: endedEarly) { return .ease }
        if isClean(outcome, endedEarly: endedEarly) {
            if (perceivedEffort ?? 0) >= config.highEffortThreshold { return .hold }
            return .advance
        }
        return .hold
    }

    /// Next session's prescription. `current` is the card seed with any manual overrides
    /// already folded in (a manual change is this session's progression for that dimension —
    /// the caller marks it in the outcome, and the policy then holds that dimension).
    public func nextPrescription(
        current: StrengthPrescription,
        exercise: Exercise,
        outcome: StrengthExerciseOutcome,
        endedEarly: Bool,
        perceivedEffort: Int? = nil
    ) -> StrengthPrescription {
        var next = current

        // Establish invariants regardless of hand-edited seeds.
        if let range = exercise.repRange, let reps = next.reps {
            next.reps = min(max(reps, range.lowerBound), range.upperBound)
        }
        if next.holdSeconds != nil {
            next.holdSeconds = min(max(next.holdSeconds!, config.holdFloor), config.holdCap)
        }

        switch decision(for: outcome, endedEarly: endedEarly, perceivedEffort: perceivedEffort) {
        case .hold:
            break

        case .advance:
            if next.holdSeconds != nil {
                next.holdSeconds = min(next.holdSeconds! + config.holdStep, config.holdCap)
            } else if let range = exercise.repRange, let reps = next.reps,
                      // A manual change to a dimension freezes it this session (already progressed).
                      !outcome.repsManuallyChanged, !outcome.weightManuallyRaised {
                if reps < range.upperBound {
                    next.reps = reps + 1
                } else if let weight = next.weight {
                    // Band topped out: load steps up, reps reset to the bottom (ACSM 2009).
                    // Grid-stepped: an off-grid legacy load advances only to the adjacent
                    // multiple of 5 (22.5 → 25, conservatively short of a full step).
                    next.weight = weight.stepped(byPounds: exercise.weightStepPounds)
                    next.reps = range.lowerBound
                }
                // Bodyweight at the top of its band: hold. A heavier "step" doesn't exist;
                // P3's AI can suggest a harder variation (e.g. push-up → decline push-up).
            }

        case .ease:
            if next.holdSeconds != nil {
                next.holdSeconds = max(next.holdSeconds! - config.holdStep, config.holdFloor)
            } else if let range = exercise.repRange, let reps = next.reps {
                if reps > range.lowerBound {
                    next.reps = reps - 1
                } else if let weight = next.weight {
                    next.weight = weight.stepped(byPounds: -exercise.weightStepPounds)
                }
            }
        }

        // Every prescription leaves on the 5 lb grid, whatever path produced it — this is
        // where legacy 2.5-step loads (22.5) converge (holds included; midpoints snap down).
        // A loaded movement is floored at the smallest real dumbbell: easing/snapping may
        // never turn a weighted exercise into a phantom 0 lb one.
        let hadLoad = (current.weight?.pounds ?? 0) > 0
        next.weight = next.weight.map { weight in
            let snapped = weight.snappedToGrid()
            return (snapped.pounds < config.minWeightPounds && hadLoad)
                ? Weight.lb(config.minWeightPounds) : snapped
        }
        return next
    }

    /// A clean session for this exercise: all planned sets done, every set at/above
    /// prescription (holds: full duration), rests recovering, session not abandoned.
    private func isClean(_ o: StrengthExerciseOutcome, endedEarly: Bool) -> Bool {
        guard !endedEarly, o.setsPlanned > 0, o.setsCompleted >= o.setsPlanned else { return false }
        if o.unrecoveredRests >= config.suspicionUnrecoveredRests { return false }
        if let prescribed = o.prescribedReps {
            guard !o.completedRepsPerSet.isEmpty,
                  o.completedRepsPerSet.allSatisfy({ $0 >= prescribed }) else { return false }
        }
        if let hold = o.prescribedHoldSeconds {
            guard !o.completedHoldSecondsPerSet.isEmpty,
                  o.completedHoldSecondsPerSet.allSatisfy({ $0 >= hold }) else { return false }
        }
        return true
    }

    /// Clear shortfall evidence: repeated short sets, a manual weight reduction, or bailing
    /// with under half this exercise's sets done. (Unattempted sets are not failures — a
    /// session ended early with most sets done reads as hold, not ease.)
    private func isStruggle(_ o: StrengthExerciseOutcome, endedEarly: Bool) -> Bool {
        if o.weightManuallyLowered { return true }
        if let prescribed = o.prescribedReps {
            let short = o.completedRepsPerSet.filter { $0 <= prescribed - config.shortfallReps }.count
            if short >= config.struggleShortSets { return true }
        }
        if let hold = o.prescribedHoldSeconds {
            let short = o.completedHoldSecondsPerSet.filter { $0 <= hold - config.holdStep }.count
            if short >= config.struggleShortSets { return true }
        }
        if endedEarly, o.setsPlanned > 0, o.setsCompleted * 2 < o.setsPlanned { return true }
        return false
    }
}

public extension StrengthPrescription {
    /// The one quiet "next time" line for the summary, or nil when nothing changed (Q5 —
    /// adaptation never nags). E.g. "Goblet Squat → 25 lb", "Push-Up → 12 reps", "Plank → 40s".
    static func progressionNote(exerciseName: String, from old: StrengthPrescription, to new: StrengthPrescription) -> String? {
        guard new != old else { return nil }
        if let weight = new.weight, weight != old.weight {
            return "\(exerciseName) → \(weight.displayString())"
        }
        if let reps = new.reps, reps != old.reps {
            return "\(exerciseName) → \(reps) reps"
        }
        if let hold = new.holdSeconds, hold != old.holdSeconds {
            return "\(exerciseName) → \(Int(hold))s hold"
        }
        return nil
    }
}
