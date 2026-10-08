import XCTest
import AppKit

@MainActor
final class MacFlowTests: XCTestCase {
    func testConversationChangesAndNewTab() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        app.activate()
        let session = app.staticTexts["session-session-long"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        app.activate()
        try await capture(app, name: "mac-sidebar")
        session.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let editor = app.textViews["message-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["changes-inspector"].exists)
        try await capture(app, name: "mac-default")
        paste("Keep main draft", into: editor, app: app)
        app.buttons["toggle-changes"].click()
        XCTAssertTrue(app.staticTexts["ConversationView.swift"].waitForExistence(timeout: 10))
        app.disclosureTriangles.matching(NSPredicate(format: "label CONTAINS %@", "ConversationView.swift")).firstMatch.click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "let showsChanges = true")).firstMatch.waitForExistence(timeout: 10))
        try await capture(app, name: "mac-changes")
        app.buttons["toggle-changes"].click()
        XCTAssertEqual(editor.value as? String, "Keep main draft")
        app.buttons["new-tab"].click()
        let firstMessage = app.textViews["new-message"]
        XCTAssertTrue(firstMessage.waitForExistence(timeout: 10))
        XCTAssertTrue(app.popUpButtons["new-model"].waitForExistence(timeout: 10))
        paste("Mac new tab integration", into: firstMessage, app: app)
        try await capture(app, name: "mac-new-session")
        app.buttons["start-session"].click()
        XCTAssertTrue(app.staticTexts["Mac new tab integration"].waitForExistence(timeout: 10))
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "")
        app.buttons["tab-session-long"].click()
        XCTAssertEqual(editor.value as? String, "Keep main draft")
        app.buttons["send-message"].click()
        XCTAssertTrue(app.staticTexts["Keep main draft"].waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "")
    }

    func testDarkNewRootSessionAndSignOut() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-dark"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.menuButtons["new-session"].waitForExistence(timeout: 15))
        app.menuButtons["new-session"].click()
        app.menuItems["kurage"].click()
        let editor = app.textViews["new-message"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let model = app.popUpButtons["new-model"]
        XCTAssertTrue(model.waitForExistence(timeout: 10))
        model.click()
        app.menuItems["gpt-5.4-mini"].click()
        XCTAssertTrue((model.value as? String ?? "").contains("gpt-5.4-mini"))
        paste("Mac root integration", into: editor, app: app)
        try await capture(app, name: "mac-new-root-dark")
        app.buttons["start-session"].click()
        XCTAssertTrue(app.staticTexts["Mac root integration"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textViews["message-editor"].waitForExistence(timeout: 10))
        try await capture(app, name: "mac-conversation-dark")
        app.buttons["Sign out"].click()
        XCTAssertTrue(app.sheets.buttons["Sign out"].waitForExistence(timeout: 5))
        app.sheets.buttons["Sign out"].click()
        XCTAssertTrue(app.buttons["Sign in with Lody"].waitForExistence(timeout: 10))
        try await capture(app, name: "mac-sign-in")
    }

    func testImagePreview() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        app.activate()
        let session = app.staticTexts["session-session-pr"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        session.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let image = app.buttons["result.png"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        try await capture(app, name: "mac-images")
        let thumbnailWidth = image.frame.width
        image.click()
        XCTAssertGreaterThan(image.frame.width, thumbnailWidth)
        try await capture(app, name: "mac-image-expanded")
    }

    private func paste(_ text: String, into editor: XCUIElement, app: XCUIApplication) {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let change = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == change {
                pasteboard.clearContents()
                pasteboard.writeObjects(saved)
            }
        }
        app.activate()
        editor.click()
        editor.typeKey("v", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, text)
    }

    private func capture(_ app: XCUIApplication, name: String) async throws {
        app.activate()
        try await Task.sleep(for: .milliseconds(300))
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
