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
    /// Seconds of RUN time spent above the target zone (same fresh-reading rule as
    /// `timeInTargetZone`). Feeds the effort suggestion — a session mostly over zone felt hard.
    public private(set) var timeAboveTargetZone: TimeInterval
    /// The run duration future segments have converged to (nil until convergence first fires).
    /// This is the session's *demonstrated* run length — the only honest source for the
    /// cross-session converged path; the policy must never derive one from averages (N6).
    public private(set) var convergedRunSeconds: TimeInterval?
    /// The walk duration future segments have converged to (nil until convergence fires).
    public private(set) var convergedWalkSeconds: TimeInterval?
    /// Seconds added to the cooldown to backfill adaptation-driven session shrink, so a
    /// planned 30-minute session still delivers ~30 minutes of low-intensity volume.
    public private(set) var backfilledCooldownSeconds: TimeInterval

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
    /// Set by the caller when the compliance monitor accepted the user running through the
    /// current walk. A defied walk's dragged-out recovery is a choice, not a signal — it must
    /// never converge future walks upward (the caller already excludes it from struggle math).
    private var currentWalkDefied = false
    /// True while the current segment is being force-ended by `skipCurrentSegment` — skipped
    /// segments don't earn interval credit or record recovery (nothing was demonstrated).
    private var skippingSegment = false
    /// The session length the user signed up for, minus any time they *chose* to skip.
    /// Cooldown backfill restores adaptation-driven shrink up to this total; a skip is the
    /// user's choice and is never backfilled (same philosophy as `walksDefied`).
    private var effectivePlannedTotal: TimeInterval

    /// Run intervals that backed off with no fast recovery since — the "recovery isn't coming
    /// back" run. Climbs on each back-off, resets on each fast recovery. At `struggleCap` the
    /// session converts its remaining run/walk block to continuous easy walking (the evidence
    /// ladder's final rung). Exposed read-only for tests/telemetry.
    public private(set) var consecutiveStruggles: Int = 0
    /// True once the struggle cap has converted the remainder to walking — the switch is
    /// one-way for the session (no flapping back into run attempts).
    public private(set) var struggleConverted: Bool = false

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
        self.timeAboveTargetZone = 0
        self.convergedRunSeconds = nil
        self.convergedWalkSeconds = nil
        self.backfilledCooldownSeconds = 0
        self.effectivePlannedTotal = config.plan.plannedDuration
    }

    /// The phase currently in progress, or nil once the session is complete.
    public var currentPhase: IntervalPhase? {
        isComplete || segments.isEmpty ? nil : segments[currentIndex].phase
    }

    /// Run intervals in the session *as lived*: the working plan's run count after any
    /// time-box trimming. This — not the seed plan's count — is the honest
    /// `plannedRunIntervals` for progression: a session whose extended runs consumed the
    /// block in fewer intervals completed everything it planned.
    public var plannedRunIntervals: Int {
        segments.filter { $0.phase == .run }.count
    }

    /// The current segment's working target duration (after any adaptation), or nil if complete.
    public var currentTargetDuration: TimeInterval? {
        isComplete || segments.isEmpty ? nil : segments[currentIndex].targetDuration
    }

    /// Mean heart-rate recovery drop across the session's walks, or nil if never measurable.
    public var meanRecoveryDrop: Double? {
        recoveryDrops.isEmpty ? nil : recoveryDrops.reduce(0, +) / Double(recoveryDrops.count)
    }

    /// Backfill seconds actually *walked*, not merely planned. `backfilledCooldownSeconds` is
    /// recorded at cooldown entry; a user who ends mid-cooldown never walked the rest, and the
    /// summary must describe the session as lived, not the plan (N6).
    public var deliveredCooldownBackfill: TimeInterval {
        guard backfilledCooldownSeconds > 0 else { return 0 }
        guard !isComplete, currentPhase == .cooldownWalk else { return backfilledCooldownSeconds }
        let authored = segments[currentIndex].targetDuration - backfilledCooldownSeconds
        return min(backfilledCooldownSeconds, max(0, intervalElapsed - authored))
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
            if let zone = sample.zone {
                if zone == targetZone {
                    timeInTargetZone += deltaTime
                } else if zone > targetZone {
                    timeAboveTargetZone += deltaTime
                }
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
            // Upward convergence fires only on a NATURALLY completed demonstration (never on
            // a skip, never mid-segment): an extended run that ran to its stretched end raises
            // future runs — slew-limited, spikes are the injury risk; a walk that rode to the
            // cap unrecovered raises future walks (longer walks are the safe direction).
            if phase == .run, announcedThisSegment.contains(.extendedRun) {
                convergeFutureRuns(toward: roundedDown(intervalElapsed), upward: true)
            } else if phase == .walk, walkHitCapPending, !currentWalkDefied {
                convergeFutureWalks(toward: roundedUp(intervalElapsed), upward: true)
            }
            let transition = advance()
            return TickResult(transition: transition, isComplete: isComplete)
        }

        return TickResult()
    }

    /// Mark the current walk as run-through-by-choice (compliance monitor accepted). Its
    /// recovery numbers are an artifact of the choice: the walk still ends on its cap/timer,
    /// but it never converges future walks upward (the loop never fights the human).
    public mutating func markCurrentWalkDefied() {
        guard !isComplete, !segments.isEmpty, segments[currentIndex].phase == .walk else { return }
        currentWalkDefied = true
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
        // The skipped remainder was the user's choice — take it out of the backfill budget
        // so the cooldown never re-adds time the user deliberately cut.
        effectivePlannedTotal -= max(0, segments[currentIndex].targetDuration - intervalElapsed)
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
                // A back-off with no fast recovery since it last reset counts toward the
                // struggle cap (evidence: slow → shorten → walk). A subsequent fast recovery
                // will zero this — a lone back-off is the loop calibrating a too-long seed.
                consecutiveStruggles += 1
                // Downward convergence, one jump: the back-off point IS the demonstrated run
                // length (already a sustained-confirmed signal), so future runs retarget to it
                // and the countdown turns truthful from the next interval on.
                convergeFutureRuns(toward: max(policy.config.minRunDuration, roundedDown(intervalElapsed)),
                                   upward: false)
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
                    // Recovery came back — the run attempts are working. Reset the struggle
                    // ladder so it only trips on genuinely sustained failure.
                    consecutiveStruggles = 0
                }
                // Recovery demonstrated: future walks converge down to what the body needed
                // (rounded UP — a slightly longer walk is the safe direction).
                convergeFutureWalks(toward: max(policy.config.minWalkDuration, roundedUp(intervalElapsed)),
                                    upward: false)
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
        // The session is a TIME BOX, not an interval count. Before choosing the next segment,
        // reshape the remaining plan to fit the box: once the struggle cap trips, switch the
        // remainder to one continuous easy walk (evidence ladder's final rung); otherwise keep
        // offering shortened run cycles across the whole box — trim trailing cycles that overrun
        // (extensions/lengthened walks) and append shortened cycles that would otherwise let the
        // block finish early and hand the rest to walking.
        if !struggleConverted, consecutiveStruggles >= policy.config.struggleCap {
            convertRemainderToWalking()
        } else if !struggleConverted {
            fitCyclesToTimeBox()
        }
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
        currentWalkDefied = false

        let nextIndex = currentIndex + 1
        guard nextIndex < segments.count else {
            isComplete = true
            return nil
        }

        currentIndex = nextIndex
        if segments[currentIndex].phase == .run {
            // New run: peak tracking starts fresh (the previous walk's recovery math is done).
            peakRunHeartRate = nil
        } else if segments[currentIndex].phase == .cooldownWalk {
            backfillCooldown()
        }
        intervalElapsed = 0
        policy.resetAccumulators()
        announcedThisSegment.removeAll()
        return TransitionEvent(from: fromPhase, to: segments[currentIndex].phase)
    }

    /// Reshape the remaining run/walk cycles so the session keeps offering shortened runs
    /// across the whole time box. Adaptation grows *or* shrinks segments (extended/lengthened
    /// vs backed-off/recovered) but the plan's cycle count was sized for the *seed* durations —
    /// interval count is an artifact of the seeds, time is the prescription (the defect a real
    /// 20-minute run surfaced). Two directions, each moving only when it brings the projected
    /// total *closer* to the plan (the factory's own rounding rule, so a small mismatch never
    /// trades a whole cycle):
    ///   • **Overrun** (extensions / lengthened walks): drop trailing cycles.
    ///   • **Underrun** (backed-off runs finishing the block early): append shortened cycles at
    ///     the demonstrated run/walk durations, so a struggling-but-recovering runner keeps
    ///     getting run attempts to the end instead of an early hand-off to walking (the evidence:
    ///     keep offering shortened runs while recovery returns; walk is the *capped* fallback,
    ///     not the default fill).
    /// Silent, like convergence — the countdown and "what's left" stay truthful. Never touches
    /// the segment in progress; warmup/cooldown are never dropped. The two deadbands are
    /// symmetric (each acts only past half a cycle), so trim and append can't oscillate.
    private mutating func fitCyclesToTimeBox() {
        // Overrun: drop whole trailing cycles.
        while true {
            let overshoot = projectedRemainingTotal() - effectivePlannedTotal
            guard overshoot > 0,
                  let lastRun = segments.indices.last(where: {
                      $0 > currentIndex && segments[$0].phase == .run
                          && $0 + 1 < segments.count && segments[$0 + 1].phase == .walk
                  }) else { break }
            let cycleLength = segments[lastRun].targetDuration + segments[lastRun + 1].targetDuration
            guard overshoot > cycleLength / 2 else { break }
            segments.removeSubrange(lastRun...(lastRun + 1))
        }

        // Underrun: append shortened cycles at the demonstrated durations, before any cooldown.
        // Bounded by the box (each append shrinks the shortfall) — a hard iteration cap guards
        // against a pathological near-zero cycle.
        for _ in 0..<64 {
            guard let (run, walk) = demonstratedCycle() else { break }
            let cycleLength = run + walk
            let shortfall = effectivePlannedTotal - projectedRemainingTotal()
            guard cycleLength > 0, shortfall > cycleLength / 2 else { break }
            let insertAt = segments.firstIndex(where: { $0.phase == .cooldownWalk }) ?? segments.count
            segments.insert(contentsOf: [
                IntervalSegment(phase: .run, targetDuration: run),
                IntervalSegment(phase: .walk, targetDuration: walk),
            ], at: insertAt)
        }
    }

    /// Session time already elapsed plus every not-yet-started segment's target.
    private func projectedRemainingTotal() -> TimeInterval {
        sessionElapsed + segments[(currentIndex + 1)...].reduce(0) { $0 + $1.targetDuration }
    }

    /// The run/walk durations to fill the box with: the demonstrated (converged) values when the
    /// engine has learned them, else the most recent upcoming run/walk targets. nil when the
    /// remaining plan has no run/walk pair to model on (e.g. a continuous-run plan).
    private func demonstratedCycle() -> (run: TimeInterval, walk: TimeInterval)? {
        let run = convergedRunSeconds
            ?? segments[(currentIndex + 1)...].first(where: { $0.phase == .run })?.targetDuration
        let walk = convergedWalkSeconds
            ?? segments[(currentIndex + 1)...].first(where: { $0.phase == .walk })?.targetDuration
        guard let run, let walk else { return nil }
        return (run, walk)
    }

    /// The evidence ladder's final rung: after `struggleCap` back-offs with no recovery, replace
    /// the remaining run/walk block (and any authored cooldown) with **one** continuous easy walk
    /// filling the rest of the time box. A single decisive engine switch — a struggling novice is
    /// poorly served by more above-threshold run attempts (delayed autonomic recovery, homogeneous
    /// displeasure) and by being asked to keep self-adjusting. Uses `.cooldownWalk`, which the
    /// engine never adapts, so it stays a genuine sub-threshold walk to the end. One-way per
    /// session (`struggleConverted`).
    private mutating func convertRemainderToWalking() {
        struggleConverted = true
        let fill = max(0, effectivePlannedTotal - sessionElapsed)
        guard currentIndex + 1 < segments.count else {
            // Cap tripped on the final segment — nothing left to convert; let it complete.
            return
        }
        if fill > 0 {
            segments.replaceSubrange((currentIndex + 1)...,
                                     with: [IntervalSegment(phase: .cooldownWalk, targetDuration: fill)])
        } else {
            // Already at/over the box — just end after the current segment.
            segments.removeSubrange((currentIndex + 1)...)
        }
    }

    /// Extend the cooldown we just entered so total session time reaches the planned total —
    /// adaptation-shortened intervals become extra low-intensity walking (session volume is an
    /// adaptation driver; filling with easy walking is safe, filling with more running is not).
    /// Capped so the cooldown never exceeds min(authored + 10 min, authored × 2); the ×2 bound
    /// keeps compressed simulator cooldowns proportionate. Only ever extends: a session that ran
    /// long (extension) leaves the cooldown authored.
    private mutating func backfillCooldown() {
        let authored = segments[currentIndex].targetDuration
        let shortfall = effectivePlannedTotal - (sessionElapsed + authored)
        guard shortfall > 0 else { return }
        let cap = min(authored + 600, authored * 2)
        let newTarget = min(authored + shortfall, cap)
        guard newTarget > authored else { return }
        segments[currentIndex].targetDuration = newTarget
        backfilledCooldownSeconds = newTarget - authored
    }

    /// Round a demonstrated duration down to the convergence grid (runs — never credit
    /// undemonstrated seconds).
    private func roundedDown(_ value: TimeInterval) -> TimeInterval {
        let grid = policy.config.convergenceRounding
        guard grid > 0 else { return value }
        return (value / grid).rounded(.down) * grid
    }

    /// Round a demonstrated duration up to the convergence grid (walks — longer is safer).
    private func roundedUp(_ value: TimeInterval) -> TimeInterval {
        let grid = policy.config.convergenceRounding
        guard grid > 0 else { return value }
        return (value / grid).rounded(.up) * grid
    }

    /// Retarget future run segments toward a demonstrated duration. Downward converges in one
    /// jump (the safe direction); upward is slew-limited to min(+25%, `maxUpwardConvergenceStep`)
    /// per event. Both are silent — the current-segment events already announced the felt
    /// change; this only makes the upcoming countdowns truthful. Down-after-up always wins
    /// (min rules), expressing the back-off bias in-session.
    private mutating func convergeFutureRuns(toward demonstrated: TimeInterval, upward: Bool) {
        guard demonstrated > 0 else { return }
        var converged: TimeInterval?
        for index in segments.indices where index > currentIndex && segments[index].phase == .run {
            let existing = segments[index].targetDuration
            let newTarget: TimeInterval
            if upward {
                // Quantize the slew step to the convergence grid (at least one grid step, so a
                // small relative step can't round to zero) — every retarget stays on-grid.
                let rawStep = min(existing * 0.25, policy.config.maxUpwardConvergenceStep)
                let step = max(policy.config.convergenceRounding, roundedDown(rawStep))
                newTarget = min(demonstrated, existing + step)
            } else {
                newTarget = min(existing, demonstrated)
            }
            segments[index].targetDuration = newTarget
            converged = newTarget
        }
        if let converged {
            convergedRunSeconds = converged
        } else if !upward {
            // A back-off on the FINAL run still records its demonstration (the cross-session
            // converged path's honest input). An upward demonstration with no future segment
            // records nothing — recording the raw length would bypass the slew limit, and the
            // long run is already captured by `longestRunInterval` for the snap path.
            convergedRunSeconds = min(convergedRunSeconds ?? demonstrated, demonstrated)
        }
    }

    /// Retarget future walk segments toward a demonstrated duration. Same rules as runs except
    /// upward is a one-jump (walking longer is the safe direction), bounded by `maxWalkDuration`.
    private mutating func convergeFutureWalks(toward demonstrated: TimeInterval, upward: Bool) {
        guard demonstrated > 0 else { return }
        let bounded = min(demonstrated, policy.config.maxWalkDuration)
        var converged: TimeInterval?
        for index in segments.indices where index > currentIndex && segments[index].phase == .walk {
            let existing = segments[index].targetDuration
            let newTarget = upward ? max(existing, bounded) : min(existing, bounded)
            segments[index].targetDuration = newTarget
            converged = newTarget
        }
        if let converged {
            convergedWalkSeconds = converged
        } else if !upward {
            // Same rule as runs: a final-walk recovery still records; a final-walk cap-ride
            // records nothing (its struggle is already `walksHitCap`).
            convergedWalkSeconds = min(convergedWalkSeconds ?? bounded, bounded)
        }
    }
}
