import Foundation
import Testing
@testable import AdaptiveCore

struct AdaptationPolicyTests {

    private let targetZone = 2

    /// Drive `evaluateRun` for `seconds` at a fixed zone, returning the last decision.
    /// Stops early and returns the first non-`keepGoing` decision if one occurs.
    private func runFor(
        _ policy: inout AdaptationPolicy,
        zone: Int,
        seconds: Int,
        segmentTarget: TimeInterval,
        startElapsed: TimeInterval = 0
    ) -> (decision: RunDecision, atElapsed: TimeInterval) {
        var elapsed = startElapsed
        for _ in 0..<seconds {
            elapsed += 1
            let d = policy.evaluateRun(
                currentZone: zone, targetZone: targetZone,
                intervalElapsed: elapsed, segmentTarget: segmentTarget, deltaTime: 1
            )
            if d != .keepGoing { return (d, elapsed) }
        }
        return (.keepGoing, elapsed)
    }

    /// Drive `evaluateWalk` for `seconds` with fixed signals, returning the first decision.
    private func walkFor(
        _ policy: inout AdaptationPolicy,
        zone: Int?,
        heartRate: Double? = nil,
        peakRunHeartRate: Double? = nil,
        seconds: Int,
        segmentTarget: TimeInterval,
        startElapsed: TimeInterval = 0
    ) -> (decision: WalkDecision, atElapsed: TimeInterval) {
        var elapsed = startElapsed
        for _ in 0..<seconds {
            elapsed += 1
            let d = policy.evaluateWalk(
                currentZone: zone, heartRate: heartRate, peakRunHeartRate: peakRunHeartRate,
                targetZone: targetZone,
                intervalElapsed: elapsed, segmentTarget: segmentTarget, deltaTime: 1
            )
            if d != .keepGoing { return (d, elapsed) }
        }
        return (.keepGoing, elapsed)
    }

    // MARK: - Backing off (shorten run)

    @Test func sustainedHotZoneShortensRun() {
        var policy = AdaptationPolicy() // backOff 20s, minRun 20s
        // Zone 3 (above target 2, below the hard-ceiling delta) for the whole interval.
        let result = runFor(&policy, zone: 3, seconds: 60, segmentTarget: 60)
        #expect(result.decision == .shorten)
        // Fires once both the 20s window AND the 20s minimum-run are satisfied.
        #expect(result.atElapsed == 20)
    }

    @Test func briefHotSpikeDoesNotShortenRun() {
        var policy = AdaptationPolicy()
        // 10s hot — shorter than the 20s back-off window — then back in zone.
        _ = runFor(&policy, zone: 3, seconds: 10, segmentTarget: 60)
        let after = runFor(&policy, zone: 2, seconds: 40, segmentTarget: 60, startElapsed: 10)
        #expect(after.decision == .keepGoing)
    }

    @Test func hotZoneBeforeMinimumRunDurationWaits() {
        // Even with a short back-off window, a run cannot be cut below minRunDuration.
        let config = AdaptationConfig(backOffWindow: 5, hardBackOffMinRun: 30, minRunDuration: 30)
        var policy = AdaptationPolicy(config: config)
        let result = runFor(&policy, zone: 5, seconds: 60, segmentTarget: 60)
        #expect(result.decision == .shorten)
        #expect(result.atElapsed == 30) // held off until the minimum, not the 5s window
    }

    @Test func balancedFlappingDoesNotShorten() {
        // HR riding the zone boundary 50/50 (5s hot / 5s in-zone) is ambiguous effort: with the
        // leaky-integrator hysteresis the hot accumulator oscillates and never reaches the
        // window, so no back-off fires. (Zone 3 — the hard ceiling is a separate fast path.)
        var policy = AdaptationPolicy()
        var elapsed: TimeInterval = 0
        var sawShorten = false
        for _ in 0..<6 {
            for zone in [3, 3, 3, 3, 3, 2, 2, 2, 2, 2] {
                elapsed += 1
                if policy.evaluateRun(currentZone: zone, targetZone: targetZone,
                                      intervalElapsed: elapsed, segmentTarget: 400, deltaTime: 1) == .shorten {
                    sawShorten = true
                }
            }
        }
        #expect(!sawShorten)
    }

    @Test func mostlyHotEventuallyShortensDespiteBriefDips() {
        // 10s hot / 1s dip, repeated: genuinely mostly-hot. Hysteresis lets the net-hot time
        // accumulate across the brief dips and eventually backs off (the OLD hard-reset logic
        // would have been permanently defeated by the 1s dips — the bug this fixes).
        var policy = AdaptationPolicy()
        var elapsed: TimeInterval = 0
        var sawShorten = false
        for _ in 0..<5 {
            for zone in Array(repeating: 3, count: 10) + [2] {
                elapsed += 1
                if policy.evaluateRun(currentZone: zone, targetZone: targetZone,
                                      intervalElapsed: elapsed, segmentTarget: 400, deltaTime: 1) == .shorten {
                    sawShorten = true
                }
            }
        }
        #expect(sawShorten)
    }

    @Test func briefDipNearWindowCompletionStillShortens() {
        // A single 1s dip just before the window completes must not wipe a nearly-full window.
        var policy = AdaptationPolicy(config: AdaptationConfig(backOffWindow: 20, minRunDuration: 2))
        var elapsed: TimeInterval = 0
        var decision: RunDecision = .keepGoing
        for zone in Array(repeating: 3, count: 19) + [2] + [3, 3] {
            elapsed += 1
            decision = policy.evaluateRun(currentZone: zone, targetZone: targetZone,
                                          intervalElapsed: elapsed, segmentTarget: 400, deltaTime: 1)
            if decision == .shorten { break }
        }
        #expect(decision == .shorten)
    }

    // MARK: - Hard ceiling (far above target)

    @Test func farAboveTargetShortensOnTheFastPath() {
        var policy = AdaptationPolicy() // hard window 8s, hard minRun 15s, delta 2
        // Zone 4 against target 2 = far above → fires at max(8s window, 15s minRun) = 15s,
        // well before the standard 20s back-off window.
        let result = runFor(&policy, zone: 4, seconds: 60, segmentTarget: 60)
        #expect(result.decision == .shorten)
        #expect(result.atElapsed == 15)
    }

    @Test func oneZoneAboveStillNeedsTheStandardWindow() {
        var policy = AdaptationPolicy()
        // Zone 3 (only one above target) never touches the fast path → standard 20s.
        let result = runFor(&policy, zone: 3, seconds: 60, segmentTarget: 60)
        #expect(result.decision == .shorten)
        #expect(result.atElapsed == 20)
    }

    @Test func hardCeilingAccumulatorDecaysAcrossDips() {
        var policy = AdaptationPolicy(config: AdaptationConfig(hardBackOffWindow: 8, hardBackOffMinRun: 2))
        var elapsed: TimeInterval = 0
        var decision: RunDecision = .keepGoing
        // 7s redline, 1s dip to zone 3, 2s redline: leaky accumulator = 7 - 1 + 2 = 8 → fires.
        for zone in Array(repeating: 4, count: 7) + [3] + [4, 4] {
            elapsed += 1
            decision = policy.evaluateRun(currentZone: zone, targetZone: targetZone,
                                          intervalElapsed: elapsed, segmentTarget: 400, deltaTime: 1)
            if decision == .shorten { break }
        }
        #expect(decision == .shorten)
        #expect(elapsed == 10)
    }

    // MARK: - Extension is opt-in (off by default)

    @Test func comfortableRunIsNeverExtendedByDefault() {
        // HR lag reads as comfort in a deconditioned runner — the failure that motivated
        // gating extension off. Comfortable zone forever must keep the planned duration.
        var policy = AdaptationPolicy()
        let result = runFor(&policy, zone: 1, seconds: 300, segmentTarget: 60)
        #expect(result.decision == .keepGoing)
    }

    @Test func sustainedComfortableZoneExtendsRunAtPlannedEndWhenEnabled() {
        var policy = AdaptationPolicy(config: AdaptationConfig(allowRunExtension: true)) // extend window 45s
        let result = runFor(&policy, zone: 1, seconds: 90, segmentTarget: 60)
        #expect(result.decision == .extend)
        #expect(result.atElapsed == 60) // not before the planned end
    }

    @Test func comfortableButBeforePlannedEndKeepsGoing() {
        var policy = AdaptationPolicy(config: AdaptationConfig(allowRunExtension: true))
        // Comfortable but planned run is long (200s): never reaches planned end in window.
        let result = runFor(&policy, zone: 1, seconds: 120, segmentTarget: 200)
        #expect(result.decision == .keepGoing)
    }

    @Test func atPlannedEndWithoutSustainedComfortDoesNotExtend() {
        var policy = AdaptationPolicy(config: AdaptationConfig(allowRunExtension: true, extendWindow: 45))
        // Only 30s of comfort accumulated by the planned end (<45s window) → no extend.
        _ = runFor(&policy, zone: 3, seconds: 30, segmentTarget: 60) // hot first 30s
        let result = runFor(&policy, zone: 1, seconds: 30, segmentTarget: 60, startElapsed: 30)
        #expect(result.decision == .keepGoing)
    }

    // MARK: - Bias asymmetry

    @Test func backingOffFiresSoonerThanExtending() {
        // The same elapsed comfort/discomfort: backing off should trigger before extending would.
        var hot = AdaptationPolicy()
        let shorten = runFor(&hot, zone: 3, seconds: 60, segmentTarget: 1) // tiny target so end isn't the gate
        var cool = AdaptationPolicy(config: AdaptationConfig(allowRunExtension: true))
        let extend = runFor(&cool, zone: 1, seconds: 60, segmentTarget: 1)
        #expect(shorten.decision == .shorten)
        #expect(extend.decision == .extend)
        // Back-off window (20s) is strictly shorter than extend window (45s).
        #expect(shorten.atElapsed < extend.atElapsed)
    }

    @Test func endingAWalkEarlyIsSlowerThanEndingARun() {
        // Cutting a walk short raises effort; its floor must exceed the run back-off window.
        let config = AdaptationConfig()
        #expect(config.minWalkDuration > config.backOffWindow)
    }

    // MARK: - Walk recovery (HR drop from run peak)

    @Test func heartRateDropEndsTheWalk() {
        var policy = AdaptationPolicy() // drop 20bpm, recoverWindow 10s, minWalk 60s
        // HR 135 against a run peak of 160 = 25bpm drop → recovered. The confirm window (10s)
        // is inside the 60s floor, so the walk ends exactly at the floor.
        let result = walkFor(&policy, zone: 2, heartRate: 135, peakRunHeartRate: 160,
                             seconds: 120, segmentTarget: 90)
        #expect(result.decision == .shorten)
        #expect(result.atElapsed == 60)
    }

    @Test func insufficientDropInTargetZoneLengthensTheWalk() {
        var policy = AdaptationPolicy()
        // HR only 10bpm below peak and zone still AT target (not below): unrecovered — this is
        // exactly the "HR sits in the green band while gassed" case. Walk extends at planned end.
        let result = walkFor(&policy, zone: 2, heartRate: 150, peakRunHeartRate: 160,
                             seconds: 120, segmentTarget: 90)
        #expect(result.decision == .lengthen)
        #expect(result.atElapsed == 90)
    }

    @Test func zoneBelowTargetCountsAsRecoveredWithoutHeartRate() {
        var policy = AdaptationPolicy()
        // No raw HR (or no recorded peak), but the zone fell below target → recovered.
        let result = walkFor(&policy, zone: 1, seconds: 120, segmentTarget: 90)
        #expect(result.decision == .shorten)
        #expect(result.atElapsed == 60)
    }

    @Test func zoneAtTargetAloneIsNotRecovered() {
        var policy = AdaptationPolicy()
        // Zone equal to target with no HR signal: ambiguous → never shorten; lengthen at end.
        let result = walkFor(&policy, zone: 2, seconds: 120, segmentTarget: 90)
        #expect(result.decision == .lengthen)
    }

    @Test func noSignalsKeepsThePlannedWalk() {
        var policy = AdaptationPolicy()
        // Neither zone nor HR: fixed-interval fallback (N6) — no decision ever fires.
        let result = walkFor(&policy, zone: nil, seconds: 200, segmentTarget: 90)
        #expect(result.decision == .keepGoing)
    }

    @Test func recoverySignalNeedsToSustainTheConfirmWindow() {
        var policy = AdaptationPolicy(config: AdaptationConfig(recoverWindow: 10, minWalkDuration: 15))
        var elapsed: TimeInterval = 0
        var decision: WalkDecision = .keepGoing
        // Alternating recovered/unrecovered (drop 25 vs drop 5) never sustains the 10s window.
        for i in 0..<60 {
            elapsed += 1
            let hr: Double = i % 2 == 0 ? 135 : 155
            decision = policy.evaluateWalk(currentZone: 2, heartRate: hr, peakRunHeartRate: 160,
                                           targetZone: targetZone,
                                           intervalElapsed: elapsed, segmentTarget: 400, deltaTime: 1)
            if decision != .keepGoing { break }
        }
        #expect(decision == .keepGoing)
    }

    @Test func shortenWalkRespectsMinimumWalkDuration() {
        var policy = AdaptationPolicy(config: AdaptationConfig(recoverWindow: 5, minWalkDuration: 40))
        let result = walkFor(&policy, zone: 1, seconds: 90, segmentTarget: 90)
        #expect(result.decision == .shorten)
        #expect(result.atElapsed == 40) // held until minWalkDuration, not the 5s window
    }

    // MARK: - Reset

    @Test func resetClearsAccumulators() {
        var policy = AdaptationPolicy()
        _ = runFor(&policy, zone: 3, seconds: 15, segmentTarget: 200) // 15s hot, not yet shorten
        policy.resetAccumulators()
        // After reset, another 15s hot still shouldn't shorten (needs 20s sustained again).
        let result = runFor(&policy, zone: 3, seconds: 15, segmentTarget: 200, startElapsed: 15)
        #expect(result.decision == .keepGoing)
    }
}
