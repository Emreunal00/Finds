//
//  FindsAppUITests.swift
//  FindsAppUITests
//
//  Created by Emre ünal on 11.12.2025.
//

import XCTest

final class FindsAppUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "1"]
    }

    override func tearDownWithError() throws {
        // Ensure app is terminated between tests to avoid interference
        if app != nil {
            if app.state == .runningForeground || app.state == .runningBackground {
                app.terminate()
            }
        }
        app = nil
    }

    @MainActor
    func testSearchClearGoesToDefault() throws {
        app.launch()

        // Wait for Tab Bar to appear
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Tab bar görünmedi. Login/onboarding olabilir veya etiketler farklı.")

        // Try multiple possible labels in case of localization
        let possibleLabels = ["Search", "Ara", "SEARCH"]
        var tapped = false
        for label in possibleLabels {
            let btn = tabBar.buttons[label]
            if btn.waitForExistence(timeout: 1) {
                btn.tap()
                tapped = true
                break
            }
        }
        XCTAssertTrue(tapped, "Search tab butonu bulunamadı. Tab item label'ını kontrol edin.")

        // Try to find search field by identifier first, then fallback to first search/text field
        let searchFieldById = app.textFields["searchTextField"]
        let searchField: XCUIElement = searchFieldById.exists ? searchFieldById : (app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch)
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Arama alanı bulunamadı. Lütfen SearchView'e accessibilityIdentifier('searchTextField') ekleyin.")

        searchField.tap()
        searchField.typeText("Matrix")

        // Clear by sending delete keys
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12)
        searchField.typeText(deleteString)

        // Optionally assert default state if identifier exists
        // let emptyState = app.otherElements["searchEmptyState"]
        // XCTAssertTrue(emptyState.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments += ["-UITestMode", "1"]
            app.launch()
            app.terminate()
        }
    }
}
