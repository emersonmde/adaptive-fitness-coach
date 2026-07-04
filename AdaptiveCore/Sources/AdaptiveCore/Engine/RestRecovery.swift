import Foundation

/// Decides when a between-set rest is over: **time-based per the evidence, refined by heart
/// rate within a bounded band** around the authored seed.
///
/// The physiology that actually governs between-set readiness — phosphocreatine resynthesis
/// (~85–90% recovered by 3 minutes; Harris et al., Pflügers Arch 1976) — is unobservable on a
/// wrist. The citable rest-interval evidence is time-based: ≥2 minutes benefits compound-lift
/// strength/hypertrophy (Schoenfeld et al., JSCR 30(7), 2016; Grgic et al. 2017 review), while
/// 60–90s is adequate for isolation work and beginners (de Salles & Simão, Sports Medicine
/// 39(9), 2009). So the authored rest card is the seed, and heart-rate recovery (the Cole 1999
/// HRR construct, same as the run side) only *trims* the rest when the user is clearly
/// recovered — never below the floor — or *extends* it while systemically elevated, never past
/// the cap. With no HR signal the rest is exactly the authored timer (N6).
public struct RestRecoveryConfig: Sendable, Hashable {
    /// HR drop from the preceding set's peak that counts as recovered (Cole et al., NEJM 1999
    /// grounds the construct; 20 bpm matches the run side's bar).
    public var recoveryDropBPM: Double
    /// Sustained seconds of the recovered signal before the rest can end early.
    public var recoverWindow: TimeInterval
    /// Floor fraction of the seed the rest can never trim below (protects the local-recovery
    /// time the seed encodes — HR recovers faster than muscle).
    public var floorFraction: Double
    /// Absolute floor in seconds.
    public var floorSeconds: TimeInterval
    /// Extension allowance past the seed while unrecovered, and the absolute cap.
    public var extensionSeconds: TimeInterval
    public var capSeconds: TimeInterval

    public init(
        recoveryDropBPM: Double = 20,
        recoverWindow: TimeInterval = 10,
        floorFraction: Double = 0.75,
        floorSeconds: TimeInterval = 45,
        extensionSeconds: TimeInterval = 60,
        capSeconds: TimeInterval = 180
    ) {
        self.recoveryDropBPM = recoveryDropBPM
        self.recoverWindow = recoverWindow
        self.floorFraction = floorFraction
        self.floorSeconds = floorSeconds
        self.extensionSeconds = extensionSeconds
        self.capSeconds = capSeconds
    }
}

/// Pure, clock-free rest model ticked by the session manager (mirrors the interval engine's
/// discipline — the caller supplies deltaTime, so it is deterministic and testable).
public struct RestRecoveryModel: Sendable {
    public let config: RestRecoveryConfig
    /// The authored rest card's seconds — the evidence-anchored seed.
    public let seedDuration: TimeInterval
    /// Peak heart rate during the preceding set, or nil when no HR was observed (→ pure timer).
    public let peakHeartRate: Double?

    public private(set) var elapsed: TimeInterval = 0
    /// Leaky accumulator of the recovered signal (same hysteresis as `AdaptationPolicy`).
    private var timeRecovered: TimeInterval = 0
    private var lastHeartRate: Double?

    public init(config: RestRecoveryConfig = RestRecoveryConfig(), seedDuration: TimeInterval, peakHeartRate: Double?) {
        self.config = config
        self.seedDuration = seedDuration
        self.peakHeartRate = peakHeartRate
    }

    public enum Decision: Sendable, Hashable {
        case resting
        /// The rest is over. `recovered` — true: HR confirmed recovery (possibly early);
        /// false: hit the cap still elevated; nil: no HR signal, plain timer expiry (N6).
        case endRest(recovered: Bool?)
    }

    /// The earliest the rest may end, even fully recovered: never trim below ¾ of the seed
    /// (min 45s), and a floor never exceeds the seed itself (a short authored rest stays short).
    public var minDuration: TimeInterval {
        min(seedDuration, max(config.floorSeconds, seedDuration * config.floorFraction))
    }

    /// The latest the rest may run, even unrecovered: seed + 60s, capped at 3 minutes, and a
    /// cap never undercuts the seed (a long authored rest is honored).
    public var maxDuration: TimeInterval {
        max(seedDuration, min(seedDuration + config.extensionSeconds, config.capSeconds))
    }

    /// 0…1 progress of HR recovery toward the drop threshold, or nil when unmeasurable —
    /// drives the recovery ring.
    public var recoveryProgress: Double? {
        guard let peak = peakHeartRate, let hr = lastHeartRate else { return nil }
        return min(max((peak - hr) / config.recoveryDropBPM, 0), 1)
    }

    /// 0…1 progress of plain time toward the seed — the no-HR fallback ring.
    public var timeProgress: Double {
        seedDuration > 0 ? min(elapsed / seedDuration, 1) : 1
    }

    /// Seconds until the rest would end on time alone (shrinks toward 0 at the seed; during
    /// an unrecovered extension it counts toward the cap). Seed-based until the seed
    /// elapses — flipping on the instantaneous HR signal made the countdown jump ±60s while
    /// HR hovered at the threshold mid-rest.
    public var remaining: TimeInterval {
        if elapsed < seedDuration { return seedDuration - elapsed }
        if peakHeartRate == nil || isRecoveredNow { return 0 }
        return max(maxDuration - elapsed, 0)
    }

    /// The instantaneous recovered signal (unsmoothed — the decision uses the leaky window).
    public var isRecoveredNow: Bool {
        guard let peak = peakHeartRate, let hr = lastHeartRate else { return false }
        return peak - hr >= config.recoveryDropBPM
    }

    /// Advance the rest by `deltaTime` with the latest heart rate (nil when no fresh signal).
    public mutating func tick(heartRate: Double?, deltaTime: TimeInterval) -> Decision {
        guard deltaTime > 0 else { return .resting }
        elapsed += deltaTime
        if let heartRate { lastHeartRate = heartRate }

        // No usable HR pair → the authored timer, exactly (N6).
        guard let peak = peakHeartRate, let hr = lastHeartRate else {
            return elapsed >= seedDuration ? .endRest(recovered: nil) : .resting
        }

        let recovered = peak - hr >= config.recoveryDropBPM
        timeRecovered = recovered ? timeRecovered + deltaTime : max(0, timeRecovered - deltaTime)

        if timeRecovered >= config.recoverWindow, elapsed >= minDuration {
            return .endRest(recovered: true)
        }
        if elapsed >= seedDuration, recovered {
            return .endRest(recovered: true)
        }
        if elapsed >= maxDuration {
            return .endRest(recovered: false)
        }
        return .resting
    }
}
