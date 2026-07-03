import XCTest

/// Drives the P3 coach flow end-to-end against the deterministic scripted engine
/// (`-simulateCoach`, the chat analogue of `-simulateWorkout`) and a throwaway store
/// (`-uiTesting`): intake conversation → proposal card → Review & apply → routines land on the
/// week screen. Run serially (`-parallel-testing-enabled NO`), like RoutineFlowUITests.
final class CoachFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-simulateCoach"]
        app.launch()
        return app
    }

    /// Walk the scripted intake from the empty state to an applied two-routine plan.
    func testCoachBuildsPlanFromEmptyState() throws {
        let app = launchApp()

        let coachDoor = app.buttons["coachEmptyState"]
        XCTAssertTrue(coachDoor.waitForExistence(timeout: 5))
        coachDoor.tap()

        // The sheet opens on the coach's greeting with one-tap answers.
        XCTAssertTrue(app.staticTexts["Let's build your week. First — what equipment do you have access to?"]
            .waitForExistence(timeout: 5))
        app.buttons["Dumbbells and a bench"].tap()

        // Scripted turns: answer the intake through the text field.
        let input = app.textFields["coachInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))

        for answer in ["Been off for a year, knees are fine", "Get stronger"] {
            input.tap()
            input.typeText(answer)
            let send = app.buttons["coachSend"]
            XCTAssertTrue(send.isEnabled)
            send.tap()
        }

        // The scripted third turn proposes a plan; review and apply it.
        let review = app.buttons["coachProposalReview"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()

        XCTAssertTrue(app.staticTexts["NEW · COACHED STRENGTH A"].waitForExistence(timeout: 5))
        app.buttons["Apply"].tap()

        // Applied confirmation shows in the chat; done → routines are on the week screen.
        XCTAssertTrue(app.staticTexts["Applied — updated 0, added 2."].waitForExistence(timeout: 5))
        app.buttons["coachDone"].tap()

        XCTAssertTrue(app.staticTexts["Coached Strength A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Coached Run"].exists)
    }

    /// The detail screen's "Ask the coach" opens the revise conversation for that routine.
    func testAskCoachFromRoutineDetail() throws {
        let app = launchApp()

        // Build a minimal routine first (same steps as RoutineFlowUITests).
        let newRoutineButton = app.buttons["newRoutineEmptyState"]
        XCTAssertTrue(newRoutineButton.waitForExistence(timeout: 5))
        newRoutineButton.tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Tempo Run")
        app.buttons["Wednesday"].firstMatch.tap()
        app.buttons["Next"].firstMatch.tap()
        app.buttons["Add card"].firstMatch.tap()
        app.buttons["Adaptive Run"].firstMatch.tap()
        app.buttons["Save"].firstMatch.tap()

        let row = app.staticTexts["Tempo Run"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let askCoach = app.buttons["askCoach"]
        XCTAssertTrue(askCoach.waitForExistence(timeout: 5))
        askCoach.tap()

        // The revise greeting names the routine under discussion.
        XCTAssertTrue(app.staticTexts["What's changed since you built Tempo Run? New equipment, more experience, less time?"]
            .waitForExistence(timeout: 5))
    }

    /// Without -simulateCoach the M2 placeholder engine reports unavailable — the sheet must
    /// show the honest reason state, never a dead end.
    func testCoachUnavailableStateShowsReason() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]   // no -simulateCoach
        app.launch()

        let coachDoor = app.buttons["coachEmptyState"]
        XCTAssertTrue(coachDoor.waitForExistence(timeout: 5))
        coachDoor.tap()

        XCTAssertTrue(app.staticTexts["Coach unavailable"].waitForExistence(timeout: 5))
        app.buttons["coachDone"].tap()
        XCTAssertTrue(app.staticTexts["No routines yet"].waitForExistence(timeout: 5))
    }
}
