import XCTest

/// Drives the phone's core flow through the real UI: create a routine and confirm it lands on
/// the week screen, then open it. Runs against a throwaway store (`-uiTesting`) so each run
/// starts empty and no system prompts block interaction.
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

    func testCreateRoutineAppearsInWeek() throws {
        let app = launchApp()

        // Empty state first.
        XCTAssertTrue(app.staticTexts["No routines yet"].waitForExistence(timeout: 5))

        // Open the create flow via the unambiguous empty-state button.
        let newRoutineButton = app.buttons["newRoutineEmptyState"]
        XCTAssertTrue(newRoutineButton.waitForExistence(timeout: 5))
        newRoutineButton.tap()

        // Name it.
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Morning Run")

        // Pick a day (Monday pill is labeled with its full name for accessibility).
        app.buttons["Monday"].firstMatch.tap()

        // Save.
        app.buttons["Next"].firstMatch.tap()

        // Back on the week screen, the routine is listed.
        XCTAssertTrue(app.staticTexts["Morning Run"].waitForExistence(timeout: 5))
    }

    func testCreateStrengthRoutineViaLibraryAppearsInWeek() throws {
        let app = launchApp()

        app.buttons["newRoutineEmptyState"].tap()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Push Day")
        app.buttons["Monday"].firstMatch.tap()

        // Switch the type to Strength → "Next" now pushes the exercise builder.
        app.buttons["Strength"].firstMatch.tap()
        app.buttons["Next"].firstMatch.tap()

        // Builder empty state → open the library and add an exercise.
        let addExercises = app.buttons["Add Exercises"].firstMatch
        XCTAssertTrue(addExercises.waitForExistence(timeout: 5))
        addExercises.tap()

        let benchRow = app.buttons["exercise_db_bench_press"]
        XCTAssertTrue(benchRow.waitForExistence(timeout: 5))
        benchRow.tap()
        app.buttons["Add (1)"].firstMatch.tap()

        // Back in the builder, the card is present → Save creates the routine.
        XCTAssertTrue(app.staticTexts["Dumbbell Bench Press"].waitForExistence(timeout: 5))
        app.buttons["Save"].firstMatch.tap()

        // The strength routine is now on the week screen.
        XCTAssertTrue(app.staticTexts["Push Day"].waitForExistence(timeout: 5))
    }

    func testCreatedRoutineOpensDetail() throws {
        let app = launchApp()

        app.buttons["newRoutineEmptyState"].tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Tempo Run")
        app.buttons["Wednesday"].firstMatch.tap()
        app.buttons["Next"].firstMatch.tap()

        // Open the routine's detail/schedule. The name now appears in both the Up-Next hero and
        // its routine row, so target the first match explicitly (both navigate to the same detail).
        let row = app.staticTexts["Tempo Run"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // The schedule screen shows the Add to Calendar toggle.
        XCTAssertTrue(app.switches["Add to Calendar"].waitForExistence(timeout: 5))
    }
}
