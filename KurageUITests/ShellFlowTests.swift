import XCTest

final class ShellFlowTests: XCTestCase {
    @MainActor
    func testSessionListModesAndMoreMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        let connect = app.buttons["sign-in-button"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        tap(connect)

        let projectHeading = app.staticTexts["kurage"]
        XCTAssertTrue(projectHeading.waitForExistence(timeout: 5))

        let more = app.buttons["more-options"]
        tap(more)
        let byTime = app.buttons["By Time"]
        XCTAssertTrue(byTime.waitForExistence(timeout: 2))
        tap(byTime)
        XCTAssertFalse(projectHeading.exists)
        XCTAssertTrue(app.descendants(matching: .any)["session-session-tests"].exists)

        tap(more)
        let byProject = app.buttons["By Project"]
        XCTAssertTrue(byProject.waitForExistence(timeout: 2))
        tap(byProject)
        XCTAssertTrue(projectHeading.exists)

        tap(more)
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSignInOpenSessionAllowAndSend() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()

        let connect = app.buttons["sign-in-button"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["See running sessions when you step away."].exists)
        XCTAssertEqual(connect.label, "Connect Lody Cloud")
        attachScreen(app, name: "sign-in")
        tap(connect)

        let session = app.descendants(matching: .any)["session-session-tests"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(session.label.contains("fix flaky tests"))
        XCTAssertTrue(app.descendants(matching: .any)["session-session-pr"].exists)
        attachScreen(app, name: "sessions")
        tap(session)

        let review = app.buttons["permission-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Allow npm test?"].exists)
        let firstMessage = app.staticTexts["Run the tests again"]
        XCTAssertTrue(firstMessage.waitForExistence(timeout: 5))
        let firstMessageVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: firstMessage
        )
        XCTAssertEqual(XCTWaiter.wait(for: [firstMessageVisible], timeout: 5), .completed)
        attachScreen(app, name: "conversation")
        tap(review)
        let allow = app.buttons["permission-allow"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        tap(allow)
        XCTAssertFalse(review.waitForExistence(timeout: 2))

        let field = app.descendants(matching: .any)["follow-up-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        tap(field)
        field.typeText("look again")

        tap(app.buttons["send-follow-up"])
        let sentMessage = app.staticTexts["look again"]
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Run the tests again"].isHittable)
        XCTAssertLessThan(field.frame.minY - sentMessage.frame.maxY, 160)
        attachScreen(app, name: "sent")

        app.tables["conversation-transcript"].swipeDown()
        XCTAssertFalse(app.keyboards.firstMatch.isHittable)
        tap(field)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThan(field.frame.minY - sentMessage.frame.maxY, 160)
        attachScreen(app, name: "keyboard-reopened")
    }

    @MainActor
    func testLongConversationOpensAtLatestMessage() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])

        let session = app.descendants(matching: .any)["session-session-long"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        tap(session)

        let latest = app.staticTexts["Latest reply in long conversation"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertTrue(latest.wait(for: \.frame.isEmpty, toEqual: false, timeout: 5))
        let transcript = app.tables["conversation-transcript"]
        let composer = app.otherElements["follow-up-composer"]
        let visibleTranscript = CGRect(x: transcript.frame.minX, y: transcript.frame.minY,
                                       width: transcript.frame.width,
                                       height: composer.frame.minY - transcript.frame.minY)
        XCTAssertTrue(visibleTranscript.contains(latest.frame))

        transcript.swipeDown()
        XCTAssertFalse(latest.exists && visibleTranscript.intersects(latest.frame))
        tap(app.descendants(matching: .any)["follow-up-field"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(latest.isHittable)
    }

    @MainActor
    func testKeyboardAndMultilineComposerKeepLatestMessageVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        let session = app.descendants(matching: .any)["session-session-long"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        tap(session)

        let latest = app.staticTexts["Latest reply in long conversation"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        let field = app.descendants(matching: .any)["follow-up-field"]
        for _ in 0..<2 {
            tap(field)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            assertMessageAboveComposer(latest, field: field)
            app.tables["conversation-transcript"].swipeDown()
            XCTAssertFalse(app.keyboards.firstMatch.isHittable)
            // Dismissing the keyboard also scrolls into history. Reach the actual bottom
            // (not just a visible last row) before testing automatic following again.
            app.tables["conversation-transcript"].swipeUp()
            app.tables["conversation-transcript"].swipeUp()
        }
        tap(field)
        let composer = app.otherElements["follow-up-composer"]
        let singleLineHeight = composer.frame.height
        field.typeText("First line\nSecond line\nThird line\nFourth line\nFifth line")
        XCTAssertGreaterThan(composer.frame.height, singleLineHeight + 50)
        XCTAssertTrue(composer.frame.contains(field.frame))
        XCTAssertLessThanOrEqual(composer.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertTrue(composer.frame.contains(app.buttons["send-follow-up"].frame))
        assertMessageAboveComposer(latest, field: field)
        attachScreen(app, name: "multiline-keyboard")
        tap(app.buttons["send-follow-up"])
        let sent = app.staticTexts["First line\nSecond line\nThird line\nFourth line\nFifth line"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        XCTAssertTrue(sent.wait(for: \.frame.isEmpty, toEqual: false, timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.isHittable)
        XCTAssertGreaterThan(sent.frame.height, 70)
        XCTAssertGreaterThan(sent.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(sent.frame.maxY, field.frame.minY)
        attachScreen(app, name: "multiline-sent")
    }

    @MainActor
    private func assertMessageAboveComposer(_ message: XCUIElement, field: XCUIElement,
                                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(message.isHittable, file: file, line: line)
        XCTAssertLessThanOrEqual(message.frame.maxY, field.frame.minY, file: file, line: line)
        XCTAssertLessThan(field.frame.minY - message.frame.maxY, 100, file: file, line: line)
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    @MainActor
    private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
