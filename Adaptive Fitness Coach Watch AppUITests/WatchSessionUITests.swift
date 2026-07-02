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

    /// `-simulateStrength` reaches the live strength screen end-to-end (launch → active). Tapping
    /// through the cards is covered by `StrengthFlowTests` (see the limitation note above).
    func testStrengthSessionReachesLiveScreen() throws {
        let app = launch("-simulateStrength")
        XCTAssertTrue(app.staticTexts["Goblet Squat"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Done set"].exists, "the live strength glance should be showing")
    }
}
