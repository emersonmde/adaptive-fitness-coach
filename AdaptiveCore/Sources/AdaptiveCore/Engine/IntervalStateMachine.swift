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
/// mutates the seed plan) and an `AdaptationPolicy`. It takes a `WorkoutSample` (zone +
/// raw heart rate) as input and emits transitions/adaptations as output. No HealthKit, no
/// clock — the caller supplies `deltaTime`, which makes the whole engine deterministic and
/// testable.
///
/// Signal degradation is per-field (N6): no zone → runs hold their planned duration; no
/// heart rate → walks hold theirs; neither → the plan runs as fixed intervals.
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

    /// Runs the policy cut short (either back-off window) — the session's struggle signal.
    public private(set) var runBackOffCount: Int
    /// Walks that reached `maxWalkDuration` still unrecovered — the "never trap the user
    /// walking forever" cap fired, a strong struggle signal.
    public private(set) var walksHitCap: Int
    /// Per-walk heart-rate recovery: bpm dropped from the preceding run's peak within the
    /// first 60 seconds of the walk (Cole et al., NEJM 1999 — the standard HRR window), or
    /// at walk end for walks shorter than that. Empty when heart rate was unavailable.
    public private(set) var recoveryDrops: [Double]
    /// Walks that ended essentially at the floor — recovery confirmed as early as the rules
    /// allow. The "this user is fitter than the seeds" signal: it unlocks run extension for
    /// the rest of the session and marks the session as strong for multi-notch progression.
    public private(set) var fastRecoveries: Int
    /// The longest single run interval actually sustained this session (seconds). With
    /// extension unlocked this can far exceed the seed — progression snaps to it, so one
    /// session is enough for a mis-seeded fit runner to land at their real level.
    public private(set) var longestRunInterval: TimeInterval
    /// Walk intervals completed naturally (the counterpart to `intervalsCompleted`). Skipped
    /// walks earn no credit (N6), and warmup/cooldown are not walks — same rule as runs.
    public private(set) var walksCompleted: Int
    /// Seconds of RUN time spent in the target zone — the "time in optimal zone" the summary
    /// shows. Run phases only (a walk below zone is desired, counting it would dilute the
    /// metric) and only ticks with a fresh zone reading accumulate; the caller nils stale
    /// zones, so sensor gaps add nothing (N6).
    public private(set) var timeInTargetZone: TimeInterval

    /// Peak heart rate observed during the current/most recent run segment. Reset when a new
    /// run begins; carried through the following walk for recovery math.
    private var peakRunHeartRate: Double?
    /// Most recent heart rate seen, for recovery recording on ticks without a fresh sample.
    private var lastHeartRate: Double?
    /// Whether any HR sample arrived during the current walk. Gates recovery recording: a
    /// drop computed purely from a pre-walk reading would fabricate a "poor recovery" out of
    /// a sensor gap (N6).
    private var heartRateSeenThisWalk = false
    /// Whether the current walk's recovery drop has been recorded yet.
    private var recoveryRecordedThisWalk = false
    /// Set while the current walk sits at `maxWalkDuration` unrecovered; folded into
    /// `walksHitCap` when the segment advances.
    private var walkHitCapPending = false
    /// True while the current segment is being force-ended by `skipCurrentSegment` — skipped
    /// segments don't earn interval credit or record recovery (nothing was demonstrated).
    private var skippingSegment = false

    /// Non-transition adaptations (extend/lengthen) already surfaced for the current segment,
    /// used to show each banner at most once per segment.
    private var announcedThisSegment: Set<AdaptationAction> = []

    /// Seconds into a walk after which the recovery drop is sampled. Fixed at the clinical
    /// HRR definition's one-minute mark (Cole et al., NEJM 1999), not a tunable.
    private static let recoverySampleTime: TimeInterval = 60

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
        self.runBackOffCount = 0
        self.walksHitCap = 0
        self.recoveryDrops = []
        self.fastRecoveries = 0
        self.longestRunInterval = 0
        self.walksCompleted = 0
        self.timeInTargetZone = 0
    }

    /// The phase currently in progress, or nil once the session is complete.
    public var currentPhase: IntervalPhase? {
        isComplete || segments.isEmpty ? nil : segments[currentIndex].phase
    }

    /// The current segment's working target duration (after any adaptation), or nil if complete.
    public var currentTargetDuration: TimeInterval? {
        isComplete || segments.isEmpty ? nil : segments[currentIndex].targetDuration
    }

    /// Mean heart-rate recovery drop across the session's walks, or nil if never measurable.
    public var meanRecoveryDrop: Double? {
        recoveryDrops.isEmpty ? nil : recoveryDrops.reduce(0, +) / Double(recoveryDrops.count)
    }

    /// True while the current segment is a run that has been extended past its seed. Ending
    /// the workout here is finishing a long run, not bailing — the caller uses this to keep
    /// a manual end from reading as a struggle.
    public var currentRunIsExtended: Bool {
        !isComplete && !segments.isEmpty
            && segments[currentIndex].phase == .run
            && announcedThisSegment.contains(.extendedRun)
    }

    /// Zone-only convenience over `tick(deltaTime:sample:)` (no heart rate → no recovery math).
    public mutating func tick(deltaTime: TimeInterval, currentZone: Int?) -> TickResult {
        tick(deltaTime: deltaTime, sample: WorkoutSample(zone: currentZone))
    }

    /// Advance the session by `deltaTime` seconds given the live `sample`. Returns what changed
    /// this tick. Callers should tick at roughly ≤1s granularity and clamp `deltaTime` against
    /// background catch-up; a non-positive delta is ignored.
    public mutating func tick(deltaTime: TimeInterval, sample: WorkoutSample) -> TickResult {
        guard !isComplete, !segments.isEmpty else {
            return TickResult(isComplete: true)
        }
        guard deltaTime > 0 else { return TickResult() }

        intervalElapsed += deltaTime
        sessionElapsed += deltaTime

        let phase = segments[currentIndex].phase
        if phase.isRun {
            totalRunDuration += deltaTime
            longestRunInterval = max(longestRunInterval, intervalElapsed)
            if sample.zone == targetZone {
                timeInTargetZone += deltaTime
            }
        } else {
            totalWalkDuration += deltaTime
        }

        observeHeartRate(sample.heartRate, phase: phase)

        // Adaptation only applies to the repeating run/walk intervals. Warmup/cooldown walks
        // run their fixed seed duration.
        if phase == .run || phase == .walk {
            if let result = adapt(phase: phase, sample: sample, deltaTime: deltaTime) {
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

    /// End the current segment now and move to the next, exactly as a natural transition would
    /// (same `TickResult`, so the caller's haptic/UI path is unchanged). Used to cut the warmup
    /// short when running is detected or the user taps "Start Run". Valid for any segment, but
    /// a skipped segment earns no interval credit and records no recovery — nothing was
    /// demonstrated, so nothing is counted (N6).
    public mutating func skipCurrentSegment() -> TickResult {
        guard !isComplete, !segments.isEmpty else {
            return TickResult(isComplete: true)
        }
        skippingSegment = true
        defer { skippingSegment = false }
        let transition = advance()
        return TickResult(transition: transition, isComplete: isComplete)
    }

    /// Track peak run HR and sample the walk's recovery drop at the 60s HRR mark.
    private mutating func observeHeartRate(_ heartRate: Double?, phase: IntervalPhase) {
        if let heartRate {
            lastHeartRate = heartRate
            if phase == .run {
                peakRunHeartRate = max(peakRunHeartRate ?? heartRate, heartRate)
            } else if phase == .walk {
                heartRateSeenThisWalk = true
            }
        }

        if phase == .walk, !recoveryRecordedThisWalk,
           intervalElapsed >= Self.recoverySampleTime {
            recordRecoveryDrop()
        }
    }

    /// Record the current walk's HRR drop once — only when the peak is known AND at least one
    /// HR sample actually arrived during this walk. A stale pre-walk reading proves nothing
    /// about recovery and would fabricate a near-zero drop across a sensor gap (N6).
    private mutating func recordRecoveryDrop() {
        guard heartRateSeenThisWalk, let peak = peakRunHeartRate, let hr = lastHeartRate else { return }
        recoveryDrops.append(max(0, peak - hr))
        recoveryRecordedThisWalk = true
    }

    /// Apply the adaptation policy for the current run/walk phase. Returns a `TickResult` if
    /// the policy acted this tick, or nil to fall through to the natural-transition check.
    private mutating func adapt(phase: IntervalPhase, sample: WorkoutSample, deltaTime: TimeInterval) -> TickResult? {
        let target = segments[currentIndex].targetDuration

        switch phase {
        case .run:
            // Run adaptation is zone-driven; without a zone the run holds its plan (N6).
            guard let zone = sample.zone else { return nil }
            switch policy.evaluateRun(currentZone: zone, targetZone: targetZone,
                                      intervalElapsed: intervalElapsed, segmentTarget: target, deltaTime: deltaTime,
                                      extensionUnlocked: fastRecoveries > 0) {
            case .shorten:
                let event = AdaptationEvent(action: .shortenedRun, atSessionTime: sessionElapsed, zone: zone)
                adaptationsApplied += 1
                runBackOffCount += 1
                let transition = advance()
                return TickResult(transition: transition, adaptation: event, isComplete: isComplete)
            case .extend:
                // Reachable via `allowRunExtension` (config, off by default — HR lag reads as
                // comfort in deconditioned runners) or the in-session evidence gate
                // (`fastRecoveries > 0`: a walk that ended at the recovery floor proved the
                // user is fitter than the seeds). The target keeps growing each qualifying
                // tick, but the banner is announced only once per run so the change never
                // nags (Q5).
                segments[currentIndex].targetDuration = target + policy.config.runExtendIncrement
                return announceOnce(.extendedRun, zone: zone)
            case .keepGoing:
                return nil
            }

        case .walk:
            switch policy.evaluateWalk(currentZone: sample.zone, heartRate: sample.heartRate,
                                       peakRunHeartRate: peakRunHeartRate, targetZone: targetZone,
                                       intervalElapsed: intervalElapsed, segmentTarget: target, deltaTime: deltaTime) {
            case .shorten:
                let event = AdaptationEvent(action: .shortenedWalk, atSessionTime: sessionElapsed, zone: sample.zone)
                adaptationsApplied += 1
                // Ending at (or a breath past) the floor means recovery was confirmed as early
                // as the rules allow — demonstrated fitness, not a lucky reading.
                if intervalElapsed <= policy.config.minWalkDuration + policy.config.recoverWindow {
                    fastRecoveries += 1
                }
                let transition = advance()
                return TickResult(transition: transition, adaptation: event, isComplete: isComplete)
            case .lengthen:
                guard target < policy.config.maxWalkDuration else {
                    // At cap and still unrecovered: let the natural transition end the walk
                    // (never trap the user walking forever) and remember the cap fired.
                    walkHitCapPending = true
                    return nil
                }
                segments[currentIndex].targetDuration = min(target + policy.config.walkLengthenIncrement, policy.config.maxWalkDuration)
                return announceOnce(.lengthenedWalk, zone: sample.zone)
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
    private mutating func announceOnce(_ action: AdaptationAction, zone: Int?) -> TickResult {
        guard !announcedThisSegment.contains(action) else { return TickResult() }
        announcedThisSegment.insert(action)
        adaptationsApplied += 1
        return TickResult(adaptation: AdaptationEvent(action: action, atSessionTime: sessionElapsed, zone: zone))
    }

    /// Move to the next segment, or complete the session. Returns the transition for haptics,
    /// or nil when the session completes (signaled via `isComplete`).
    private mutating func advance() -> TransitionEvent? {
        let fromPhase = segments[currentIndex].phase
        if fromPhase.isRun, !skippingSegment {
            intervalsCompleted += 1
        }
        if fromPhase == .walk, !skippingSegment {
            walksCompleted += 1
            // A short walk ends before the 60s HRR mark — record its drop at exit instead.
            if !recoveryRecordedThisWalk { recordRecoveryDrop() }
            if walkHitCapPending { walksHitCap += 1 }
        }
        heartRateSeenThisWalk = false
        recoveryRecordedThisWalk = false
        walkHitCapPending = false

        let nextIndex = currentIndex + 1
        guard nextIndex < segments.count else {
            isComplete = true
            return nil
        }

        currentIndex = nextIndex
        if segments[currentIndex].phase == .run {
            // New run: peak tracking starts fresh (the previous walk's recovery math is done).
            peakRunHeartRate = nil
        }
        intervalElapsed = 0
        policy.resetAccumulators()
        announcedThisSegment.removeAll()
        return TransitionEvent(from: fromPhase, to: segments[currentIndex].phase)
    }
}
