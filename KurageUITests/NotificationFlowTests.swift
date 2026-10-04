import XCTest

final class NotificationFlowTests: XCTestCase {
    @MainActor
    func testNotificationToggleCanEnableAndDisable() {
        let app = launch()
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-notifications"])
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        let toggle = app.switches["notifications-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertEqual(toggle.value as? String, "0")
        // SwiftUI exposes the whole Form row as a Switch; tap its trailing control.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitForValue("1", of: toggle)
        attach(app, "Notification settings enabled")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitForValue("0", of: toggle)
    }

    @MainActor
    func testColdNotificationWaitsForSignInThenOpensConversation() {
        let app = launch(arguments: ["--fixture-notification-click"])
        XCTAssertTrue(app.staticTexts["conversation-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["follow-up-field"].waitForExistence(timeout: 10))
        attach(app, "Cold notification opens conversation after sign in")
    }

    @MainActor
    func testNotificationOpensDirectTab() {
        let app = launch(arguments: ["--fixture-notification-click", "--fixture-running-tab"])
        XCTAssertTrue(app.staticTexts["conversation-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["conversation-title"].label, "Working tab")
        XCTAssertTrue(app.buttons["session-tab-fixture-running-tab"].waitForExistence(timeout: 10))
        attach(app, "Notification selects its child tab")
    }

    @MainActor
    func testOtherAccountsColdNotificationIsDiscarded() {
        let app = launch(arguments: ["--fixture-notification-click", "--fixture-notification-wrong-account"])
        XCTAssertTrue(app.descendants(matching: .any)["session-session-long"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["conversation-title"].exists)
    }

    @MainActor
    func testUnavailableNotificationsAreHiddenFromSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["account-menu"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings-notifications"].exists)
        XCTAssertTrue(app.buttons["settings-theme"].exists)
        XCTAssertTrue(app.buttons["settings-about"].exists)
        attach(app, "Settings with notifications hidden")
    }

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-notifications"] + arguments
        app.launch()
        tap(app.buttons["sign-in-button"])
        return app
    }

    @MainActor private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        element.tap()
    }

    @MainActor private func waitForValue(_ value: String, of element: XCUIElement) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
