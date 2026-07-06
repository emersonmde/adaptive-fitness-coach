import Foundation
import Testing
@testable import Adaptive_Fitness_Coach_Watch_App

/// The quick-log complication's hand-off (`afcoach://quicklog` → `WorkoutLaunchRequest` →
/// the session container's sheet). The SwiftUI wiring can't be driven headlessly (watchOS
/// exposes no LS scheme opening and XCUI taps don't fire on watch — see WatchSessionUITests),
/// so the consume discipline is pinned here: exactly-once, and a dropped request (session in
/// progress) must not linger and pop a sheet later.
@MainActor
struct QuickLogLaunchRequestTests {

    @Test func consumeIsExactlyOnce() {
        let request = WorkoutLaunchRequest.shared
        request.requestQuickLog()
        #expect(request.consumeQuickLog())
        #expect(!request.consumeQuickLog(), "a second consume must see nothing")
    }

    @Test func startsUnrequested() {
        // Order-independent with the test above: consume always resets, so a fresh check
        // (after any prior test consumed) reads false.
        let request = WorkoutLaunchRequest.shared
        #expect(!request.consumeQuickLog())
    }

    @Test func quickLogAndRoutineRequestsAreIndependent() {
        let request = WorkoutLaunchRequest.shared
        request.request(routineId: "abc")
        #expect(!request.consumeQuickLog(), "a routine request must not open the meal sheet")
        #expect(request.consume() == "abc")
    }
}
