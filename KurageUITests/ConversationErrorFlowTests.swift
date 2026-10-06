import XCTest

final class ConversationErrorFlowTests: XCTestCase {
    @MainActor
    func testAgentErrorRemainsVisibleWithDetailsAndCopyAfterReopening() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-agent-error"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-error"])
        let error = app.buttons["error-details-error-agent-notice-1"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Agent internal error")
        XCTAssertTrue((error.value as? String)?.contains("model 'sample-model' is not enabled in the provider") == true)
        XCTAssertTrue((error.value as? String)?.contains("\"status\":400") == true)
        let work = app.buttons["turn-work-toggle-error-work"]
        XCTAssertEqual(work.value as? String, "Collapsed")
        XCTAssertFalse(app.staticTexts["Preparing the test message."].exists)
        attach(app, "Agent error outside collapsed work")

        tap(error)
        let report = app.scrollViews["conversation-error-details"].staticTexts.firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(report.label.contains("Reason: acp_internal_error"))
        XCTAssertTrue(report.label.contains("Internal error: API Error: 400"))
        XCTAssertTrue(report.label.contains("\"status\":400"))
        let details = app.scrollViews["conversation-error-details"]
        XCTAssertGreaterThanOrEqual(app.frame.maxY - details.frame.maxY, 24)
        attach(app, "Complete provider error details")
        let copy = app.buttons["copy-error-error-agent-notice-1"]
        tap(copy)
        XCTAssertEqual(copy.label, "Copied")
        attach(app, "Copied error")

        let grabber = app.buttons["Sheet Grabber"]
        let halfScreenY = grabber.frame.minY
        let handle = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(CGVector(dx: 0, dy: -180)))
        waitForValue("Expanded", on: grabber)
        XCTAssertLessThan(grabber.frame.minY, halfScreenY - 100)
        XCTAssertGreaterThanOrEqual(app.frame.maxY - details.frame.maxY, 24)
        attach(app, "Expanded error details preserve the outside bottom margin")
        tap(grabber)
        waitForValue("Half screen", on: grabber)
        tap(app.buttons["close-error-details"])

        tap(error)
        let dismissHandle = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        dismissHandle.press(forDuration: 0.1, thenDragTo: dismissHandle.withOffset(CGVector(dx: 0, dy: 180)))
        XCTAssertTrue(details.waitForNonExistence(timeout: 5))
        XCTAssertTrue(error.isHittable)

        error.press(forDuration: 1)
        attach(app, "Error copy context menu")
        tap(app.buttons["copy-error-error-agent-notice-1"])
        XCTAssertTrue(error.wait(for: \.isHittable, toEqual: true, timeout: 5))

        if UIDevice.current.userInterfaceIdiom == .pad {
            tap(app.descendants(matching: .any)["session-session-tests"])
            XCTAssertTrue(error.waitForNonExistence(timeout: 5))
        } else {
            tap(app.navigationBars.buttons.firstMatch)
        }
        tap(app.descendants(matching: .any)["session-session-error"])
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Agent internal error")
        XCTAssertTrue((error.value as? String)?.contains("\"status\":400") == true)
        XCTAssertEqual(work.value as? String, "Collapsed")
        attach(app, "Agent error after reopening")
    }

    @MainActor
    private func waitForValue(_ value: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
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
