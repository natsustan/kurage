import XCTest
import UIKit

final class AdaptiveLayoutFlowTests: XCTestCase {
    @MainActor
    func testIPadNewSessionKeyboardKeepsSidebarPosition() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        let account = app.buttons["account-menu"]
        let toggle = app.buttons["toggle-session-sidebar"]
        let project = app.buttons["project-header-local:machine-1:prism"]
        let row = session("session-tests", in: app)
        let list = app.tables["session-browser"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(toggle.frame.minX, account.frame.minX)
        XCTAssertLessThan(toggle.frame.maxX, app.buttons["more-options"].frame.minX)
        let accountFrame = account.frame
        let projectFrame = project.frame
        let rowFrame = row.frame
        let listFrame = list.frame
        tap(app.buttons["new-session-local:machine-1:prism"])
        let field = app.descendants(matching: .any)["new-session-field"].firstMatch
        tap(field)
        field.typeText("Keep the sidebar steady")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertEqual(account.frame.minY, accountFrame.minY, accuracy: 1)
        XCTAssertEqual(project.frame.minY, projectFrame.minY, accuracy: 1)
        XCTAssertEqual(row.frame.minY, rowFrame.minY, accuracy: 1)
        XCTAssertEqual(list.frame.minY, listFrame.minY, accuracy: 1)
        XCTAssertLessThanOrEqual(list.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertLessThanOrEqual(app.buttons["new-session-send"].frame.maxY, keyboard.frame.minY + 1)
        let search = app.textFields["session-search"]
        XCTAssertLessThanOrEqual(search.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertTrue(search.isHittable)
        attach(app, "New session keyboard with a steady sidebar")

        tap(row)
        XCTAssertTrue(row.wait(for: \.isSelected, toEqual: true, timeout: 5))
        let reply = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(reply)
        reply.typeText("Existing conversation keyboard")
        XCTAssertEqual(account.frame.minY, accountFrame.minY, accuracy: 1)
        XCTAssertEqual(project.frame.minY, projectFrame.minY, accuracy: 1)
        XCTAssertEqual(row.frame.minY, rowFrame.minY, accuracy: 1)
        XCTAssertEqual(list.frame.minY, listFrame.minY, accuracy: 1)
        XCTAssertLessThanOrEqual(list.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertLessThanOrEqual(search.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertTrue(search.isHittable)
        attach(app, "Selected session pill and column divider")

        list.swipeUp()
        let last = session("session-pr", in: app)
        XCTAssertTrue(last.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertLessThan(last.frame.midY, search.frame.minY)
        attach(app, "Last sidebar row above floating search")
        tap(last)
        XCTAssertTrue(last.wait(for: \.isSelected, toEqual: true, timeout: 5))
    }

    @MainActor
    func testIPadSidebarCollapsePreservesConversationAndDraft() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        tap(session("session-tests", in: app))
        let field = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(field)
        field.typeText("Draft with sidebar hidden")
        app.tables["conversation-transcript"].swipeDown()
        tap(app.buttons["toggle-session-sidebar"])
        XCTAssertTrue(app.buttons["account-menu"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Draft with sidebar hidden")
        attach(app, "Conversation with sidebar hidden")
        tap(app.buttons["toggle-session-sidebar"])
        XCTAssertTrue(app.buttons["account-menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(session("session-tests", in: app).isSelected)
        XCTAssertEqual(field.value as? String, "Draft with sidebar hidden")
        attach(app, "Sidebar restored beside conversation")
    }

    @MainActor
    func testIPadSearchesOtherConversationBodiesWithDetailOpen() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        tap(session("session-tests", in: app))
        let transcript = app.tables["conversation-transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        let search = app.textFields["session-search"]
        tap(search)
        search.typeText("Question 7")
        let result = session("session-long", in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.isHittable)
        XCTAssertFalse(session("session-tests", in: app).exists)
        XCTAssertTrue(transcript.exists)
        tap(result)
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        XCTAssertTrue(result.isSelected)
        attach(app, "Body search while detail remains open")
    }

    @MainActor
    func testIPadRestoredFirstTurnSurvivesSidebarArchive() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(arguments: ["--fixture-start-rejected"])
        tap(app.buttons["new-session-local:machine-1:prism"])
        let field = app.descendants(matching: .any)["new-session-field"].firstMatch
        tap(field)
        field.typeText("Restore this first turn")
        tap(app.buttons["new-session-send"])
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "edit-message-")).firstMatch
        tap(edit)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Restore this first turn")
        let other = session("session-tests", in: app)
        XCTAssertTrue(other.wait(for: \.isHittable, toEqual: true, timeout: 5))
        other.press(forDuration: 1)
        tap(app.buttons["Archive"])
        tap(app.buttons["archive-confirm"].firstMatch)
        XCTAssertTrue(other.waitForNonExistence(timeout: 10))
        XCTAssertTrue(field.exists)
        XCTAssertEqual(field.value as? String, "Restore this first turn")
        attach(app, "Restored first turn after sidebar archive")
    }

    @MainActor
    func testDraftSurvivesRotationAndSessionSwitching() {
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let main = session("session-long", in: app)
        tap(main)
        let field = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(field)
        field.typeText("Draft survives window changes")
        app.tables["conversation-transcript"].swipeDown()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Draft survives window changes")
        attach(app, "Landscape conversation")

        XCUIDevice.shared.orientation = .portrait
        showSessions(app, target: session("session-tests", in: app))
        tap(session("session-tests", in: app))
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse((field.value as? String)?.contains("Draft survives") == true)
        tap(field)
        field.typeText("Independent second draft")
        app.tables["conversation-transcript"].swipeDown()
        showSessions(app, target: main)
        tap(main)
        XCTAssertEqual(field.value as? String, "Draft survives window changes")
        attach(app, "Restored session draft")

        showSessions(app, target: session("session-tests", in: app))
        tap(session("session-tests", in: app))
        XCTAssertEqual(field.value as? String, "Independent second draft")
    }

    @MainActor
    func testIPadSidebarAndReadableConversationWidth() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["session-detail-empty"].waitForExistence(timeout: 5))
        let main = session("session-long", in: app)
        tap(main)
        let transcript = app.tables["conversation-transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        XCTAssertTrue(main.isHittable)
        XCTAssertTrue(main.isSelected)
        XCTAssertLessThanOrEqual(transcript.frame.width, 801)
        XCTAssertGreaterThan(transcript.frame.minX, main.frame.maxX)
        let field = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(field)
        field.typeText("Keyboard stays in the conversation column")
        let send = app.buttons["send-follow-up"]
        XCTAssertTrue(send.isHittable)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        attach(app, "iPad sidebar and keyboard")
    }

    @MainActor
    func testArchivingSelectedSessionClearsTheDetail() {
        let app = launch()
        tap(session("session-long", in: app))
        tap(app.buttons["session-options"])
        tap(app.buttons["Archive"])
        let confirmation = app.buttons["archive-confirm"].firstMatch
        tap(confirmation)
        XCTAssertTrue(session("session-tests", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.tables["conversation-transcript"].exists)
        tap(session("session-tests", in: app))
        XCTAssertTrue(app.tables["conversation-transcript"].waitForExistence(timeout: 5))
        attach(app, "Next conversation after archiving")
    }

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"] + arguments
        app.launch()
        tap(app.buttons["sign-in-button"])
        return app
    }

    @MainActor
    private func session(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["session-\(id)"].firstMatch
    }

    @MainActor
    private func showSessions(_ app: XCUIApplication, target: XCUIElement) {
        if !target.isHittable {
            tap(app.navigationBars.buttons.firstMatch)
        }
        XCTAssertTrue(target.waitForExistence(timeout: 5))
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
