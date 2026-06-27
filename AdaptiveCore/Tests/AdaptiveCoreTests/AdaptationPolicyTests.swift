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

    private func walkFor(
        _ policy: inout AdaptationPolicy,
        zone: Int,
        seconds: Int,
        segmentTarget: TimeInterval,
        startElapsed: TimeInterval = 0
    ) -> (decision: WalkDecision, atElapsed: TimeInterval) {
        var elapsed = startElapsed
        for _ in 0..<seconds {
            elapsed += 1
            let d = policy.evaluateWalk(
                currentZone: zone, targetZone: targetZone,
                intervalElapsed: elapsed, segmentTarget: segmentTarget, deltaTime: 1
            )
            if d != .keepGoing { return (d, elapsed) }
        }
        return (.keepGoing, elapsed)
    }

    // MARK: - Backing off (shorten run)

    @Test func sustainedHotZoneShortensRun() {
        var policy = AdaptationPolicy() // backOff 20s, minRun 20s
        // Zone 4 (above target 2) for the whole interval; planned 60s.
        let result = runFor(&policy, zone: 4, seconds: 60, segmentTarget: 60)
        #expect(result.decision == .shorten)
        // Fires once both the 20s window AND the 20s minimum-run are satisfied.
        #expect(result.atElapsed == 20)
    }

    @Test func briefHotSpikeDoesNotShortenRun() {
        var policy = AdaptationPolicy()
        // 10s hot — shorter than the 20s back-off window — then back in zone.
        _ = runFor(&policy, zone: 4, seconds: 10, segmentTarget: 60)
        let after = runFor(&policy, zone: 2, seconds: 40, segmentTarget: 60, startElapsed: 10)
        #expect(after.decision == .keepGoing)
    }

    @Test func hotZoneBeforeMinimumRunDurationWaits() {
        // Even with a short back-off window, a run cannot be cut below minRunDuration.
        var config = AdaptationConfig(backOffWindow: 5, minRunDuration: 30)
        var policy = AdaptationPolicy(config: config)
        let result = runFor(&policy, zone: 5, seconds: 60, segmentTarget: 60)
        #expect(result.decision == .shorten)
        #expect(result.atElapsed == 30) // held off until minRunDuration, not the 5s window
    }

    @Test func balancedFlappingDoesNotShorten() {
        // HR riding the zone boundary 50/50 (5s hot / 5s in-zone) is ambiguous effort: with the
        // leaky-integrator hysteresis the hot accumulator oscillates and never reaches the
        // window, so no back-off fires.
        var policy = AdaptationPolicy()
        var elapsed: TimeInterval = 0
        var sawShorten = false
        for _ in 0..<6 {
            for zone in [4, 4, 4, 4, 4, 2, 2, 2, 2, 2] {
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
            for zone in Array(repeating: 4, count: 10) + [2] {
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
        for zone in Array(repeating: 4, count: 19) + [2] + [4, 4] {
            elapsed += 1
            decision = policy.evaluateRun(currentZone: zone, targetZone: targetZone,
                                          intervalElapsed: elapsed, segmentTarget: 400, deltaTime: 1)
            if decision == .shorten { break }
        }
        #expect(decision == .shorten)
    }

    // MARK: - Extending (run)

    @Test func sustainedComfortableZoneExtendsRunAtPlannedEnd() {
        var policy = AdaptationPolicy() // extend window 45s
        // Comfortable (zone 1) for a 60s planned run. Extend should fire at the planned end.
        let result = runFor(&policy, zone: 1, seconds: 90, segmentTarget: 60)
        #expect(result.decision == .extend)
        #expect(result.atElapsed == 60) // not before the planned end
    }

    @Test func comfortableButBeforePlannedEndKeepsGoing() {
        var policy = AdaptationPolicy()
        // Comfortable but planned run is long (200s): never reaches planned end in window.
        let result = runFor(&policy, zone: 1, seconds: 120, segmentTarget: 200)
        #expect(result.decision == .keepGoing)
    }

    @Test func atPlannedEndWithoutSustainedComfortDoesNotExtend() {
        var config = AdaptationConfig(extendWindow: 45)
        var policy = AdaptationPolicy(config: config)
        // Only 30s of comfort accumulated by the planned end (<45s window) → no extend.
        _ = runFor(&policy, zone: 4, seconds: 30, segmentTarget: 60) // hot first 30s
        let result = runFor(&policy, zone: 1, seconds: 30, segmentTarget: 60, startElapsed: 30)
        #expect(result.decision == .keepGoing)
    }

    // MARK: - Bias asymmetry

    @Test func backingOffFiresSoonerThanExtending() {
        // The same elapsed comfort/discomfort: backing off should trigger before extending would.
        var hot = AdaptationPolicy()
        let shorten = runFor(&hot, zone: 4, seconds: 60, segmentTarget: 1) // tiny target so end isn't the gate
        var cool = AdaptationPolicy()
        let extend = runFor(&cool, zone: 1, seconds: 60, segmentTarget: 1)
        #expect(shorten.decision == .shorten)
        #expect(extend.decision == .extend)
        // Back-off window (20s) is strictly shorter than extend window (45s).
        #expect(shorten.atElapsed < extend.atElapsed)
    }

    // MARK: - Walk lengthening

    @Test func notRecoveredByEndLengthensWalk() {
        var policy = AdaptationPolicy()
        // Still hot (zone 4) through the whole planned 90s walk → lengthen at the end.
        let result = walkFor(&policy, zone: 4, seconds: 90, segmentTarget: 90)
        #expect(result.decision == .lengthen)
        #expect(result.atElapsed == 90)
    }

    @Test func recoveredWalkShortensRatherThanLengthens() {
        var policy = AdaptationPolicy()
        // Recovered (zone 2) — recoverWindow(30) triggers an early shorten before the 90s end,
        // i.e. a recovered walk is cut short, never lengthened.
        let result = walkFor(&policy, zone: 2, seconds: 90, segmentTarget: 90)
        #expect(result.decision == .shorten)
    }

    // MARK: - Walk shortening

    @Test func quickRecoveryShortensWalk() {
        var policy = AdaptationPolicy() // recoverWindow 30s, minWalk 15s
        let result = walkFor(&policy, zone: 1, seconds: 90, segmentTarget: 90)
        #expect(result.decision == .shorten)
        #expect(result.atElapsed == 30) // recoverWindow reached (>= minWalk)
    }

    @Test func shortenWalkRespectsMinimumWalkDuration() {
        var config = AdaptationConfig(recoverWindow: 5, minWalkDuration: 40)
        var policy = AdaptationPolicy(config: config)
        let result = walkFor(&policy, zone: 1, seconds: 90, segmentTarget: 90)
        #expect(result.decision == .shorten)
        #expect(result.atElapsed == 40) // held until minWalkDuration, not the 5s window
    }

    @Test func walkShortenWindowIsLongerThanRunBackOff() {
        // Cutting a walk short (raises effort) should take longer to confirm than easing off.
        let config = AdaptationConfig()
        #expect(config.recoverWindow > config.backOffWindow)
    }

    // MARK: - Reset

    @Test func resetClearsAccumulators() {
        var policy = AdaptationPolicy()
        _ = runFor(&policy, zone: 4, seconds: 15, segmentTarget: 200) // 15s hot, not yet shorten
        policy.resetAccumulators()
        // After reset, another 15s hot still shouldn't shorten (needs 20s sustained again).
        let result = runFor(&policy, zone: 4, seconds: 15, segmentTarget: 200, startElapsed: 15)
        #expect(result.decision == .keepGoing)
    }
}
