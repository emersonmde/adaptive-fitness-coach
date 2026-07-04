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

    /// Opens the capture cover. First use routes through the Food screen (build 8.1 — the
    /// discovery path leads to the day screen; camera-direct is the widget's job).
    ///
    /// The scan tap gets ONE retry: presenting a fullScreenCover while the target sheet's
    /// dismissal transaction is still settling gets silently dropped by SwiftUI under
    /// load (deterministic when another suite ran first) — a second tap is exactly what a
    /// person does, and the helper asserts the cover actually arrived either way.
    private func openCapture(_ app: XCUIApplication) {
        let firstUse = app.buttons["meal.dailyLine.firstUse"]
        let camera = app.buttons["meal.dailyLine.capture"]
        if firstUse.waitForExistence(timeout: 5) {
            firstUse.tap()
            XCTAssertTrue(app.staticTexts["meal.day.title"].waitForExistence(timeout: 5))
            dismissTargetSheetIfPresent(app)
            app.buttons["meal.day.scan"].tap()
            if !app.buttons["meal.capture.cancel"].waitForExistence(timeout: 3) {
                app.buttons["meal.day.scan"].tap()
            }
        } else {
            XCTAssertTrue(camera.waitForExistence(timeout: 5))
            camera.tap()
        }
        XCTAssertTrue(app.buttons["meal.capture.cancel"].waitForExistence(timeout: 5),
                      "capture cover didn't present")
    }

    /// Taps a simulated-capture button, waiting for it first (immediate taps raced the
    /// cover's presentation animation).
    private func tapSimulatedCapture(_ app: XCUIApplication, _ kind: String) {
        let button = app.buttons["meal.capture.simulated.\(kind)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "simulated \(kind) button missing")
        button.tap()
    }

    /// Taps Log once it's ENABLED — the button stays disabled while any checked item is
    /// still looking up (never commit an unseen number), so an instant tap is a no-op.
    private func tapLogWhenReady(_ app: XCUIApplication, timeout: TimeInterval = 10) {
        let log = app.buttons["meal.confirm.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(timeout)
        while !log.isEnabled, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(log.isEnabled, "Log never became enabled — lookups still pending?")
        log.tap()
    }

    /// The barcode fast path: scan → single pre-checked item → Log → total lands.
    func testBarcodeFastPath() throws {
        let app = launchApp()
        openCapture(app)

        tapSimulatedCapture(app, "barcode")

        // Identify (scripted 400ms) → confirmation shows the resolved product, pre-checked.
        XCTAssertTrue(app.staticTexts["Coca-Cola Classic 12 fl oz"].waitForExistence(timeout: 5))
        tapLogWhenReady(app)

        // The Food screen's day total settles to the logged value once the lookup finishes.
        XCTAssertTrue(app.staticTexts["140 kcal"].waitForExistence(timeout: 10))
    }

    /// The receipt multi-item flow: 4 items, pantry item pre-unchecked, questionnaire chip
    /// answered by tap, Log → total reflects checked items only.
    func testReceiptFlow() throws {
        let app = launchApp()
        openCapture(app)

        tapSimulatedCapture(app, "receipt")

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

        // Build 8: the scripted receipt prints yesterday's date, so the when-row prefills
        // Yesterday (visible label) — flip to Today so the daily line assertion below holds.
        XCTAssertTrue(app.staticTexts["meal.when.prefill"].exists)
        app.buttons["meal.when.today"].tap()

        // Pantry item is pre-unchecked → Log says 3 items.
        XCTAssertTrue(app.buttons["meal.confirm.log"].label.contains("3"),
                      "expected 3 checked items, got: \(app.buttons["meal.confirm.log"].label)")
        tapLogWhenReady(app)

        // Total = 460 (salad) + 300 (chicken) + 475 (estimate midpoint) = 1,235.
        XCTAssertTrue(app.staticTexts["1,235 kcal"].waitForExistence(timeout: 12))
    }

    /// The label path: deterministic panel parse → verified item with its printed facts →
    /// Log → total = the label's calories (no lookup ran at all).
    func testNutritionLabelFlow() throws {
        let app = launchApp()
        openCapture(app)

        tapSimulatedCapture(app, "label")

        XCTAssertTrue(app.staticTexts["GREEK YOGURT"].waitForExistence(timeout: 5))
        tapLogWhenReady(app)

        XCTAssertTrue(app.staticTexts["190 kcal"].waitForExistence(timeout: 10))
    }

    /// The plate fallback (stage 5): placeholder item renamed inline, portion chips answered,
    /// Log → an honest RANGE lands (never a point value — C3).
    func testPlateEstimateFlow() throws {
        let app = launchApp()
        openCapture(app)

        tapSimulatedCapture(app, "plate")

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

        tapLogWhenReady(app)

        // Scripted estimate = 350–600 → the day total shows the midpoint (475).
        XCTAssertTrue(app.staticTexts["475 kcal"].waitForExistence(timeout: 10))
    }

    /// Build 10: the confirmation screen shows each item's number + source before Log, and
    /// tapping the number overrides it — the override records as the user's number.
    func testConfirmationShowsNumbersAndOverride() throws {
        let app = launchApp()
        openCapture(app)

        tapSimulatedCapture(app, "receipt")
        XCTAssertTrue(app.staticTexts["meal.confirm.header"].waitForExistence(timeout: 5))

        // Pre-commit lookups land row by row (scripted 500ms each): the salad shows its
        // database number, the curry an honest range — before anything is logged.
        let saladKcal = app.buttons["meal.confirm.kcal.Chicken Caesar Salad"]
        XCTAssertTrue(saladKcal.waitForExistence(timeout: 8))
        XCTAssertTrue(saladKcal.label.contains("460 kcal"))
        XCTAssertTrue(saladKcal.label.contains("Open Food Facts"))
        let curryKcal = app.buttons["meal.confirm.kcal.Deli Lentil Curry"]
        XCTAssertTrue(curryKcal.waitForExistence(timeout: 8))
        XCTAssertTrue(curryKcal.label.contains("350–600 kcal"))

        // Override the salad to 520 → "your number" immediately, before Log.
        saladKcal.tap()
        let field = app.textFields["meal.confirm.kcalField"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        clear(field)
        field.typeText("520")
        app.buttons["meal.confirm.kcalDone"].tap()
        XCTAssertTrue(saladKcal.waitForExistence(timeout: 3))
        XCTAssertTrue(saladKcal.label.contains("520 kcal"))
        XCTAssertTrue(saladKcal.label.contains("your number"))

        // Log to today; the day total reflects the override: 520 + 300 + 475 = 1,295.
        app.buttons["meal.when.today"].tap()
        tapLogWhenReady(app)
        XCTAssertTrue(app.staticTexts["1,295 kcal"].waitForExistence(timeout: 12))
    }

    /// Cancel is always an exit (principle 13): capture → Cancel → week intact, nothing logged.
    func testCancelExits() throws {
        let app = launchApp()
        openCapture(app)

        let cancel = app.buttons["meal.capture.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()

        // Back on the Food screen, nothing logged.
        XCTAssertTrue(app.staticTexts["meal.day.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing logged yet today."].waitForExistence(timeout: 5))
    }

    // MARK: - Build 8

    /// Typed entry with a stated calorie count: the number is the user's, verbatim.
    func testTypedEntryStatedCalories() throws {
        let app = launchApp()
        openCapture(app)

        let typePill = app.buttons["meal.capture.typeInstead"]
        XCTAssertTrue(typePill.waitForExistence(timeout: 5))
        typePill.tap()

        let field = app.textFields["meal.typed.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("salmon caesar salad, 400 calories")
        app.buttons["meal.typed.submit"].tap()

        // Confirmation shows the stripped, capitalized name; log it.
        XCTAssertTrue(app.staticTexts["Salmon caesar salad"].waitForExistence(timeout: 5))
        tapLogWhenReady(app)

        XCTAssertTrue(app.staticTexts["400 kcal"].waitForExistence(timeout: 10))
    }

    /// Backdate via the when-row: a barcode logged to Yesterday leaves today empty and shows
    /// up on the Food screen's previous day.
    func testBackdateYesterday() throws {
        let app = launchApp()
        openCapture(app)

        tapSimulatedCapture(app, "barcode")
        XCTAssertTrue(app.staticTexts["Coca-Cola Classic 12 fl oz"].waitForExistence(timeout: 5))
        app.buttons["meal.when.yesterday"].tap()
        tapLogWhenReady(app)

        // Today stays empty on the Food screen (the entry went to yesterday)…
        XCTAssertTrue(app.staticTexts["meal.day.title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Nothing logged yet today."].waitForExistence(timeout: 8))

        // …and paging back finds it. (On a past day the title becomes the jump-home button.)
        app.buttons["meal.day.prev"].tap()
        let backTitle = app.buttons["meal.day.title"]
        XCTAssertTrue(backTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Yesterday"].exists)
        XCTAssertTrue(app.staticTexts["Coca-Cola Classic 12 fl oz"].waitForExistence(timeout: 5))

        // Tapping the title jumps straight back to today — no paging one day at a time.
        backTitle.tap()
        XCTAssertTrue(app.staticTexts["meal.day.title"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Today"].exists)
    }

    /// Target setup from the fixed sim profile → gauge appears with the suggested number.
    func testTargetSetupAndGauge() throws {
        let app = launchApp()
        // Log once so the daily line (the Food screen's door) exists.
        openCapture(app)
        tapSimulatedCapture(app, "barcode")
        XCTAssertTrue(app.staticTexts["Coca-Cola Classic 12 fl oz"].waitForExistence(timeout: 5))
        tapLogWhenReady(app)
        XCTAssertTrue(app.staticTexts["140 kcal"].waitForExistence(timeout: 10))

        openFoodDay(app)
        app.buttons["meal.day.setTarget"].tap()

        // The sheet offers the suggestion (fixed sim profile 80kg/180cm/35/M). Confirm.
        let confirm = app.buttons["meal.target.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["meal.target.suggested"].exists)
        confirm.tap()

        // The gauge takes the slot: consumed hero + "of N" target line; the hub line gains
        // the quiet "x / y" arithmetic.
        XCTAssertTrue(app.staticTexts["meal.day.gauge.consumed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["meal.day.gauge.target"].exists)
        app.navigationBars.buttons.firstMatch.tap()   // back to the hub
        XCTAssertTrue(waitForLabel(app.staticTexts["meal.dailyLine.total"], contains: "/", timeout: 5))
    }

    /// Edit an entry's calories → the number becomes "your number" and the row updates.
    func testEditEntry() throws {
        let app = launchApp()
        openCapture(app)
        tapSimulatedCapture(app, "barcode")
        XCTAssertTrue(app.staticTexts["Coca-Cola Classic 12 fl oz"].waitForExistence(timeout: 5))
        tapLogWhenReady(app)
        XCTAssertTrue(app.staticTexts["140 kcal"].waitForExistence(timeout: 10))

        openFoodDay(app)
        dismissTargetSheetIfPresent(app)
        let row = app.staticTexts["Coca-Cola Classic 12 fl oz"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let kcalField = app.textFields["meal.edit.kcal"]
        XCTAssertTrue(kcalField.waitForExistence(timeout: 5))
        kcalField.tap()
        clear(kcalField)
        kcalField.typeText("500")
        XCTAssertTrue(app.staticTexts["meal.edit.userStatedNote"].exists)
        app.buttons["meal.edit.save"].tap()

        XCTAssertTrue(app.staticTexts["your number"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["500 kcal"].exists)
    }

    /// Build 11: fix the restaurant on the edit sheet and "Look up again" — the ladder
    /// re-runs against the edited name/seller and the row records the fresh result.
    func testEditRescanReLooksUp() throws {
        let app = launchApp()
        openCapture(app)
        tapSimulatedCapture(app, "barcode")
        XCTAssertTrue(app.staticTexts["Coca-Cola Classic 12 fl oz"].waitForExistence(timeout: 5))
        tapLogWhenReady(app)
        XCTAssertTrue(app.staticTexts["140 kcal"].waitForExistence(timeout: 10))

        openFoodDay(app)
        dismissTargetSheetIfPresent(app)
        let row = app.staticTexts["Coca-Cola Classic 12 fl oz"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // Name the restaurant, then re-run the lookup. The scripted ladder resolves the
        // edited item through the estimate rung (350–600) — honest range, "estimate" source.
        let seller = app.textFields["meal.edit.seller"]
        XCTAssertTrue(seller.waitForExistence(timeout: 5))
        seller.tap()
        seller.typeText("Salad Works")
        app.buttons["meal.edit.rescan"].tap()
        let source = app.staticTexts["meal.edit.source"]
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline, source.label != "estimate" {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertEqual(source.label, "estimate")
        app.buttons["meal.edit.save"].tap()

        // The day row shows the seller, the honest source, and the fresh range.
        XCTAssertTrue(app.staticTexts["Salad Works · estimate"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["350–600 kcal"].exists)
    }

    /// "Log again" duplicates a past entry as a fresh one now — the total doubles.
    func testLogAgain() throws {
        let app = launchApp()
        openCapture(app)
        tapSimulatedCapture(app, "barcode")
        XCTAssertTrue(app.staticTexts["Coca-Cola Classic 12 fl oz"].waitForExistence(timeout: 5))
        tapLogWhenReady(app)
        XCTAssertTrue(app.staticTexts["140 kcal"].waitForExistence(timeout: 10))

        openFoodDay(app)
        dismissTargetSheetIfPresent(app)
        let row = app.staticTexts["Coca-Cola Classic 12 fl oz"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.0)
        let again = app.buttons["Log again"]
        XCTAssertTrue(again.waitForExistence(timeout: 3))
        again.tap()

        // Two 140-kcal entries → the day total (gauge-less slot) reads 280 kcal.
        XCTAssertTrue(app.staticTexts["280 kcal"].waitForExistence(timeout: 6))
    }

    // MARK: - Helpers

    private func openFoodDay(_ app: XCUIApplication) {
        // Already there? (post-log flows land on the Food screen since 8.1's routing.)
        if app.staticTexts["meal.day.title"].waitForExistence(timeout: 2) { return }
        let total = app.staticTexts["meal.dailyLine.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5), "daily line not present — log something first")
        total.tap()
        XCTAssertTrue(app.staticTexts["meal.day.title"].waitForExistence(timeout: 5), "Food screen didn't open")
    }

    private func clear(_ field: XCUIElement) {
        guard let value = field.value as? String, !value.isEmpty else { return }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 1))
    }

    private func dismissTargetSheetIfPresent(_ app: XCUIApplication) {
        // The first-run target offer (a sheet) appears on the Food screen's first open.
        let field = app.textFields["meal.target.field"]
        if field.waitForExistence(timeout: 3) {
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.waitForExistence(timeout: 2) {
                cancel.tap()
                // The sheet must be fully GONE before the caller taps beneath it — a tap
                // mid-dismissal can have its own presentation silently dropped.
                XCTAssertTrue(field.waitForNonExistence(timeout: 5))
            }
        }
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
