import XCTest
import UIKit

final class AdaptiveLayoutFlowTests: XCTestCase {
    @MainActor
    func testIPhoneReturningFromKeyboardKeepsSessionRowsAndSearchUsable() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        let app = launch(arguments: ["--fixture-long-session-list"])
        let list = app.tables["session-browser"]
        let search = app.textFields["session-search"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let listFrame = list.frame
        let searchFrame = search.frame
        let visibleRows = list.cells.allElementsBoundByIndex.filter {
            $0.identifier.hasPrefix("session-") && $0.isHittable && $0.frame.maxY < searchFrame.minY
        }.map { (id: $0.identifier, frame: $0.frame) }
        XCTAssertGreaterThan(visibleRows.count, 3)

        for usesGesture in [false, true] {
            tap(session("session-long", in: app))
            let field = app.descendants(matching: .any)["follow-up-field"].firstMatch
            tap(field)
            if !usesGesture { field.typeText("Keep this draft when returning") }
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
            try XCTSkipIf(!app.frame.intersects(keyboard.frame) || !keyboard.isHittable,
                          "This regression requires the simulator software keyboard to be visible.")
            XCTAssertEqual(field.value as? String, "Keep this draft when returning")
            attach(app, usesGesture ? "Keyboard before swipe back" : "Keyboard before back button")

            if usesGesture {
                let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.4))
                let destination = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.4))
                edge.press(forDuration: 0.1, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 1)
            } else {
                tap(app.navigationBars.buttons.firstMatch)
            }

            XCTAssertTrue(search.waitForExistence(timeout: 5))
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
            XCTAssertEqual(list.frame.maxY, listFrame.maxY, accuracy: 1)
            XCTAssertEqual(search.frame.minY, searchFrame.minY, accuracy: 1)
            for row in visibleRows {
                let restored = list.cells[row.id]
                XCTAssertTrue(restored.exists, row.id)
                XCTAssertTrue(restored.isHittable, row.id)
                XCTAssertEqual(restored.frame.minY, row.frame.minY, accuracy: 1, row.id)
            }
            attach(app, usesGesture ? "Session rows after swipe back" : "Session rows after back button")
        }

        tap(search)
        search.typeText("kurage session 8")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(session("list-kurage-8", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        XCTAssertLessThanOrEqual(search.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        attach(app, "List search still avoids its own keyboard")
    }

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
        XCTAssertGreaterThan(toggle.frame.minX, list.frame.maxX)
        let accountFrame = account.frame
        let projectFrame = project.frame
        let rowFrame = row.frame
        let listFrame = list.frame
        let search = app.textFields["session-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let searchFrame = search.frame
        func assertSidebarSteady(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(account.frame.minY, accountFrame.minY, accuracy: 1, file: file, line: line)
            XCTAssertEqual(project.frame.minY, projectFrame.minY, accuracy: 1, file: file, line: line)
            XCTAssertEqual(row.frame.minY, rowFrame.minY, accuracy: 1, file: file, line: line)
            XCTAssertEqual(list.frame.minY, listFrame.minY, accuracy: 1, file: file, line: line)
            XCTAssertEqual(list.frame.maxY, listFrame.maxY, accuracy: 1, file: file, line: line)
            XCTAssertEqual(search.frame.minY, searchFrame.minY, accuracy: 1, file: file, line: line)
        }
        tap(app.buttons["new-session-local:machine-1:prism"])
        let field = app.descendants(matching: .any)["new-session-field"].firstMatch
        tap(field)
        field.typeText("Keep the sidebar steady")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        assertSidebarSteady()
        XCTAssertLessThanOrEqual(app.buttons["new-session-send"].frame.maxY, keyboard.frame.minY + 1)
        attach(app, "New session keyboard with a steady sidebar")

        tap(row)
        XCTAssertTrue(row.wait(for: \.isSelected, toEqual: true, timeout: 5))
        let reply = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(reply)
        reply.typeText("Existing conversation keyboard")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        assertSidebarSteady()
        XCTAssertLessThanOrEqual(app.buttons["send-follow-up"].frame.maxY, keyboard.frame.minY + 1)
        attach(app, "Selected session pill and column divider")
    }

    @MainActor
    func testIPadSidebarCollapsePreservesConversationAndDraft() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        tap(session("session-tests", in: app))
        let toggle = app.buttons["toggle-session-sidebar"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let toggleFrame = toggle.frame
        let sidebar = app.tables["session-browser"]
        let leadingOffset = toggleFrame.minX - sidebar.frame.maxX
        XCTAssertGreaterThan(leadingOffset, 0)
        XCTAssertEqual(toggle.label, "Hide sidebar")
        let title = app.staticTexts["conversation-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let titleOffset = title.frame.minX - toggleFrame.maxX
        XCTAssertGreaterThanOrEqual(titleOffset, 0)
        XCTAssertLessThan(titleOffset, 40)
        let field = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(field)
        field.typeText("Draft with sidebar hidden")
        app.tables["conversation-transcript"].swipeDown()
        tap(app.buttons["toggle-session-sidebar"])
        XCTAssertTrue(app.buttons["account-menu"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(toggle.frame.minX - app.frame.minX, leadingOffset, accuracy: 1)
        XCTAssertEqual(toggle.frame.midY, toggleFrame.midY, accuracy: 1)
        XCTAssertEqual(toggle.label, "Show sidebar")
        XCTAssertEqual(title.frame.minX - toggle.frame.maxX, titleOffset, accuracy: 1)
        XCTAssertEqual(field.value as? String, "Draft with sidebar hidden")
        attach(app, "Conversation with sidebar hidden")
        tap(app.buttons["toggle-session-sidebar"])
        XCTAssertTrue(app.buttons["account-menu"].waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.frame.minX - sidebar.frame.maxX, leadingOffset, accuracy: 1)
        XCTAssertEqual(toggle.frame.midY, toggleFrame.midY, accuracy: 1)
        XCTAssertEqual(toggle.label, "Hide sidebar")
        XCTAssertEqual(title.frame.minX - toggle.frame.maxX, titleOffset, accuracy: 1)
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
        if UIDevice.current.userInterfaceIdiom == .phone {
            let window = app.windows.firstMatch.frame
            XCTAssertLessThan(window.width, window.height)
        }
        attach(app, "Conversation after device rotation")

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
