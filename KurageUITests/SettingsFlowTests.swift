import XCTest
import UIKit

final class SettingsFlowTests: XCTestCase {
    @MainActor
    func testSettingsKeepsReferenceHeightAndCachedWorkspacesRefreshQuietly() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        let app = launch(arguments: ["--fixture-settings", "--fixture-slow-workspaces"])
        tap(app.buttons["account-menu"])
        let settings = app.descendants(matching: .any)["settings-screen"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let openingFrame = settings.frame
        XCTAssertGreaterThan(openingFrame.minY, app.frame.height * 0.08)
        XCTAssertLessThan(openingFrame.minY, app.frame.height * 0.18)
        XCTAssertGreaterThan(openingFrame.height, app.frame.height * 0.81)
        XCTAssertLessThan(openingFrame.height, app.frame.height * 0.9)
        XCTAssertFalse(app.buttons["Sheet Grabber"].exists)
        attach(app, "Settings opens at the fixed reference height")

        tap(app.buttons["settings-workspace"])
        let picker = app.descendants(matching: .any)["workspace-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["workspace-option-ws-demo"].isSelected)
        XCTAssertTrue(app.buttons["workspace-option-ws-studio"].isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["workspace-loading"].exists)
        XCTAssertFalse(app.staticTexts["Refreshing workspaces…"].exists)
        attach(app, "Cached workspaces refresh without a footer")

        picker.swipeUp()
        XCTAssertEqual(settings.frame.minY, openingFrame.minY, accuracy: 2)
        XCTAssertEqual(settings.frame.height, openingFrame.height, accuracy: 2)

        picker.swipeDown()
        XCTAssertTrue(picker.exists)
        XCTAssertTrue(app.buttons["workspace-option-ws-demo"].isSelected)
        XCTAssertTrue(app.buttons["workspace-option-ws-studio"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workspace-loading"].exists)
        attach(app, "Native workspace pull to refresh preserves rows")

        tap(app.buttons["workspace-option-ws-demo"])
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings-workspace"].value as? String, "Demo")
        tap(app.buttons["settings-close"])
        tap(app.buttons["account-menu"])
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertEqual(settings.frame.minY, openingFrame.minY, accuracy: 2)
        XCTAssertEqual(settings.frame.height, openingFrame.height, accuracy: 2)
        attach(app, "Settings reopens at the same fixed height")
    }

    @MainActor
    func testThemeChangesApplyToSettingsAndPersistAfterRelaunch() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "Background sampling uses the iPhone sheet inset; iPad theme changes have a separate test.")
        let app = launch(arguments: ["--fixture-settings"])
        tap(app.buttons["account-menu"])
        selectTheme("System", in: app)
        let systemBrightness = try settingsBackgroundBrightness(in: app)
        attach(app, "Settings follows system theme")
        selectTheme("Night", in: app)
        XCTAssertLessThan(try settingsBackgroundBrightness(in: app), 0.5)
        attach(app, "Settings with Night appearance")
        tap(app.buttons["settings-workspace"])
        XCTAssertTrue(app.descendants(matching: .any)["workspace-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Workspace"].exists)
        attach(app, "Workspace page inherits Night appearance")
        back(from: "Workspace", in: app)
        tap(app.buttons["settings-about"])
        XCTAssertTrue(app.navigationBars["About Kurage"].waitForExistence(timeout: 5))
        attach(app, "About inherits Night appearance")
        tap(app.navigationBars["About Kurage"].buttons.element(boundBy: 0))
        selectTheme("Day", in: app)
        XCTAssertGreaterThan(try settingsBackgroundBrightness(in: app), 0.7)
        attach(app, "Settings with Day appearance")
        tap(app.buttons["settings-close"])
        attach(app, "Session list inherits Day appearance")

        app.terminate()
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["account-menu"])
        XCTAssertEqual(app.buttons["settings-theme"].value as? String, "Day")
        XCTAssertGreaterThan(try settingsBackgroundBrightness(in: app), 0.7)
        attach(app, "Day appearance restored after relaunch")
        selectTheme("System", in: app)
        XCTAssertEqual(try settingsBackgroundBrightness(in: app), systemBrightness, accuracy: 0.1)
        attach(app, "Settings returns to system theme")
    }

    @MainActor
    private func settingsBackgroundBrightness(in app: XCUIApplication) throws -> Double {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        // The sheet's left inset stays clear of cards at every text size and scroll position.
        let settings = app.descendants(matching: .any)["settings-screen"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let scaleX = CGFloat(image.width) / app.frame.width
        let scaleY = CGFloat(image.height) / app.frame.height
        let point = CGRect(x: (settings.frame.minX + 8 - app.frame.minX) * scaleX,
                           y: (settings.frame.midY - app.frame.minY) * scaleY, width: 1, height: 1)
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
        let picker = app.descendants(matching: .any)["workspace-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let demo = app.buttons["workspace-option-ws-demo"]
        XCTAssertTrue(demo.isSelected)
        XCTAssertTrue(app.navigationBars["Workspace"].exists)
        XCTAssertFalse(app.buttons["settings-close"].exists)
        attach(app, "Workspace secondary page")
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
        XCTAssertTrue(app.descendants(matching: .any)["workspace-picker"].waitForNonExistence(timeout: 5))
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
        back(from: "Workspace", in: app)
        XCTAssertTrue(app.buttons["settings-workspace"].exists)
    }

    @MainActor
    func testLongWorkspaceListScrollsAndSelectsLastItem() {
        let app = launch(arguments: ["--fixture-many-workspaces"])
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-workspace"])
        let picker = app.descendants(matching: .any)["workspace-picker"]
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
    func testIPadSettingsPreservesReadStateAndDraft() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        let row = app.descendants(matching: .any)["session-session-long"].firstMatch
        tap(row)
        let read = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Idle, Read"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [read], timeout: 5), .completed)
        let field = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(field)
        field.typeText("Keep this draft while settings is open")
        tap(app.buttons["account-menu"])
        XCTAssertEqual(row.value as? String, "Idle, Read")
        attach(app, "iPad settings preserves the existing read receipt")
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
        selectTheme("Night", in: app)
        selectTheme("Day", in: app)
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
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
        let value = title == "Day" ? "light" : title == "Night" ? "dark" : "system"
        let option = app.buttons["appearance-theme-\(value)"]
        tap(option)
        XCTAssertTrue(option.wait(for: \.isSelected, toEqual: true, timeout: 5))
        attach(app, "Appearance selects \(title)")
        back(from: "Appearance", in: app)
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", title), object: app.buttons["settings-theme"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    @MainActor
    func testAccentAndHapticsPersistAfterRelaunch() throws {
        let app = launch(arguments: ["--fixture-settings"])
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-theme"])
        tap(app.buttons["appearance-accent-blue"])
        XCTAssertTrue(app.buttons["appearance-accent-blue"].wait(for: \.isSelected, toEqual: true, timeout: 5))
        XCTAssertFalse(app.buttons["appearance-accent-black"].isSelected)
        attach(app, "Appearance with Blue accent")
        back(from: "Appearance", in: app)

        tap(app.buttons["settings-haptics"])
        XCTAssertTrue(app.navigationBars["Haptics"].waitForExistence(timeout: 5))
        let toggle = app.switches["haptics-toggle"]
        setHaptics(true, toggle: toggle)
        XCTAssertGreaterThan(try bluePixelFraction(in: toggle.screenshot().image), 0.02)
        XCTAssertLessThan(try bluePixelFraction(in: app.navigationBars["Haptics"].buttons.firstMatch.screenshot().image), 0.02)
        attach(app, "Haptics Feedback with Blue accent")
        setHaptics(false, toggle: toggle)
        attach(app, "Haptics Feedback turned off")
        back(from: "Haptics", in: app)
        XCTAssertEqual(app.buttons["settings-haptics"].value as? String, "Off")
        tap(app.buttons["settings-close"])

        app.terminate()
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["account-menu"])
        XCTAssertEqual(app.buttons["settings-haptics"].value as? String, "Off")
        tap(app.buttons["settings-theme"])
        XCTAssertTrue(app.buttons["appearance-accent-blue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appearance-accent-blue"].isSelected)
        tap(app.buttons["appearance-accent-black"])
        XCTAssertTrue(app.buttons["appearance-accent-black"].wait(for: \.isSelected, toEqual: true, timeout: 5))
        attach(app, "Appearance restored and Black accent selected")
        back(from: "Appearance", in: app)
        tap(app.buttons["settings-haptics"])
        setHaptics(true, toggle: toggle)
        XCTAssertLessThan(try bluePixelFraction(in: toggle.screenshot().image), 0.02)
        attach(app, "Haptics Feedback with Black accent")
        back(from: "Haptics", in: app)
        XCTAssertEqual(app.buttons["settings-haptics"].value as? String, "On")
    }

    @MainActor
    func testAccentColorsComposerAndUserBubblesWhileSystemButtonsStayMonochrome() throws {
        let app = launch(arguments: ["--fixture-settings"])
        for theme in ["Day", "Night"] {
            for accent in ["blue", "black"] {
                tap(app.buttons["account-menu"])
                selectTheme(theme, in: app)
                tap(app.buttons["settings-theme"])
                let option = app.buttons["appearance-accent-\(accent)"]
                tap(option)
                XCTAssertTrue(option.wait(for: \.isSelected, toEqual: true, timeout: 5))
                back(from: "Appearance", in: app)
                tap(app.buttons["settings-close"])
                tap(app.descendants(matching: .any)["session-session-tests"])

                let bubble = app.descendants(matching: .any)["Run the tests again"].firstMatch
                XCTAssertTrue(bubble.waitForExistence(timeout: 5))
                XCTAssertTrue(bubble.wait(for: \.isHittable, toEqual: true, timeout: 5))
                let backButton = app.navigationBars.buttons.firstMatch
                let attachmentButton = app.buttons["add-attachment"]
                let optionsButton = app.buttons["session-options"]
                for button in [backButton, attachmentButton, optionsButton] {
                    XCTAssertTrue(button.waitForExistence(timeout: 5))
                    XCTAssertLessThan(try bluePixelFraction(in: button.screenshot().image), 0.02)
                }
                let stopButton = app.buttons["pause-session"]
                if stopButton.exists {
                    XCTAssertLessThan(try bluePixelFraction(in: stopButton.screenshot().image), 0.02)
                }
                let field = app.descendants(matching: .any)["follow-up-field"]
                tap(field)
                field.typeText("Accent preview")
                let send = app.buttons["send-follow-up"]
                XCTAssertTrue(send.wait(for: \.isEnabled, toEqual: true, timeout: 5))
                if accent == "blue" {
                    XCTAssertGreaterThan(try bluePixelFraction(in: send.screenshot().image), 0.02)
                    XCTAssertGreaterThan(try bluePixelFraction(in: bubble.screenshot().image), 0.6)
                } else {
                    XCTAssertLessThan(try bluePixelFraction(in: send.screenshot().image), 0.02)
                    XCTAssertLessThan(try bluePixelFraction(in: bubble.screenshot().image), 0.02)
                }
                attach(app, "\(theme) with \(accent) composer and user bubble")
                tap(backButton)
                XCTAssertTrue(app.buttons["account-menu"].waitForExistence(timeout: 5))
            }
        }
        tap(app.buttons["account-menu"])
        selectTheme("System", in: app)
    }

    private func bluePixelFraction(in image: UIImage) throws -> Double {
        let source = try XCTUnwrap(image.cgImage)
        let width = min(source.width, 128)
        let height = max(1, Int(Double(source.height) * Double(width) / Double(source.width)))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var bluePixels = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            if blue > red + 12 && blue > green + 4 { bluePixels += 1 }
        }
        return Double(bluePixels) / Double(width * height)
    }

    @MainActor
    private func setHaptics(_ enabled: Bool, toggle: XCUIElement) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let value = enabled ? "1" : "0"
        if toggle.value as? String != value {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    @MainActor
    private func back(from title: String, in app: XCUIApplication) {
        tap(app.navigationBars[title].buttons.firstMatch)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
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
        let content = XCUIApplication().scrollViews["settings-content"]
        if content.exists {
            for _ in 0..<5 {
                if element.isHittable { break }
                content.swipeUp()
            }
        }
        element.tap()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
