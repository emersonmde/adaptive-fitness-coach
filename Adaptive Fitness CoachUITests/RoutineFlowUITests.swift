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

    func testCreatedRoutineOpensDetail() throws {
        let app = launchApp()

        app.buttons["newRoutineEmptyState"].tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Tempo Run")
        app.buttons["Wednesday"].firstMatch.tap()
        app.buttons["Next"].firstMatch.tap()

        // Tap the routine row to open its detail/schedule screen.
        let row = app.staticTexts["Tempo Run"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // The schedule screen shows the Reminders toggle.
        XCTAssertTrue(app.switches["Reminders"].waitForExistence(timeout: 5))
    }
}
