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
        XCTAssertTrue(app.staticTexts["look again"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Run the tests again"].isHittable)
        attachScreen(app, name: "sent")
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
        XCTAssertTrue(latest.isHittable)
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
