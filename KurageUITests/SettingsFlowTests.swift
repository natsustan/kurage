import XCTest
import UIKit

final class SettingsFlowTests: XCTestCase {
    @MainActor
    func testThemeChangesApplyToSettingsAndPersistAfterRelaunch() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "Background sampling uses the iPhone sheet inset; iPad theme changes have a separate test.")
        let app = launch(arguments: ["--fixture-settings"])
        tap(app.buttons["account-menu"])
        selectTheme("System", in: app)
        let systemBrightness = try settingsBackgroundBrightness(in: app)
        attach(app, "Settings follows system theme")
        selectTheme("Dark", in: app)
        XCTAssertLessThan(try settingsBackgroundBrightness(in: app), 0.5)
        attach(app, "Settings with Dark theme and MingCute icons")
        tap(app.buttons["settings-workspace"])
        XCTAssertTrue(app.scrollViews["workspace-picker"].waitForExistence(timeout: 5))
        attach(app, "Workspace picker inherits Dark theme")
        tap(app.buttons["workspace-picker-close"])
        tap(app.buttons["settings-about"])
        XCTAssertTrue(app.navigationBars["About Kurage"].waitForExistence(timeout: 5))
        attach(app, "About inherits Dark theme")
        tap(app.navigationBars["About Kurage"].buttons.element(boundBy: 0))
        selectTheme("Light", in: app)
        XCTAssertGreaterThan(try settingsBackgroundBrightness(in: app), 0.7)
        attach(app, "Settings with Light theme and MingCute icons")
        tap(app.buttons["settings-close"])
        attach(app, "Session list inherits Light theme")

        app.terminate()
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["account-menu"])
        XCTAssertEqual(app.buttons["settings-theme"].value as? String, "Light")
        XCTAssertGreaterThan(try settingsBackgroundBrightness(in: app), 0.7)
        attach(app, "Light theme restored after relaunch")
        selectTheme("System", in: app)
        XCTAssertEqual(try settingsBackgroundBrightness(in: app), systemBrightness, accuracy: 0.1)
        attach(app, "Settings returns to system theme")
    }

    @MainActor
    private func settingsBackgroundBrightness(in app: XCUIApplication) throws -> Double {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        // The sheet's left inset stays clear of cards at every text size and scroll position.
        let point = CGRect(x: CGFloat(image.width) * 0.02, y: CGFloat(image.height) * 0.5, width: 1, height: 1)
        let sample = try XCTUnwrap(image.cropping(to: point))
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel.prefix(3).reduce(0.0) { $0 + Double($1) } / (3 * 255)
    }

    @MainActor
    func testWorkspaceSwitchKeepsSettingsAndRestoresIsolatedLists() {
        let app = launch(arguments: ["--fixture-settings"])
        tap(app.buttons["account-menu"])
        let workspace = app.buttons["settings-workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 5))
        XCTAssertEqual(workspace.value as? String, "Demo")
        attach(app, "Settings account and workspace")
        tap(workspace)
        let picker = app.scrollViews["workspace-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let demo = app.buttons["workspace-option-ws-demo"]
        XCTAssertTrue(demo.isSelected)
        XCTAssertLessThan(picker.frame.height, app.frame.height * 0.65)
        attach(app, "Compact workspace picker")
        tap(app.buttons["workspace-option-ws-studio"])
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        XCTAssertEqual(workspace.value as? String, "Studio")
        attach(app, "Settings survives workspace switch")
        tap(app.buttons["settings-close"])
        XCTAssertTrue(app.staticTexts["No sessions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["session-session-long"].exists)
        tap(app.buttons["account-menu"])
        tap(workspace)
        XCTAssertTrue(app.buttons["workspace-option-ws-studio"].isSelected)
        tap(demo)
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertEqual(workspace.value as? String, "Demo")
        tap(app.buttons["settings-close"])
        XCTAssertTrue(app.descendants(matching: .any)["session-session-long"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWorkspaceRefreshFailureKeepsRowsAndRetries() {
        let app = launch(arguments: ["--fixture-settings", "--fixture-workspace-failure"])
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-workspace"])
        XCTAssertTrue(app.buttons["workspace-option-ws-demo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workspace-option-ws-studio"].exists)
        XCTAssertTrue(app.staticTexts["workspace-error"].waitForExistence(timeout: 5))
        attach(app, "Cached workspaces with retry")
        tap(app.buttons["workspace-retry"])
        let loading = app.descendants(matching: .any)["workspace-loading"].firstMatch
        XCTAssertTrue(loading.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["workspace-error"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workspace-option-ws-demo"].isSelected)
        tap(app.buttons["workspace-option-ws-demo"])
        XCTAssertTrue(app.scrollViews["workspace-picker"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings-workspace"].value as? String, "Demo")
        tap(app.buttons["settings-about"])
        XCTAssertTrue(app.navigationBars["About Kurage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Version"].exists)
        XCTAssertTrue(app.staticTexts["Build"].exists)
        attach(app, "About Kurage")
    }

    @MainActor
    func testSignOutCanBeCancelledThenConfirmed() {
        let app = launch()
        tap(app.buttons["account-menu"])
        tap(app.buttons["sign-out-button"])
        let confirm = app.buttons["sign-out-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        attach(app, "Native sign out confirmation")
        if app.buttons["Cancel"].exists {
            tap(app.buttons["Cancel"])
        } else {
            // Native popovers cancel when tapping outside their bounds.
            app.staticTexts["settings-account"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-workspace"].exists)
        tap(app.buttons["sign-out-button"])
        tap(confirm)
        XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings-workspace"].exists)
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["account-menu"])
        XCTAssertEqual(app.buttons["settings-workspace"].value as? String, "Demo")
        attach(app, "Settings after sign in again")
    }

    @MainActor
    func testEmptyWorkspaceListHasRefreshAndCanClose() {
        let app = launch(arguments: ["--fixture-empty-workspaces"])
        tap(app.buttons["account-menu"])
        XCTAssertEqual(app.buttons["settings-workspace"].value as? String, "None selected")
        tap(app.buttons["settings-workspace"])
        XCTAssertTrue(app.staticTexts["No workspaces"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Refresh"].exists)
        attach(app, "Empty workspace picker")
        tap(app.buttons["workspace-picker-close"])
        XCTAssertTrue(app.buttons["settings-workspace"].exists)
    }

    @MainActor
    func testLongWorkspaceListScrollsAndSelectsLastItem() {
        let app = launch(arguments: ["--fixture-many-workspaces"])
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-workspace"])
        let picker = app.scrollViews["workspace-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let last = app.buttons["workspace-option-ws-extra-12"]
        for _ in 0..<10 {
            if last.isHittable { break }
            picker.swipeUp()
        }
        XCTAssertTrue(last.isHittable)
        attach(app, "Long workspace names and scrolling")
        tap(last)
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings-workspace"].value as? String,
                       "Studio 12 · Mobile Application Development")
        attach(app, "Settings with a long workspace name")
    }

    @MainActor
    func testIPadSettingsDefersReadReceiptAndPreservesDraft() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(arguments: ["--fixture-slow-conversation"])
        let row = app.descendants(matching: .any)["session-session-long"].firstMatch
        tap(row)
        tap(app.buttons["account-menu"])
        let readWhileCovered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Idle, Read"), object: row)
        readWhileCovered.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [readWhileCovered], timeout: 4), .completed)
        attach(app, "iPad settings above loading conversation")
        tap(app.buttons["settings-close"])
        let read = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Idle, Read"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [read], timeout: 5), .completed)
        let field = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(field)
        field.typeText("Keep this draft while settings is open")
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-workspace"])
        tap(app.buttons["workspace-option-ws-demo"])
        tap(app.buttons["settings-close"])
        XCTAssertEqual(field.value as? String, "Keep this draft while settings is open")
        attach(app, "iPad conversation draft after settings")
    }

    @MainActor
    func testIPadThemeChangesPreserveConversationDraft() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        tap(app.descendants(matching: .any)["session-session-long"].firstMatch)
        let field = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(field)
        field.typeText("Keep this draft while changing theme")
        tap(app.buttons["account-menu"])
        selectTheme("Dark", in: app)
        selectTheme("Light", in: app)
        selectTheme("System", in: app)
        tap(app.buttons["settings-workspace"])
        tap(app.buttons["workspace-option-ws-demo"])
        tap(app.buttons["settings-close"])
        XCTAssertEqual(field.value as? String, "Keep this draft while changing theme")
        attach(app, "iPad conversation draft after theme changes")
    }

    @MainActor
    private func selectTheme(_ title: String, in app: XCUIApplication) {
        tap(app.buttons["settings-theme"])
        tap(app.buttons[title].firstMatch)
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", title), object: app.buttons["settings-theme"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"] + arguments
        app.launch()
        tap(app.buttons["sign-in-button"])
        XCTAssertTrue(app.buttons["account-menu"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
