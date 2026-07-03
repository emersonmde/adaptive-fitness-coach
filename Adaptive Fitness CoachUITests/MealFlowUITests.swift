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
