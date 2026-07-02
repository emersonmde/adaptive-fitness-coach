import Foundation

/// One phase of a run/walk session.
///
/// Warmup and cooldown are distinct from the repeating mid-session walks so the UI and
/// haptics can treat them differently (e.g. no "ease off" messaging during the warmup).
public enum IntervalPhase: String, Codable, Sendable, Hashable {
    case warmupWalk
    case run
    case walk
    case cooldownWalk

    /// True for any phase the user is meant to run (work). Drives green vs amber UI.
    public var isRun: Bool { self == .run }

    /// True for any walking phase (warmup, recovery walk, cooldown).
    public var isWalk: Bool { !isRun }

    /// The verb shown on the watch face during this phase.
    public var verb: String { isRun ? "RUN" : "WALK" }
}

/// One segment of the plan: a phase to perform for a target duration.
///
/// `targetDuration` is a *seed* (N7). The interval engine adjusts a working copy of it
/// in real time from the user's heart-rate zone; the original plan is never mutated.
public struct IntervalSegment: Codable, Sendable, Hashable {
    public var phase: IntervalPhase
    public var targetDuration: TimeInterval // seconds

    public init(phase: IntervalPhase, targetDuration: TimeInterval) {
        self.phase = phase
        self.targetDuration = targetDuration
    }
}

/// An ordered list of run/walk segments forming one session.
public struct IntervalPlan: Codable, Sendable, Hashable {
    public var segments: [IntervalSegment]

    public init(segments: [IntervalSegment]) {
        self.segments = segments
    }

    /// Sum of all segment target durations — the planned session length before adaptation.
    public var plannedDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.targetDuration }
    }

    /// Count of `run` segments (excludes warmup/cooldown walks) — the session's "intervals".
    public var runIntervalCount: Int {
        segments.filter { $0.phase == .run }.count
    }
}

public extension IntervalPlan {
    /// Build a session plan from a run card's shape and seeds: an optional warmup walk, a run
    /// block filled with `runSeconds`/`walkSeconds` cycles, and an optional cooldown walk.
    ///
    /// The block is filled with whole cycles (at least one) landing near `blockDuration` —
    /// exactness doesn't matter because the engine adapts every segment live (N7). A trailing
    /// walk is kept (recovery before cooldown); once the seeds have progressed to where a
    /// single run covers the whole block (`runSeconds >= blockDuration`, or the walk seed has
    /// reached zero), the block becomes one continuous run.
    static func runWalk(
        runSeconds: TimeInterval,
        walkSeconds: TimeInterval,
        blockDuration: TimeInterval,
        warmup: TimeInterval,
        cooldown: TimeInterval
    ) -> IntervalPlan {
        var segments: [IntervalSegment] = []
        if warmup > 0 {
            segments.append(IntervalSegment(phase: .warmupWalk, targetDuration: warmup))
        }

        let run = max(15, runSeconds)
        if walkSeconds <= 0 || run >= blockDuration {
            // Continuous running reached (or the block is shorter than one run interval):
            // one run segment covering the BLOCK the user asked for — never the raw seed,
            // which may be a sentinel far larger (a 3600s calibration seed must not turn a
            // 20-minute session into an uncompletable 60-minute segment that reads as a bail).
            segments.append(IntervalSegment(phase: .run, targetDuration: max(15, blockDuration)))
        } else {
            let cycleLength = run + walkSeconds
            let cycles = max(1, Int((blockDuration / cycleLength).rounded()))
            for _ in 0..<cycles {
                segments.append(IntervalSegment(phase: .run, targetDuration: run))
                segments.append(IntervalSegment(phase: .walk, targetDuration: walkSeconds))
            }
        }

        if cooldown > 0 {
            segments.append(IntervalSegment(phase: .cooldownWalk, targetDuration: cooldown))
        }
        return IntervalPlan(segments: segments)
    }

    /// The plan for a run card — shape and seeds both come from the card.
    static func plan(for card: RunCard) -> IntervalPlan {
        runWalk(
            runSeconds: TimeInterval(card.runSeconds),
            walkSeconds: TimeInterval(card.walkSeconds),
            blockDuration: TimeInterval(card.durationMinutes * 60),
            warmup: TimeInterval(card.warmupMinutes * 60),
            cooldown: TimeInterval(card.cooldownMinutes * 60)
        )
    }

    /// The default seed plan for a low-fitness beginner — a starting point for Q1, not its
    /// resolution (Q1's research-optimal ratio is still pending per the PRD).
    ///
    /// 5-minute warmup walk, 8 cycles of 60s run / 90s walk, 5-minute cooldown walk
    /// (~30 minutes total). Matches NHS Couch-to-5K Week 1. The ratio is only a seed: the
    /// adaptation engine shortens runs / lengthens walks for a struggling user and extends
    /// runs / shortens walks for a comfortable one, so a wrong seed self-corrects (N7).
    ///
    /// `cycles` is clamped to at least 1 so the factory never yields a runless "run".
    static func beginnerRunWalk(
        warmup: TimeInterval = 300,
        runDuration: TimeInterval = 60,
        walkDuration: TimeInterval = 90,
        cycles: Int = 8,
        cooldown: TimeInterval = 300
    ) -> IntervalPlan {
        var segments: [IntervalSegment] = []
        segments.append(IntervalSegment(phase: .warmupWalk, targetDuration: warmup))
        for _ in 0..<max(1, cycles) {
            segments.append(IntervalSegment(phase: .run, targetDuration: runDuration))
            segments.append(IntervalSegment(phase: .walk, targetDuration: walkDuration))
        }
        segments.append(IntervalSegment(phase: .cooldownWalk, targetDuration: cooldown))
        return IntervalPlan(segments: segments)
    }
}
