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

    // MARK: - P6 Export to Claude

    /// The export sheet: use-case presets drive the scope, the includes-line stays honest,
    /// and the FIRST health-inclusive copy shows the one-time disclosure before copying.
    func testExportPackDisclosureThenCopy() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-seedProposal"]   // seeded routine to export
        app.launch()

        app.buttons["claudeMenu"].tap()
        // Menu items surface to XCUI by their label, not the SwiftUI identifier.
        let exportItem = app.buttons["Export to Claude…"]
        XCTAssertTrue(exportItem.waitForExistence(timeout: 5))
        exportItem.tap()

        let includesLine = app.staticTexts["export.includesLine"]
        XCTAssertTrue(includesLine.waitForExistence(timeout: 5))
        // Program design preset: routines + snapshot + 30-day progression, no meals.
        XCTAssertTrue(includesLine.label.contains("fitness snapshot"))
        XCTAssertTrue(includesLine.label.contains("no meals"))

        // Snapshot is on → the first copy passes the one-time disclosure.
        app.buttons["export.copy"].tap()
        let disclosure = app.buttons["export.disclosure.continue"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.tap()

        XCTAssertTrue(app.alerts["Copied for Claude"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()

        // Second copy: no disclosure again (per-launch flag under -uiTesting).
        app.buttons["export.copy"].tap()
        XCTAssertTrue(app.alerts["Copied for Claude"].waitForExistence(timeout: 5))
    }

    /// A health-free scope (check-in with everything health off) copies without disclosure.
    func testExportWithoutHealthDataSkipsDisclosure() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-seedProposal"]
        app.launch()

        app.buttons["claudeMenu"].tap()
        let exportItem = app.buttons["Export to Claude…"]
        XCTAssertTrue(exportItem.waitForExistence(timeout: 5))
        exportItem.tap()

        let snapshotToggle = app.switches["export.scope.snapshot"]
        XCTAssertTrue(snapshotToggle.waitForExistence(timeout: 5))
        if (snapshotToggle.value as? String) == "1" { snapshotToggle.tap() }

        app.buttons["export.copy"].tap()
        XCTAssertTrue(app.alerts["Copied for Claude"].waitForExistence(timeout: 5))
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
        // No run history (plain -uiTesting) → the insights section is silently absent.
        XCTAssertFalse(app.otherElements["routineLastWorkout"].exists)
    }

    // MARK: - P6.1 per-routine insights

    /// `-uiTestInsights` swaps in a canned five-session history: the routine detail grows a
    /// LAST WORKOUT section, and Trends pushes the chart screen with baseline-suffixed stats.
    func testRunRoutineShowsLastWorkoutAndTrends() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTestInsights"]
        app.launch()

        startNewRoutine(app, name: "Morning Run", day: "Monday")
        addCard(app, "Adaptive Run")
        app.buttons["Save"].firstMatch.tap()

        let row = app.staticTexts["Morning Run"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let section = app.otherElements["routineLastWorkout"]
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Time running"].exists)

        app.buttons["routineTrends"].tap()
        // A bare identifier on the screen's ZStack doesn't register as otherElements (the
        // build-15 container lesson) — anchor on the section header instead, and query the
        // chart type-agnostically.
        XCTAssertTrue(app.staticTexts["TIME RUNNING · LAST 28 DAYS"].waitForExistence(timeout: 5))
        // Five gate-passing sessions → the chart renders and a baseline suffix appears.
        XCTAssertTrue(app.descendants(matching: .any)["insights.chart"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'vs 28-day average'")
        ).firstMatch.exists)

        // Keep a screenshot of the chart screen in the result bundle — the visual record
        // for design review (charts aren't otherwise pinned by pixels).
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "RoutineInsights"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
