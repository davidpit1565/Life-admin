import XCTest

/// Captures a fixed sequence of App Store screenshots against deterministic demo data (seeded by
/// `ItemStore.seedDemoDataForScreenshots`, gated by `UITestSupport.isCapturingScreenshots` so it
/// never runs — or seeds anything — outside this test target). Run it against whatever Simulator
/// matches the App Store Connect size you need (e.g. "iPhone 17 Pro Max" for the 6.9" set); see
/// `docs/SCREENSHOTS.md` for how to run it and pull the PNGs out of the resulting .xcresult
/// bundle. This has not been run in CI or on a real device — verify once in Xcode before relying
/// on it, same as every other App-target change in this repo.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestScreenshots", "1",
            "-hasSeenOnboarding", "true",
            "-aiConsentDecision", "declined",
            "-appLockEnabled", "false"
        ]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar never appeared — first-run screens may not have been fully skipped.")

        capture(app, name: "01-Home")

        let itemsTab = tabBar.buttons.element(boundBy: 1)
        itemsTab.tap()
        capture(app, name: "02-Items")

        // Best-effort: opening an item's detail screen is a nice bonus screenshot (shows the
        // category-tailored Document Details fields), but not worth failing the whole run over.
        let passportRow = app.staticTexts["Passport Renewal"].firstMatch
        if passportRow.waitForExistence(timeout: 5) {
            passportRow.tap()
            _ = app.navigationBars.firstMatch.waitForExistence(timeout: 5)
            capture(app, name: "03-ItemDetail-DocumentFields")
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            if backButton.exists {
                backButton.tap()
            }
        }

        let calendarTab = tabBar.buttons.element(boundBy: 2)
        calendarTab.tap()
        capture(app, name: "04-Calendar")

        let insightsTab = tabBar.buttons.element(boundBy: 3)
        insightsTab.tap()
        capture(app, name: "05-Insights")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
