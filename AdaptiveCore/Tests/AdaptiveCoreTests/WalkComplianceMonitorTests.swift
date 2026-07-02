import Foundation
import Testing
@testable import AdaptiveCore

struct WalkComplianceMonitorTests {

    // Defaults: threshold 140, grace 8, stale 6, nudge interval 6, max 3.

    @Test func stillRunningAfterGraceMismatchesAndNudges() {
        var monitor = WalkComplianceMonitor()
        monitor.walkStarted(at: 100)
        monitor.recordCadence(155, at: 107)
        let during = monitor.assess(at: 107) // inside the grace period
        #expect(during == .init(isMismatched: false, shouldNudge: false))

        monitor.recordCadence(155, at: 109)
        let after = monitor.assess(at: 109)
        #expect(after.isMismatched)
        #expect(after.shouldNudge) // first nudge granted immediately after grace
    }

    @Test func slowingDownWithinGraceNeverNags() {
        var monitor = WalkComplianceMonitor()
        monitor.walkStarted(at: 100)
        monitor.recordCadence(150, at: 102) // still decelerating
        monitor.recordCadence(110, at: 106) // walking now
        let a = monitor.assess(at: 110)
        #expect(a == .init(isMismatched: false, shouldNudge: false))
    }

    @Test func nudgesAreRateLimitedAndCapped() {
        var monitor = WalkComplianceMonitor()
        monitor.walkStarted(at: 0)
        var nudges = 0
        for t in stride(from: 8.0, through: 60.0, by: 1.0) {
            monitor.recordCadence(150, at: t)
            let a = monitor.assess(at: t)
            if a.shouldNudge { nudges += 1 }
            #expect(a.isMismatched) // the visual pulse persists the whole time...
        }
        #expect(nudges == 3) // ...but the haptic stops nagging after the cap (Q5)
    }

    @Test func staleCadenceSaysNothing() {
        var monitor = WalkComplianceMonitor()
        monitor.walkStarted(at: 0)
        monitor.recordCadence(150, at: 8)
        let fresh = monitor.assess(at: 9)
        #expect(fresh.isMismatched)
        // 10s later with no new samples: the old reading proves nothing (N6).
        let stale = monitor.assess(at: 19)
        #expect(!stale.isMismatched)
    }

    @Test func newWalkResetsTheNudgeBudget() {
        var monitor = WalkComplianceMonitor()
        monitor.walkStarted(at: 0)
        for t in stride(from: 8.0, through: 40.0, by: 1.0) {
            monitor.recordCadence(150, at: t)
            _ = monitor.assess(at: t) // burn all three nudges
        }
        monitor.walkEnded()
        monitor.walkStarted(at: 100)
        monitor.recordCadence(150, at: 109)
        let a = monitor.assess(at: 109)
        #expect(a.shouldNudge) // fresh walk, fresh budget
    }

    @Test func noWalkNoAssessment() {
        var monitor = WalkComplianceMonitor()
        monitor.recordCadence(160, at: 5)
        let a = monitor.assess(at: 10)
        #expect(a == .init(isMismatched: false, shouldNudge: false))
    }
}
