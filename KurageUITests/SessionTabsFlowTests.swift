import XCTest

final class SessionTabsFlowTests: XCTestCase {
    @MainActor
    func testCreateSwitchCloseReopenKeepsIndependentDrafts() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        let root = app.descendants(matching: .any)["session-session-long"].firstMatch
        tap(root)
        let main = app.buttons["session-tab-session-long"]
        let newTab = app.buttons["new-session-tab"]
        XCTAssertTrue(newTab.waitForExistence(timeout: 5))
        XCTAssertFalse(main.exists)
        XCTAssertFalse(app.descendants(matching: .any)["session-tab-bar"].exists)
        XCTAssertLessThanOrEqual(newTab.frame.maxX, app.buttons["session-options"].frame.minX)
        attachScreen(name: "Single session without tab bar")
        let composer = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(composer)
        composer.typeText("Main draft remains here")
        tap(app.buttons["new-session-tab"])
        let firstMessage = app.descendants(matching: .any)["new-session-field"].firstMatch
        XCTAssertTrue(firstMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["New Tab"].exists)
        XCTAssertFalse(app.buttons["new-session-project"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["inherited-tab-project"].exists)
        XCTAssertTrue(app.buttons["add-attachment"].exists)
        XCTAssertFalse(app.buttons["new-session-send"].isEnabled)
        attachScreen(name: "New tab shared composer")
        let configuration = app.buttons["run-config-menu"]
        tap(configuration)
        tap(app.buttons["run-config-advanced"])
        tap(app.buttons["run-config-model"])
        tap(app.buttons["gpt-5.4-mini"])
        tap(app.buttons["run-config-reasoning"])
        tap(app.buttons["Low"])
        attachScreen(name: "New tab chosen model and reasoning")
        tap(app.buttons["run-config-done"])
        XCTAssertTrue(configuration.label.contains("gpt-5.4-mini"))
        XCTAssertTrue(configuration.label.contains("Low"))
        tap(firstMessage)
        firstMessage.typeText("Independent tab conversation")
        tap(app.buttons["new-session-send"])

        let child = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND identifier != %@", "session-tab-", "session-tab-session-long")).firstMatch
        XCTAssertTrue(child.waitForExistence(timeout: 5))
        let childID = child.identifier
        XCTAssertTrue(child.isSelected)
        XCTAssertTrue(main.exists)
        XCTAssertTrue(app.descendants(matching: .any)["session-tab-bar"].exists)
        XCTAssertTrue(configuration.wait(for: \.label, toEqual: "Model gpt-5.4-mini, reasoning Low", timeout: 5))
        XCTAssertTrue(app.staticTexts["Independent tab conversation"].firstMatch.exists)
        XCTAssertNotEqual(composer.value as? String, "Main draft remains here")
        tap(composer)
        composer.typeText("Child draft remains separate")
        attachScreen(name: "Session tabs child draft and keyboard")
        tap(main)
        XCTAssertEqual(composer.value as? String, "Main draft remains here")
        XCTAssertTrue(main.isSelected)
        tap(child)
        XCTAssertEqual(composer.value as? String, "Child draft remains separate")
        child.press(forDuration: 1)
        tap(app.buttons["Close tab"])
        XCTAssertTrue(child.waitForNonExistence(timeout: 5))
        XCTAssertFalse(main.exists)
        XCTAssertFalse(app.descendants(matching: .any)["session-tab-bar"].exists)
        XCTAssertEqual(composer.value as? String, "Main draft remains here")
        tap(app.buttons["session-options"])
        tap(app.buttons["closed-session-tabs"])
        attachScreen(name: "Session tabs closed menu")
        tap(app.buttons["Independent tab conversation"])
        XCTAssertTrue(app.buttons[childID].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[childID].isSelected)
        XCTAssertEqual(composer.value as? String, "Child draft remains separate")
        attachScreen(name: "Session tabs reopened")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["more-options"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "session-session-long").count, 1)
        XCTAssertFalse(app.descendants(matching: .any)["session-" + String(childID.dropFirst("session-tab-".count))].exists)
        tap(root)
        XCTAssertTrue(app.buttons[childID].waitForExistence(timeout: 5))
        attachScreen(name: "Session tabs after returning from list")
    }

    @MainActor
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
        element.tap()
    }

    @MainActor
    private func attachScreen(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
