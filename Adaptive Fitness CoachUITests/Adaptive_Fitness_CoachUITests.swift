//
//  Adaptive_Fitness_CoachUITests.swift
//  Adaptive Fitness CoachUITests
//
//  Created by Matthew Emerson on 6/24/26.
//

import XCTest

final class Adaptive_Fitness_CoachUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPerformance() throws {
        // Launch in UI-test mode (clean store, no permission prompt) so the metric is stable.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments += ["-uiTesting"]
            app.launch()
        }
    }
}
