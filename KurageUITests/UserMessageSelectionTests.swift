import XCTest

final class UserMessageSelectionTests: XCTestCase {
    @MainActor
    func testCopyPreservesWholeMultilineUnicodeMessage() {
        let app = openIdleConversation()
        let message = "Hello 中文 👋\nSecond line: café é"
        let bubble = send(message, in: app)
        showBubbleMenu(bubble, in: app)
        capture(app, name: "User message Copy and Select menu")
        app.buttons["Copy"].firstMatch.tap()
        pasteIntoComposer(app)
        XCTAssertEqual(composer(in: app).value as? String, message)
        capture(app, name: "Entire multiline Unicode message pasted")
    }

    @MainActor
    func testSelectInitiallySelectsAllAndReturnsToBubbleMenu() {
        let app = openIdleConversation()
        let bubble = app.staticTexts["Question 20"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        showBubbleMenu(bubble, in: app)
        app.buttons["Select"].firstMatch.tap()
        capture(app, name: "After choosing Select")
        XCTAssertTrue(editAction("Copy", in: app).waitForExistence(timeout: 5))
        if bubble.frame.height < 30 {
            XCTAssertTrue(editAction("Look Up", in: app).exists)
            XCTAssertTrue(editAction("Translate", in: app).exists)
        }
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture(app, name: "User message initially fully selected")
        editAction("Copy", in: app).tap()
        pasteIntoComposer(app)
        XCTAssertEqual(composer(in: app).value as? String, "Question 20")

        // Returning focus to the composer ends bubble selection. Dismiss its
        // keyboard before selecting again so the bubble keeps its visible frame.
        dismissKeyboard(app)
        showBubbleMenu(bubble, in: app)
        capture(app, name: "User message menu after ending selection")
        app.buttons["Copy"].firstMatch.tap()
        XCTAssertEqual(composer(in: app).value as? String, "Question 20")
    }

    @MainActor
    func testSelectionHandlesCanCopyShorterRange() {
        let app = openIdleConversation()
        let bubble = app.staticTexts["Question 20"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        showBubbleMenu(bubble, in: app)
        app.buttons["Select"].firstMatch.tap()
        XCTAssertTrue(editAction("Copy", in: app).waitForExistence(timeout: 5))
        capture(app, name: "Selection before shortening")
        let startHandle = bubble.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
        let shortenedStart = bubble.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        startHandle.press(forDuration: 0.2, thenDragTo: shortenedStart)
        capture(app, name: "User message shortened selection")
        XCTAssertTrue(editAction("Copy", in: app).waitForExistence(timeout: 5))
        editAction("Copy", in: app).tap()
        pasteIntoComposer(app)
        let copied = composer(in: app).value as? String ?? ""
        XCTAssertFalse(copied.isEmpty)
        XCTAssertNotEqual(copied, "Question 20")
        XCTAssertTrue("Question 20".contains(copied))
        capture(app, name: "Shortened message pasted")
    }

    @MainActor
    private func openIdleConversation() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
        app.buttons["sign-in-button"].tap()
        let session = app.descendants(matching: .any)["session-session-long"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.tap()
        XCTAssertTrue(composer(in: app).waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func composer(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["follow-up-field"].firstMatch
    }

    @MainActor
    private func send(_ message: String, in app: XCUIApplication) -> XCUIElement {
        let field = composer(in: app)
        field.tap()
        field.typeText(message)
        XCTAssertEqual(field.value as? String, message)
        app.buttons["send-follow-up"].tap()
        // UITextView exposes each paragraph as its own static-text child.
        // The parent carries the complete multiline message label.
        let bubble = app.textViews[message]
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        dismissKeyboard(app)
        return bubble
    }

    @MainActor
    private func showBubbleMenu(_ bubble: XCUIElement, in app: XCUIApplication) {
        let transcript = app.tables["conversation-transcript"]
        // A few visible pixels below the navigation bar count as hittable,
        // but both selection handles need the whole text to be on screen.
        let top = max(transcript.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        let hud = app.buttons["conversation-changes-hud"]
        let bottom = hud.exists ? hud.frame.minY : composer(in: app).frame.minY
        for _ in 0..<5 {
            if bubble.isHittable && bubble.frame.minY >= top && bubble.frame.maxY <= bottom { break }
            let centerY = (top + bottom) / 2
            let adjustment = min(200, max(-200, centerY - bubble.frame.midY))
            let start = transcript.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 30, dy: centerY - transcript.frame.minY))
            start.press(forDuration: 0.01,
                        thenDragTo: start.withOffset(CGVector(dx: 0, dy: adjustment)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(bubble.isHittable)
        XCTAssertGreaterThanOrEqual(bubble.frame.minY, top)
        XCTAssertLessThanOrEqual(bubble.frame.maxY, bottom)
        capture(app, name: "Before user message long press")
        bubble.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Copy"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Select"].firstMatch.exists)
    }

    @MainActor
    private func editAction(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)",
                                  title, XCUIElement.ElementType.menuItem.rawValue,
                                  XCUIElement.ElementType.button.rawValue)).firstMatch
    }

    @MainActor
    private func pasteIntoComposer(_ app: XCUIApplication) {
        let field = composer(in: app)
        field.tap()
        field.press(forDuration: 1)
        let paste = editAction("Paste", in: app)
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        let allow = app.buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 1) { allow.tap() }
    }

    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        let transcript = app.tables["conversation-transcript"]
        transcript.swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        transcript.swipeUp()
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
