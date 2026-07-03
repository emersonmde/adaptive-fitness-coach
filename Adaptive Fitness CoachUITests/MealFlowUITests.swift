import XCTest

/// Drives the P4 meal-logging flow end-to-end against the deterministic scripted pipeline
/// (`-simulateMealScan` — the meal analogue of `-simulateCoach`) with the in-memory recorder
/// and a throwaway store (`-uiTesting`): capture → confirmation → Log → daily line settles.
/// Run serially (`-parallel-testing-enabled NO`), like the other phone UI suites.
final class MealFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-simulateMealScan"]
        app.launch()
        return app
    }

    /// Opens the capture cover from the empty week's quiet "Log a meal" entry.
    private func openCapture(_ app: XCUIApplication) {
        let firstUse = app.buttons["meal.dailyLine.firstUse"]
        let camera = app.buttons["meal.dailyLine.capture"]
        if firstUse.waitForExistence(timeout: 5) {
            firstUse.tap()
        } else {
            XCTAssertTrue(camera.waitForExistence(timeout: 5))
            camera.tap()
        }
    }

    /// The barcode fast path: scan → single pre-checked item → Log → total lands.
    func testBarcodeFastPath() throws {
        let app = launchApp()
        openCapture(app)

        let barcodeButton = app.buttons["meal.capture.simulated.barcode"]
        XCTAssertTrue(barcodeButton.waitForExistence(timeout: 5))
        barcodeButton.tap()

        // Identify (scripted 400ms) → confirmation shows the resolved product, pre-checked.
        XCTAssertTrue(app.staticTexts["Coca-Cola Classic 12 fl oz"].waitForExistence(timeout: 5))
        let log = app.buttons["meal.confirm.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 2))
        log.tap()

        // The daily line settles to the logged total (140 kcal) once the lookup finishes.
        let total = app.staticTexts["meal.dailyLine.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(total, contains: "140 kcal", timeout: 8))
    }

    /// The receipt multi-item flow: 4 items, pantry item pre-unchecked, questionnaire chip
    /// answered by tap, Log → total reflects checked items only.
    func testReceiptFlow() throws {
        let app = launchApp()
        openCapture(app)

        let receiptButton = app.buttons["meal.capture.simulated.receipt"]
        XCTAssertTrue(receiptButton.waitForExistence(timeout: 5))
        receiptButton.tap()

        // Confirmation: seller header + all four items.
        XCTAssertTrue(app.staticTexts["meal.confirm.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Trader Joe's · receipt"].exists)
        for item in ["Chicken Caesar Salad", "Rotisserie Chicken", "Penne Pasta (box)", "Deli Lentil Curry"] {
            XCTAssertTrue(app.staticTexts[item].exists, "missing item row: \(item)")
        }

        // The questionnaire renders as tappable chips with the default pre-selected; tap Half.
        let half = app.buttons["meal.question.portion.half"]
        XCTAssertTrue(half.exists)
        half.tap()

        // Pantry item is pre-unchecked → Log says 3 items.
        let log = app.buttons["meal.confirm.log"]
        XCTAssertTrue(log.label.contains("3"), "expected 3 checked items, got: \(log.label)")
        log.tap()

        // Total = 460 (salad) + 300 (chicken) + 475 (estimate midpoint) = 1,235.
        let total = app.staticTexts["meal.dailyLine.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(total, contains: "1,235 kcal", timeout: 10))
    }

    /// The label path: deterministic panel parse → verified item with its printed facts →
    /// Log → total = the label's calories (no lookup ran at all).
    func testNutritionLabelFlow() throws {
        let app = launchApp()
        openCapture(app)

        let labelButton = app.buttons["meal.capture.simulated.label"]
        XCTAssertTrue(labelButton.waitForExistence(timeout: 5))
        labelButton.tap()

        XCTAssertTrue(app.staticTexts["GREEK YOGURT"].waitForExistence(timeout: 5))
        app.buttons["meal.confirm.log"].tap()

        let total = app.staticTexts["meal.dailyLine.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(total, contains: "190 kcal", timeout: 8))
    }

    /// The plate fallback (stage 5): placeholder item renamed inline, portion chips answered,
    /// Log → an honest RANGE lands (never a point value — C3).
    func testPlateEstimateFlow() throws {
        let app = launchApp()
        openCapture(app)

        let plateButton = app.buttons["meal.capture.simulated.plate"]
        XCTAssertTrue(plateButton.waitForExistence(timeout: 5))
        plateButton.tap()

        // Rename the placeholder inline (the plate path's one typing allowance).
        let placeholder = app.staticTexts["Plate of food (tap to name it)"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5))
        placeholder.tap()
        let field = app.textFields["meal.confirm.nameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Lentil curry with rice")
        app.keyboards.buttons["done"].firstMatch.exists
            ? app.keyboards.buttons["done"].tap()
            : field.typeText("\n")

        // Portion chips (deterministic C4 question) — pick Large.
        let large = app.buttons["meal.question.plate-portion.large"]
        XCTAssertTrue(large.waitForExistence(timeout: 2))
        large.tap()

        app.buttons["meal.confirm.log"].tap()

        // Scripted estimate = 350–600 → the daily total shows the midpoint (475).
        let total = app.staticTexts["meal.dailyLine.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(total, contains: "475 kcal", timeout: 8))
    }

    /// Cancel is always an exit (principle 13): capture → Cancel → week intact, nothing logged.
    func testCancelExits() throws {
        let app = launchApp()
        openCapture(app)

        let cancel = app.buttons["meal.capture.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()

        // Back on the week screen, still in the never-logged state.
        XCTAssertTrue(app.buttons["meal.dailyLine.firstUse"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["meal.dailyLine.total"].exists)
    }

    private func waitForLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label.contains(text) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.label.contains(text)
    }
}
