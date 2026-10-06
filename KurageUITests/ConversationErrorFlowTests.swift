import XCTest

final class ConversationErrorFlowTests: XCTestCase {
    @MainActor
    func testAgentErrorRemainsVisibleWithDetailsAndCopyAfterReopening() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-agent-error"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-error"])
        let title = app.staticTexts["Agent internal error"]
        let message = app.staticTexts["model 'sample-model' is not enabled in the provider"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(message.exists)
        let work = app.buttons["turn-work-toggle-error-work"]
        XCTAssertEqual(work.value as? String, "Collapsed")
        XCTAssertFalse(app.staticTexts["Preparing the test message."].exists)
        attach(app, "Agent error outside collapsed work")

        tap(app.buttons["error-details-error-agent-notice-1"])
        let report = app.scrollViews["conversation-error-details"].staticTexts.firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(report.label.contains("Reason: acp_internal_error"))
        XCTAssertTrue(report.label.contains("Internal error: API Error: 400"))
        XCTAssertTrue(report.label.contains("\"status\":400"))
        attach(app, "Complete provider error details")
        tap(app.buttons["close-error-details"])
        let copy = app.buttons["copy-error-error-agent-notice-1"]
        tap(copy)
        XCTAssertEqual(copy.label, "Copied")
        attach(app, "Copied error")

        tap(app.navigationBars.buttons.firstMatch)
        tap(app.descendants(matching: .any)["session-session-error"])
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(message.exists)
        XCTAssertEqual(work.value as? String, "Collapsed")
        attach(app, "Agent error after reopening")
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        XCTAssertTrue(element.wait(for: \.isHittable, toEqual: true, timeout: 5))
        element.tap()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
