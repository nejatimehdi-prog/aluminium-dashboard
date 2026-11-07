import XCTest

/// Scenarios 21 and 22 on the simulator, plus real screenshots of the running app.
final class ChortkehUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
        return app
    }

    /// Saves a screenshot as a test attachment and, if SCREENSHOT_DIR is set, as a PNG file.
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
    }

    // 21. Empty first launch: onboarding can be skipped; dashboard shows "balance not recorded", not zero.
    func testEmptyStateAndOnboardingSkip() {
        let app = launch()
        let skip = app.buttons["onboardingSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        snapshot(app, "01-onboarding")
        skip.tap()
        XCTAssertTrue(app.staticTexts["noBalanceLabel"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["quickAddButton"].exists)
        snapshot(app, "02-empty-dashboard")
    }

    // 22. Open app → quick add expense → back on the dashboard with the updated balance.
    func testQuickExpenseFlow() {
        let app = launch(["-skipOnboarding", "-seedAccountToman", "2000000"])
        let total = app.staticTexts["totalCash"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue(total.label.contains("۲٬۰۰۰٬۰۰۰"))
        snapshot(app, "03-dashboard")

        app.buttons["quickAddButton"].tap()
        let expense = app.buttons["quickEntry.expense"]
        XCTAssertTrue(expense.waitForExistence(timeout: 5))
        snapshot(app, "04-quick-entry")
        expense.tap()

        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap()
        amount.typeText("150000")
        snapshot(app, "05-expense-form")
        app.buttons["saveButton"].tap()

        let predicate = NSPredicate(format: "label CONTAINS %@", "۱٬۸۵۰٬۰۰۰")
        expectation(for: predicate, evaluatedWith: app.staticTexts["totalCash"])
        waitForExpectations(timeout: 10)
        snapshot(app, "06-dashboard-after-expense")
    }

    func testChequeEntryShowsInUpcomingAndForecast() {
        let app = launch(["-skipOnboarding", "-seedAccountToman", "200000000"])
        XCTAssertTrue(app.buttons["quickAddButton"].waitForExistence(timeout: 10))
        app.buttons["quickAddButton"].tap()
        let cheque = app.buttons["quickEntry.chequeIssued"]
        XCTAssertTrue(cheque.waitForExistence(timeout: 5))
        cheque.tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap()
        amount.typeText("300000000")
        let contact = app.textFields["contactField"]
        contact.tap()
        contact.typeText("Ahmadi")
        app.buttons["saveButton"].tap()
        XCTAssertTrue(app.buttons["quickAddButton"].waitForExistence(timeout: 10))
        app.swipeUp()
        snapshot(app, "07-dashboard-with-cheque")
        XCTAssertTrue(app.otherElements["forecastCard"].exists || app.staticTexts["shortfallWarning"].exists)
    }

    func testSettingsOpens() {
        let app = launch(["-skipOnboarding", "-seedAccountToman", "1000000"])
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["closeButton"].waitForExistence(timeout: 5))
        snapshot(app, "08-settings")
        app.buttons["closeButton"].tap()
        XCTAssertTrue(app.buttons["quickAddButton"].waitForExistence(timeout: 5))
    }
}
