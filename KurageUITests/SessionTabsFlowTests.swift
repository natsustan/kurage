import XCTest

final class SessionTabsFlowTests: XCTestCase {
    @MainActor
    func testSuccessfulSendKeepsItsStateAcrossTabSwitches() {
        verifySendAcrossTabSwitches(fails: false)
    }

    @MainActor
    func testUnconfirmedSendKeepsItsBubbleAndNextDraftAcrossTabs() {
        verifySendAcrossTabSwitches(fails: true)
    }

    @MainActor
    private func verifySendAcrossTabSwitches(fails: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-tab-send"] + (fails ? ["--fixture-send-unconfirmed"] : [])
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"].firstMatch)
        tap(app.buttons["new-session-tab"])
        let firstMessage = app.descendants(matching: .any)["new-session-field"].firstMatch
        tap(firstMessage)
        firstMessage.typeText("Other tab")
        tap(app.buttons["new-session-send"])
        let child = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND identifier != %@", "session-tab-", "session-tab-session-long")).firstMatch
        XCTAssertTrue(child.waitForExistence(timeout: 5))
        let main = app.buttons["session-tab-session-long"]
        tap(main)
        let field = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(field)
        if fails {
            field.typeText("$review")
            tap(app.buttons["mention-skill-review-and-simplify-changes"])
        }
        field.typeText("In-flight main message")
        let send = app.buttons["send-follow-up"]
        tap(send)
        XCTAssertEqual(send.label, "Sending")
        XCTAssertTrue(field.isEnabled)
        tap(child)
        tap(field)
        field.typeText("Child stays editable")
        tap(main)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "In-flight main message")).firstMatch.exists)
        XCTAssertTrue(field.isEnabled)
        XCTAssertTrue(field.value as? String == "" || field.value as? String == "Send a follow-up")
        tap(field)
        field.typeText("Next main draft")
        attachScreen(name: "Send still pending after tab switch")
        XCTAssertTrue(send.wait(for: \.label, toEqual: "Send", timeout: 20))
        if fails {
            XCTAssertEqual(field.value as? String, "Next main draft")
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "retry-message-")).firstMatch.exists)
            XCTAssertFalse(send.isEnabled)
        } else {
            XCTAssertEqual(field.value as? String, "Next main draft")
            XCTAssertEqual(app.staticTexts.matching(identifier: "In-flight main message").count, 1)
        }
        tap(child)
        XCTAssertEqual(field.value as? String, "Child stays editable")
    }

    @MainActor
    func testProviderSkillRefreshBlocksSendAndOffersRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-skill-refresh"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["new-session-local:machine-1:prism"])
        let field = app.descendants(matching: .any)["new-session-field"].firstMatch
        tap(field)
        field.typeText("$review")
        tap(app.buttons["mention-skill-review-and-simplify-changes"])
        let send = app.buttons["new-session-send"]
        XCTAssertTrue(send.isEnabled)
        tap(app.buttons["run-config-menu"])
        tap(app.buttons["run-config-advanced"])
        tap(app.buttons["run-config-provider"])
        tap(app.buttons["Codex"])
        tap(app.buttons["run-config-done"])
        XCTAssertFalse(send.isEnabled)
        let retry = app.buttons["mention-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertFalse(send.isEnabled)
        XCTAssertTrue((field.value as? String)?.contains("$review-and-simplify-changes") == true)
        attachScreen(name: "Skill refresh failure with preserved draft")
        tap(retry)
        XCTAssertFalse(send.isEnabled)
        attachScreen(name: "Skill refresh loading with preserved draft")
        XCTAssertTrue(send.wait(for: \.isEnabled, toEqual: true, timeout: 8))
        XCTAssertTrue(retry.waitForNonExistence(timeout: 5))
        tap(send)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND NOT label CONTAINS %@", "review-and-simplify-changes", "Skill Path"))
            .firstMatch.waitForExistence(timeout: 5))
    }

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

        // A third, long-titled tab: with three pills the restored tab can start
        // outside the bar's viewport, so re-entry must scroll it into view.
        tap(app.buttons["new-session-tab"])
        let thirdMessage = app.descendants(matching: .any)["new-session-field"].firstMatch
        XCTAssertTrue(thirdMessage.waitForExistence(timeout: 5))
        tap(thirdMessage)
        thirdMessage.typeText("Another long tab conversation")
        tap(app.buttons["new-session-send"])
        let third = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND identifier != %@ AND identifier != %@",
            "session-tab-", "session-tab-session-long", childID)).firstMatch
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        XCTAssertTrue(third.isSelected)
        let thirdID = third.identifier
        attachScreen(name: "Session tabs third tab")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["more-options"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "session-session-long").count, 1)
        XCTAssertFalse(app.descendants(matching: .any)["session-" + String(childID.dropFirst("session-tab-".count))].exists)
        tap(root)
        XCTAssertTrue(app.buttons[thirdID].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[thirdID].isSelected)
        // The restored pill starts outside the bar's viewport, so re-entry has to
        // scroll it into view instead of leaving it clipped at the edge.
        XCTAssertTrue(app.buttons[thirdID].wait(for: \.isHittable, toEqual: true, timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(app.buttons[thirdID].frame.minX, window.minX)
        XCTAssertLessThanOrEqual(app.buttons[thirdID].frame.maxX, window.maxX)
        XCTAssertTrue(app.staticTexts["Another long tab conversation"].firstMatch.exists)
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
