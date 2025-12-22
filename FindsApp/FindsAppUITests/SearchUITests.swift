//
//  SearchUITests.swift
//  FindsApp
//
//  Created by Emre ünal on 11.12.2025.
//

import XCTest

final class SearchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSearchClearGoesToDefault() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "1"]
        app.launch()

        // Wait for tab bar
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Tab bar görünmedi. Login/onboarding olabilir.")

        // Try multiple labels for localization
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
        XCTAssertTrue(tapped, "Search tab butonu bulunamadı. Label'ı kontrol edin veya identifier kullanın.")

        // Prefer an identifier if available
        let searchFieldById = app.textFields["searchTextField"]
        let searchField: XCUIElement = searchFieldById.exists ? searchFieldById : (app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch)
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Arama alanı bulunamadı. SearchView'e accessibilityIdentifier('searchTextField') ekleyin.")

        searchField.tap()
        searchField.typeText("Matrix")

        // TODO: assert results appear, e.g., using an identifier like "searchResultsList"
        // let resultsList = app.collectionViews["searchResultsList"]
        // XCTAssertTrue(resultsList.waitForExistence(timeout: 5))

        // Clear text by sending deletes
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10)
        searchField.typeText(deleteString)

        // TODO: assert default state is visible, e.g., using an identifier like "searchEmptyState"
        // let emptyState = app.otherElements["searchEmptyState"]
        // XCTAssertTrue(emptyState.waitForExistence(timeout: 5))
    }
}
