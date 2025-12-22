//
//  FindsAppUITestsLaunchTests.swift
//  FindsAppUITests
//
//  Created by Emre ünal on 11.12.2025.
//

import XCTest

final class FindsAppUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "1"]
        app.launch()

        // Wait for main UI (e.g., Tab Bar) to appear to avoid onboarding/login
        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 8)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
