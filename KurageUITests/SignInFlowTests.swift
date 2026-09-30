import XCTest

final class SignInFlowTests: XCTestCase {
    @MainActor
    func testWelcomeReturnsAfterSignOutAndCanSignInAgain() {
        let app = launchFixture()
        let getStarted = app.buttons["sign-in-button"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 8))
        XCTAssertEqual(getStarted.label, "Get Started")
        XCTAssertTrue(getStarted.isHittable)
        XCTAssertTrue(app.staticTexts["welcome-title"].label.contains("Welcome to"))
        attachScreen(app, name: "welcome")
        getStarted.tap()

        let more = app.buttons["more-options"]
        XCTAssertTrue(more.waitForExistence(timeout: 8))
        more.tap()
        app.buttons["Sign out"].tap()
        XCTAssertTrue(getStarted.waitForExistence(timeout: 8))
        XCTAssertEqual(getStarted.label, "Get Started")
        XCTAssertFalse(app.descendants(matching: .any)["session-session-tests"].exists)
        attachScreen(app, name: "welcome-after-sign-out")

        getStarted.tap()
        XCTAssertTrue(more.waitForExistence(timeout: 8))
    }

    @MainActor
    func testClosingAuthorizationBrowserCancelsAndAllowsRetry() {
        let app = launchFixture(arguments: ["--fixture-browser", "--fixture-pending-authorization"])
        let getStarted = app.buttons["sign-in-button"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 8))
        getStarted.tap()

        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        attachScreen(app, name: "authorization-browser")
        close.tap()
        XCTAssertTrue(getStarted.wait(for: \.label, toEqual: "Get Started", timeout: 8))
        XCTAssertTrue(getStarted.isEnabled)
        XCTAssertFalse(app.staticTexts["sign-in-status"].exists)

        getStarted.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(getStarted.wait(for: \.label, toEqual: "Get Started", timeout: 8))
        XCTAssertFalse(app.buttons["more-options"].exists)
    }

    @MainActor
    func testAuthorizationCompletionDismissesBrowser() {
        let app = launchFixture(arguments: ["--fixture-browser"])
        let getStarted = app.buttons["sign-in-button"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 8))
        getStarted.tap()
        XCTAssertTrue(app.buttons["Close"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)

        XCTAssertTrue(app.buttons["more-options"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.buttons["Close"].firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["session-session-tests"].isHittable)
        attachScreen(app, name: "authorization-complete")
    }

    @MainActor
    private func launchFixture(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
