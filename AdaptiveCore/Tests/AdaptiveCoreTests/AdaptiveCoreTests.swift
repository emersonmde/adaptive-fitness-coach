import Foundation
import Testing
@testable import AdaptiveCore

/// Sanity check that the default beginner seed is a usable, non-degenerate plan.
struct AdaptiveCoreTests {
    @Test func defaultSeedPlanIsRunnable() {
        let plan = IntervalPlan.beginnerRunWalk()
        #expect(plan.runIntervalCount > 0)
        #expect(plan.plannedDuration > 0)
        #expect(plan.segments.first?.phase == .warmupWalk)
    }
}
