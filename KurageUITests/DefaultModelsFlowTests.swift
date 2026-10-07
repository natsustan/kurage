import XCTest

final class DefaultModelsFlowTests: XCTestCase {
    @MainActor
    func testManageReorderPersistAndChooseAcrossProviders() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "-appTheme", "dark"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-default-models"])
        clearSavedModels(app)
        for id in ["claude-sonnet", "claude-opus", "codex-gpt-5.5", "codex-gpt-5.4-mini"] {
            tap(app.buttons["default-models-add"])
            tap(app.buttons["add-default-model-\(id)"])
        }
        attach(app, "Default Models selected")
        tap(app.buttons["Edit"])
        let rows = app.collectionViews.cells
        let source = rows.containing(.any, identifier: "default-model-codex-gpt-5.5").firstMatch
        let target = rows.containing(.any, identifier: "default-model-claude-sonnet").firstMatch
        XCTAssertTrue(source.exists)
        XCTAssertTrue(target.exists)
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.1)))
        tap(app.buttons["Done"])
        let codex = app.descendants(matching: .any)["default-model-codex-gpt-5.5"].firstMatch
        let sonnet = app.descendants(matching: .any)["default-model-claude-sonnet"].firstMatch
        XCTAssertLessThan(codex.frame.minY, sonnet.frame.minY)
        attach(app, "Default Models reordered")
        app.terminate()
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-default-models"])
        XCTAssertTrue(codex.waitForExistence(timeout: 5))
        XCTAssertLessThan(codex.frame.minY, sonnet.frame.minY)
        tap(app.navigationBars["Default Models"].buttons.element(boundBy: 0))
        tap(app.buttons["settings-close"])
        tap(app.buttons["new-session-local:machine-1:prism"])
        let keyboardTop = visibleKeyboardTop(app)
        tap(app.buttons["run-config-menu"])
        assertPickerAboveKeyboard(app, keyboardTop: keyboardTop)
        let shortcut = app.buttons["model-shortcut-codex-gpt-5.5"]
        tap(shortcut)
        XCTAssertTrue(shortcut.wait(for: \.isSelected, toEqual: true, timeout: 5))
        XCTAssertFalse(app.buttons["All Models"].exists)
        XCTAssertFalse(app.buttons["Manage Default Models"].exists)
        XCTAssertFalse(app.staticTexts["Applies to your next message"].exists)
        let dial = app.otherElements["reasoning-dial"]
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        let panel = app.scrollViews["run-config-scroll"]
        panel.swipeUp()
        dial.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertEqual(dial.value as? String, "Low")
        attach(app, "Compact model picker dark")
        panel.swipeDown()
        tap(app.buttons["model-shortcut-claude-opus"])
        XCTAssertTrue(app.buttons["model-shortcut-claude-opus"].wait(for: \.isSelected, toEqual: true, timeout: 5))
        XCTAssertFalse(dial.exists)
        tap(shortcut)
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        XCTAssertEqual(dial.value as? String, "Low")
        tap(app.buttons["run-config-advanced"])
        XCTAssertTrue(app.navigationBars["Advanced"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["run-config-provider"].exists)
        attach(app, "Title opens existing Advanced")
    }

    @MainActor
    func testFavoritesRememberIndependentReasoningAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "-appTheme", "dark"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-default-models"])
        clearSavedModels(app)
        for id in ["codex-gpt-5.5", "codex-gpt-5.4-mini"] {
            tap(app.buttons["default-models-add"])
            tap(app.buttons["add-default-model-\(id)"])
        }
        tap(app.navigationBars["Default Models"].buttons.element(boundBy: 0))
        tap(app.buttons["settings-close"])
        tap(app.buttons["new-session-local:machine-1:prism"])
        tap(app.buttons["run-config-menu"])
        let full = app.buttons["model-shortcut-codex-gpt-5.5"]
        let mini = app.buttons["model-shortcut-codex-gpt-5.4-mini"]
        let dial = app.otherElements["reasoning-dial"]
        tap(full)
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        XCTAssertEqual(dial.value as? String, "Medium")
        XCTAssertEqual(app.staticTexts["run-config-reasoning-value"].label, "Medium")
        XCTAssertFalse(app.staticTexts["Default"].exists)
        attach(app, "Favorite without memory shows concrete Medium")
        dial.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let fullEffort = dial.value as? String
        XCTAssertNotEqual(fullEffort, "Low")
        tap(mini)
        XCTAssertEqual(app.staticTexts["run-config-reasoning-value"].label, "Low")
        XCTAssertFalse(dial.exists)
        XCTAssertFalse(app.staticTexts["Default"].exists)
        attach(app, "Single supported effort is visible as Low")
        // Advanced and the compact picker show the same single supported value.
        tap(app.buttons["run-config-advanced"])
        tap(app.buttons["run-config-reasoning"])
        tap(app.buttons["Low"])
        tap(app.buttons["run-config-done"])
        tap(app.descendants(matching: .any)["new-session-field"])
        XCTAssertEqual(app.buttons["run-config-menu"].label, "Provider Codex, model gpt-5.4-mini, reasoning Low")
        tap(app.buttons["run-config-menu"])
        tap(full)
        XCTAssertEqual(dial.value as? String, fullEffort)
        tap(mini)
        tap(app.buttons["run-config-close"])
        XCTAssertEqual(app.buttons["run-config-menu"].label, "Provider Codex, model gpt-5.4-mini, reasoning Low")
        app.terminate()
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["new-session-local:machine-1:prism"])
        tap(app.buttons["run-config-menu"])
        tap(full)
        XCTAssertEqual(dial.value as? String, fullEffort)
        tap(mini)
        tap(app.buttons["run-config-close"])
        XCTAssertEqual(app.buttons["run-config-menu"].label, "Provider Codex, model gpt-5.4-mini, reasoning Low")
        attach(app, "Favorites restore independent reasoning")
    }

    @MainActor
    func testRecentModelsLightAndLargeTextPicker() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "-appTheme", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-default-models"])
        clearSavedModels(app)
        attach(app, "Default Models empty large text")
        tap(app.navigationBars["Default Models"].buttons.element(boundBy: 0))
        tap(app.buttons["settings-close"])
        tap(app.buttons["new-session-local:machine-1:prism"])
        let composer = app.descendants(matching: .any)["new-session-field"]
        tap(composer)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let keyboardTop = visibleKeyboardTop(app)
        tap(app.buttons["run-config-menu"])
        assertPickerAboveKeyboard(app, keyboardTop: keyboardTop)
        let codex = app.buttons["model-shortcut-codex-gpt-5.5"]
        tap(codex)
        XCTAssertTrue(codex.wait(for: \.isSelected, toEqual: true, timeout: 5))
        XCTAssertFalse(app.buttons["model-shortcut-claude-opus"].exists)
        XCTAssertFalse(app.buttons["model-shortcut-codex-gpt-5.4-mini"].exists)
        attach(app, "Recent models light large text")
        let panel = app.scrollViews["run-config-scroll"]
        let modelY = codex.frame.minY
        let dial = app.otherElements["reasoning-dial"]
        for _ in 0..<3 {
            panel.swipeUp()
            if dial.isHittable && panel.frame.contains(dial.frame) { break }
        }
        XCTAssertTrue(dial.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertLessThan(codex.frame.minY, modelY)
        XCTAssertTrue(panel.frame.contains(dial.frame))
        XCTAssertLessThanOrEqual(dial.frame.maxY, keyboardTop)
        assertPickerAboveKeyboard(app, keyboardTop: keyboardTop)
        attach(app, "Large text reasoning above keyboard")
        for _ in 0..<3 {
            panel.swipeDown()
            if app.buttons["run-config-close"].isHittable { break }
        }
        tap(app.buttons["run-config-close"])
        XCTAssertTrue(codex.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["new-session-field"].exists)
    }

    @MainActor
    func testCurrentRecentModelKeepsSelectionAndReasoningOnlyEditing() {
        for theme in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["--fixture", "-appTheme", theme]
            app.launch()
            tap(app.buttons["sign-in-button"])
            tap(app.buttons["account-menu"])
            tap(app.buttons["settings-default-models"])
            clearSavedModels(app)
            tap(app.navigationBars["Default Models"].buttons.element(boundBy: 0))
            tap(app.buttons["settings-close"])
            tap(app.descendants(matching: .any)["session-session-long"])
            tap(app.descendants(matching: .any)["follow-up-field"])
            tap(app.buttons["run-config-menu"])
            let current = app.buttons["model-shortcut-codex-gpt-5.5"]
            XCTAssertTrue(current.waitForExistence(timeout: 5))
            XCTAssertTrue(current.isSelected)
            XCTAssertFalse(current.isEnabled)
            XCTAssertFalse(app.buttons["model-shortcut-codex-gpt-5.4-mini"].exists)
            let dial = app.otherElements["reasoning-dial"]
            XCTAssertTrue(dial.waitForExistence(timeout: 5))
            dial.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
            XCTAssertEqual(dial.value as? String, "Low")
            XCTAssertTrue(current.isSelected)
            attach(app, "Current recent model \(theme)")
            app.terminate()
        }
    }

    @MainActor
    func testNoHistoryOffersAdvancedAndShowsExplicitSelection() {
        for theme in ["dark", "light"] {
            let app = XCUIApplication()
            app.launchArguments = ["--fixture", "--fixture-no-model-history", "-appTheme", theme]
            app.launch()
            tap(app.buttons["sign-in-button"])
            tap(app.buttons["account-menu"])
            tap(app.buttons["settings-default-models"])
            clearSavedModels(app)
            tap(app.navigationBars["Default Models"].buttons.element(boundBy: 0))
            tap(app.buttons["settings-close"])
            tap(app.buttons["new-session-local:machine-1:prism"])
            tap(app.buttons["run-config-menu"])
            let choose = app.buttons["run-config-choose-model"]
            XCTAssertTrue(choose.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "model-shortcut-")).firstMatch.exists)
            attach(app, "No model history \(theme)")
            tap(choose)
            XCTAssertTrue(app.navigationBars["Advanced"].waitForExistence(timeout: 5))
            tap(app.buttons["run-config-model"])
            tap(app.buttons["Opus"])
            tap(app.buttons["run-config-done"])
            tap(app.descendants(matching: .any)["new-session-field"])
            tap(app.buttons["run-config-menu"])
            XCTAssertTrue(app.buttons["model-shortcut-claude-opus"].wait(for: \.isSelected, toEqual: true, timeout: 5))
            XCTAssertFalse(choose.exists)
            attach(app, "Explicit model after empty history \(theme)")
            app.terminate()
        }
    }

    @MainActor
    private func visibleKeyboardTop(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> CGFloat {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), file: file, line: line)
        attach(app, "Composer with software keyboard")
        // Keyboard existence alone also passes with an offscreen software keyboard.
        XCTAssertTrue(app.frame.intersects(keyboard.frame), file: file, line: line)
        XCTAssertTrue(keyboard.isHittable, file: file, line: line)
        let inputView = app.otherElements["inputView"].firstMatch
        XCTAssertTrue(inputView.waitForExistence(timeout: 5), file: file, line: line)
        return inputView.frame.minY
    }

    @MainActor
    private func assertPickerAboveKeyboard(_ app: XCUIApplication, keyboardTop: CGFloat,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let panel = app.scrollViews["run-config-scroll"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(app.frame.contains(panel.frame), file: file, line: line)
        XCTAssertLessThanOrEqual(panel.frame.maxY, keyboardTop, file: file, line: line)
    }

    @MainActor
    private func clearSavedModels(_ app: XCUIApplication) {
        for _ in 0..<5 {
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "default-model-")).firstMatch
            guard row.waitForExistence(timeout: 1) else { break }
            row.swipeLeft()
            tap(app.buttons["Delete"].firstMatch)
        }
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        let app = XCUIApplication()
        for _ in 0..<4 {
            if element.waitForExistence(timeout: 1), element.isHittable { break }
            if app.scrollViews["run-config-scroll"].exists { app.scrollViews["run-config-scroll"].swipeUp() }
            else if app.scrollViews["settings-content"].exists { app.scrollViews["settings-content"].swipeUp() }
            else if app.collectionViews.firstMatch.exists { app.collectionViews.firstMatch.swipeUp() }
            else if app.scrollViews.firstMatch.exists { app.scrollViews.firstMatch.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        XCTAssertTrue(element.wait(for: \.isHittable, toEqual: true, timeout: 5))
        element.tap()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
