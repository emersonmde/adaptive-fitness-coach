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

    /// A beginner run/walk plan scaled to a target total length (the user-chosen
    /// `Routine.durationMinutes`). Warmup and cooldown take ~1/6 of the session each, capped at
    /// 5 minutes; the remaining time is filled with 60s-run / 90s-walk cycles. The result lands
    /// near `totalDuration` (within one cycle) — exactness doesn't matter because the engine
    /// adapts every segment in real time (N7).
    static func beginnerRunWalk(
        totalDuration: TimeInterval,
        runDuration: TimeInterval = 60,
        walkDuration: TimeInterval = 90
    ) -> IntervalPlan {
        let cap = 300.0
        let warmup = min(cap, totalDuration / 6)
        let cooldown = min(cap, totalDuration / 6)
        let cycleLength = runDuration + walkDuration
        let middle = max(cycleLength, totalDuration - warmup - cooldown)
        let cycles = max(1, Int((middle / cycleLength).rounded()))
        return beginnerRunWalk(
            warmup: warmup,
            runDuration: runDuration,
            walkDuration: walkDuration,
            cycles: cycles,
            cooldown: cooldown
        )
    }
}
