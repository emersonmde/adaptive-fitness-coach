import XCTest

/// Drives the phone's core flow through the real UI: create routines from cards and confirm they
/// land on the week screen. Runs against a throwaway store (`-uiTesting`) so each run starts empty
/// and no system prompts block interaction.
final class RoutineFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
        return app
    }

    /// Fill name + a day on the "New Routine" screen, then continue to the builder.
    private func startNewRoutine(_ app: XCUIApplication, name: String, day: String) {
        let newRoutineButton = app.buttons["newRoutineEmptyState"]
        XCTAssertTrue(newRoutineButton.waitForExistence(timeout: 5))
        newRoutineButton.tap()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        app.buttons[day].firstMatch.tap()
        app.buttons["Next"].firstMatch.tap()
    }

    private func addCard(_ app: XCUIApplication, _ kind: String) {
        app.buttons["Add card"].firstMatch.tap()
        app.buttons[kind].firstMatch.tap()
    }

    func testCreateRunRoutineAppearsInWeek() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["No routines yet"].waitForExistence(timeout: 5))

        startNewRoutine(app, name: "Morning Run", day: "Monday")
        addCard(app, "Adaptive Run")
        app.buttons["Save"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Morning Run"].waitForExistence(timeout: 5))
    }

    func testCreateStrengthRoutineFromCardsAppearsInWeek() throws {
        let app = launchApp()

        startNewRoutine(app, name: "Push Day", day: "Monday")

        // Add an exercise card via the library, plus a rest card.
        addCard(app, "Exercise")
        let benchRow = app.buttons["exercise_db_bench_press"]
        XCTAssertTrue(benchRow.waitForExistence(timeout: 5))
        benchRow.tap()
        app.buttons["Add (1)"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Dumbbell Bench Press"].waitForExistence(timeout: 5))

        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Push Day"].waitForExistence(timeout: 5))
    }

    // MARK: - P6 progression journal + structural confirms

    /// `-seedProposal` routes a real v4 batch through ProgressionIntake at launch: a micro
    /// curl bump (journaled) plus a structural squat load-step proposal (pending). Confirming
    /// the card applies the step and the journal shows both rows.
    func testProposalCardConfirmAppliesAndJournals() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-seedProposal"]
        app.launch()

        let card = app.otherElements["proposal.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let changeLine = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Goblet Squat'")
        ).firstMatch
        XCTAssertTrue(changeLine.exists)

        app.buttons["proposal.confirm"].tap()
        XCTAssertFalse(card.waitForExistence(timeout: 2))

        // The journal shows the confirmed structural step and the automatic micro bump.
        app.buttons["journalToolbar"].tap()
        XCTAssertTrue(app.staticTexts["Goblet Squat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Dumbbell Curl"].exists)
        XCTAssertTrue(app.staticTexts["CONFIRMED"].exists)
    }

    /// Hold declines the structural step: the seed stays, the journal records "HELD".
    func testProposalCardHoldDeclines() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-seedProposal"]
        app.launch()

        let card = app.otherElements["proposal.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.buttons["proposal.hold"].tap()
        XCTAssertFalse(card.waitForExistence(timeout: 2))

        app.buttons["journalToolbar"].tap()
        XCTAssertTrue(app.staticTexts["HELD"].waitForExistence(timeout: 5))
    }

    func testCreatedRoutineOpensDetail() throws {
        let app = launchApp()

        startNewRoutine(app, name: "Tempo Run", day: "Wednesday")
        addCard(app, "Adaptive Run")
        app.buttons["Save"].firstMatch.tap()

        let row = app.staticTexts["Tempo Run"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // The schedule screen shows the Add to Calendar toggle.
        XCTAssertTrue(app.switches["Add to Calendar"].waitForExistence(timeout: 5))
    }
}
