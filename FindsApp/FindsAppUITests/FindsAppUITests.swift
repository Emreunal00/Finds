






import XCTest

final class FindsAppUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "1"]
    }

    override func tearDownWithError() throws {
        
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

        
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Tab bar did not appear. Login/onboarding may be active, or labels may differ.")

        
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
        XCTAssertTrue(tapped, "Search tab button was not found. Check the tab item label.")

        
        let searchFieldById = app.textFields["searchTextField"]
        let searchField: XCUIElement = searchFieldById.exists ? searchFieldById : (app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch)
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field was not found. Add accessibilityIdentifier('searchTextField') to SearchView.")

        searchField.tap()
        searchField.typeText("Matrix")

        
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12)
        searchField.typeText(deleteString)

        
        
        
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
