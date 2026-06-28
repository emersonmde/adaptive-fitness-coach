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
