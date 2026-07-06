import XCTest

/// End-to-end coverage of the on-watch sessions against scripted backends (no HealthKit).
///
/// **watchOS UI-testing limitation:** the in-workout screens are a paged `TabView`
/// (`PUICPageViewController`), and watchOS does not deliver XCUI synthesized taps/presses to
/// buttons inside it — so a flow that needs a mid-session button (strength's "Done set", a swipe to
/// "End") can't be driven tap-by-tap here. The **run** flow needs no taps (it plays itself to the
/// summary), so it's a true launch→session→summary E2E below. Strength card-by-card progression —
/// advance, rest, hold, summary, weight-across-rounds — is covered headlessly by the manager-level
/// `StrengthFlowTests`, which drive the same code without the TabView in the way.
///
/// 2026-07-06, watchOS 27 sim: the limitation is broader than the TabView — synthesized taps
/// (element AND coordinate) also fail to fire a plain `Button` inside a `NavigationStack`
/// (tried for the quick-log flow: AX tree healthy, button enabled/hittable, action never ran).
/// Treat watch UI tests as tap-free on this toolchain; tap-driven flows verify manually via
/// the `-simulate*` launch args.
final class WatchSessionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arg: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [arg]
        app.launch()
        return app
    }

    /// `-simulateWorkout` auto-starts a short scripted adaptive run and plays it to completion with
    /// no interaction — a full launch → live session → "Saved to Health" summary end-to-end.
    func testRunSessionPlaysToSummary() throws {
        let app = launch("-simulateWorkout")
        XCTAssertTrue(app.staticTexts["Saved to Health"].waitForExistence(timeout: 120),
                      "the scripted run should play through to the saved-to-Health summary")
    }

    /// `-simulateStrength` now self-drives the whole adaptive loop (sets auto-complete, the
    /// HR-bounded rest runs its recovery ring, the hold auto-runs) to the summary — a full
    /// launch → sets → adaptive rest → hold → "Done" E2E with no taps (see the limitation
    /// note above; per-tap logic is covered by `StrengthFlowTests`).
    func testStrengthSessionPlaysToSummary() throws {
        let app = launch("-simulateStrength")
        XCTAssertTrue(app.staticTexts["Goblet Squat"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Done set"].exists, "the live strength glance should be showing")
        // The adaptive rest screen appears after the first auto-completed set...
        XCTAssertTrue(app.staticTexts["REST"].waitForExistence(timeout: 30) ||
                      app.staticTexts["READY"].waitForExistence(timeout: 5),
                      "the recovery rest screen should follow the first set")
        // ...and the whole session self-drives to the summary.
        XCTAssertTrue(app.staticTexts["Done"].waitForExistence(timeout: 150),
                      "the scripted strength session should play through to the summary")
    }
}
