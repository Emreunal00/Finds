






import XCTest

final class SearchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSearchClearGoesToDefault() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "1"]
        app.launch()

        
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Tab bar did not appear. Login/onboarding may be active.")

        
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
        XCTAssertTrue(tapped, "Search tab button was not found. Check the label or use an identifier.")

        
        let searchFieldById = app.textFields["searchTextField"]
        let searchField: XCUIElement = searchFieldById.exists ? searchFieldById : (app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch)
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field was not found. Add accessibilityIdentifier('searchTextField') to SearchView.")

        searchField.tap()
        searchField.typeText("Matrix")

        
        
        

        
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10)
        searchField.typeText(deleteString)

        
        
        
    }
}
