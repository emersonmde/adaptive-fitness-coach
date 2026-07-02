import Foundation
import Testing
@testable import AdaptiveCore

struct RestRecoveryModelTests {

    // Defaults: drop 20 bpm, window 10s, floor max(45, 0.75×seed) ≤ seed, cap min(seed+60, 180) ≥ seed.

    private func run(
        seed: TimeInterval, peak: Double?,
        hr: @escaping (TimeInterval) -> Double?,
        maxSeconds: Int = 400
    ) -> (endedAt: TimeInterval, recovered: Bool?)? {
        var model = RestRecoveryModel(seedDuration: seed, peakHeartRate: peak)
        for _ in 0..<maxSeconds {
            let t = model.elapsed + 1
            if case let .endRest(recovered) = model.tick(heartRate: hr(t), deltaTime: 1) {
                return (model.elapsed, recovered)
            }
        }
        return nil
    }

    @Test func instantRecoveryStillWaitsForTheFloor() {
        // Recovered from second one (drop 30 ≥ 20): the rest still can't end before ¾ of the
        // seed — HR recovers faster than muscle, and the seed encodes the evidence-based time.
        let result = run(seed: 120, peak: 160, hr: { _ in 130 })
        #expect(result?.endedAt == 90)   // max(45, 0.75×120)
        #expect(result?.recovered == true)
    }

    @Test func shortSeedFloorsClampToTheSeed() {
        // A 20s authored rest: floor would be 45 but never exceeds the seed itself.
        let result = run(seed: 20, peak: 160, hr: { _ in 130 })
        #expect(result?.endedAt == 20)
        #expect(result?.recovered == true)
    }

    @Test func unrecoveredExtendsExactlyToTheCap() {
        // HR pinned near peak: extends past the seed, ends at seed+60 flagged unrecovered.
        let result = run(seed: 60, peak: 160, hr: { _ in 155 })
        #expect(result?.endedAt == 120)
        #expect(result?.recovered == false)
    }

    @Test func capNeverExceedsThreeMinutes() {
        let result = run(seed: 150, peak: 160, hr: { _ in 155 })
        #expect(result?.endedAt == 180)
        #expect(result?.recovered == false)
    }

    @Test func noHeartRateIsExactlyTheAuthoredTimer() {
        // N6: without a peak (or samples), the model is a plain seed-duration timer.
        let noPeak = run(seed: 60, peak: nil, hr: { _ in nil })
        #expect(noPeak?.endedAt == 60)
        #expect(noPeak?.recovered == nil)

        let noSamples = run(seed: 60, peak: 160, hr: { _ in nil })
        #expect(noSamples?.endedAt == 60) // peak alone proves nothing without live samples
    }

    @Test func flappingRecoveryNeverSustainsTheWindow() {
        // Alternating recovered/unrecovered seconds: the leaky window never fills, so the
        // rest runs to its seed and ends there (instantaneously recovered at that moment).
        var model = RestRecoveryModel(seedDuration: 60, peakHeartRate: 160)
        var endedAt: TimeInterval?
        for i in 0..<200 {
            let hr: Double = i % 2 == 0 ? 135 : 150
            if case .endRest = model.tick(heartRate: hr, deltaTime: 1) {
                endedAt = model.elapsed
                break
            }
        }
        #expect((endedAt ?? 0) >= 59) // never ends early on a flapping signal
    }

    @Test func recoveryLateInTheExtensionEndsRecovered() {
        // Unrecovered through the seed, recovers during the extension window.
        let result = run(seed: 60, peak: 160, hr: { t in t < 80 ? 155 : 130 })
        #expect(result?.recovered == true)
        #expect(result!.endedAt < 120) // before the cap
    }

    @Test func progressValuesAreClampedAndMeaningful() {
        var model = RestRecoveryModel(seedDuration: 60, peakHeartRate: 160)
        #expect(model.recoveryProgress == nil) // no sample yet
        _ = model.tick(heartRate: 150, deltaTime: 1)
        #expect(model.recoveryProgress == 0.5) // 10 of 20 bpm dropped
        _ = model.tick(heartRate: 120, deltaTime: 1)
        #expect(model.recoveryProgress == 1.0) // clamped at full
        #expect(model.timeProgress > 0 && model.timeProgress <= 1)
    }
}
