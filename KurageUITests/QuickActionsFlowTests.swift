import XCTest

final class QuickActionsFlowTests: XCTestCase {
    @MainActor
    func testActionCreatesNamedTabPreservesDraftAndPersistsIndependentConfiguration() {
        let app = launch()
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-quick-actions"])
        tap(app.buttons["quick-action-reset"])
        choose("quick-action-agent", value: "Codex", app: app)
        choose("quick-action-model", value: "gpt-5.4-mini", app: app)
        choose("quick-action-reasoning", value: "Low", app: app)
        attach(app, "Settings configures the independent task model")
        tap(app.navigationBars.buttons.firstMatch)
        tap(app.buttons["settings-close"])
        tap(app.descendants(matching: .any)["session-session-pr"].firstMatch)
        let field = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(field)
        field.typeText("Keep my main draft")
        tap(app.buttons["quick-actions-button"])
        XCTAssertTrue(actionButton("Commit", app: app).wait(for: \.isEnabled, toEqual: true, timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["quick-actions-panel"].exists)
        XCTAssertFalse(app.staticTexts["Working Directory"].exists)
        XCTAssertFalse(app.staticTexts["Execution"].exists)
        XCTAssertFalse(app.buttons["quick-action-agent"].exists)
        XCTAssertFalse(app.buttons["quick-action-model"].exists)
        XCTAssertFalse(app.buttons["quick-action-reasoning"].exists)
        XCTAssertFalse(app.buttons["quick-action-reset"].exists)
        XCTAssertFalse(app.staticTexts["Review the changes and create a local commit."].exists)
        XCTAssertTrue(actionButton("Review Changes", app: app).exists)
        XCTAssertTrue(actionButton("Create PR", app: app).exists)
        XCTAssertTrue(actionButton("Create Draft PR", app: app).exists)
        attach(app, "Lightning button opens the six-action menu")
        tap(actionButton("Create Branch & Commit", app: app))
        XCTAssertTrue(app.descendants(matching: .any)["quick-actions-panel"].waitForNonExistence(timeout: 5))
        let taskTab = app.buttons.matching(NSPredicate(format: "label == %@", "Create Branch & Commit")).firstMatch
        XCTAssertTrue(taskTab.waitForExistence(timeout: 5))
        XCTAssertTrue(taskTab.wait(for: \.isSelected, toEqual: true, timeout: 5))
        let taskMessage = app.tables["conversation-transcript"].staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Run this Git quick action")).firstMatch
        XCTAssertTrue(taskMessage.waitForExistence(timeout: 8))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        attach(app, "Named task tab with its first instruction")
        tap(app.buttons["session-tab-session-pr"])
        XCTAssertEqual(field.value as? String, "Keep my main draft")
        XCTAssertFalse(app.tables["conversation-transcript"].staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Run this Git quick action")).firstMatch.exists)
        attach(app, "Main tab preserves its draft")
        tap(app.navigationBars.buttons.firstMatch)
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-quick-actions"])
        XCTAssertTrue(app.buttons["quick-action-model"].waitForExistence(timeout: 5))
        waitForLabel("gpt-5.4-mini", on: app.buttons["quick-action-model"])
        waitForLabel("Low", on: app.buttons["quick-action-reasoning"])
        attach(app, "Settings shows saved Quick Actions defaults")
        app.terminate()
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["account-menu"])
        tap(app.buttons["settings-quick-actions"])
        waitForLabel("gpt-5.4-mini", on: app.buttons["quick-action-model"])
        waitForLabel("Low", on: app.buttons["quick-action-reasoning"])
        attach(app, "Quick Actions defaults persist after relaunch")
        tap(app.buttons["quick-action-reset"])
    }

    @MainActor
    func testRunningProjectDisablesGitActions() {
        let app = launch()
        tap(app.descendants(matching: .any)["session-session-long"].firstMatch)
        tap(app.buttons["quick-actions-button"])
        let blocked = app.buttons["quick-action-blocked"]
        reveal(blocked)
        XCTAssertTrue(blocked.waitForExistence(timeout: 5))
        let commit = actionButton("Commit", app: app)
        reveal(commit)
        XCTAssertTrue(commit.waitForExistence(timeout: 5))
        XCTAssertFalse(commit.isEnabled)
        reveal(actionButton("Create Branch", app: app))
        XCTAssertFalse(actionButton("Create Branch", app: app).isEnabled)
        XCTAssertFalse(actionButton("Review Changes", app: app).isEnabled)
        XCTAssertFalse(actionButton("Create PR", app: app).isEnabled)
        attach(app, "Running project disables Git actions")
        tap(blocked)
        let alert = app.alerts["Quick Actions"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["A session in this project is running. Stop it before starting a Git action."].exists)
        attach(app, "Unavailable actions explain their reason on demand")
        tap(alert.buttons["Cancel"])
        XCTAssertFalse(app.descendants(matching: .any)["session-tab-bar"].exists)
    }

    @MainActor
    func testReviewAndPRActionsCreateNamedTaskTabs() {
        let app = launch()
        tap(app.descendants(matching: .any)["session-session-pr"].firstMatch)
        for title in ["Review Changes", "Create PR", "Create Draft PR"] {
            tap(app.buttons["quick-actions-button"])
            XCTAssertFalse(app.descendants(matching: .any)["quick-actions-panel"].exists)
            attach(app, "Quick Actions menu before \(title)")
            tap(actionButton(title, app: app))
            let tab = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            XCTAssertTrue(tab.wait(for: \.isSelected, toEqual: true, timeout: 5))
            let instruction = app.tables["conversation-transcript"].staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Run this Git quick action")).firstMatch
            XCTAssertTrue(instruction.waitForExistence(timeout: 8))
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            attach(app, "\(title) task keeps its instruction")
        }
    }

    @MainActor
    private func actionButton(_ title: String, app: XCUIApplication) -> XCUIElement {
        // Native Menu actions expose their title, but discard identifiers from ForEach rows.
        app.collectionViews.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        XCTAssertTrue(app.buttons["account-menu"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func choose(_ identifier: String, value: String, app: XCUIApplication) {
        tap(app.buttons[identifier])
        tap(app.buttons[value].firstMatch)
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        reveal(element)
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        XCTAssertTrue(element.wait(for: \.isHittable, toEqual: true, timeout: 5))
        element.tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement) {
        let app = XCUIApplication()
        let container = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews["settings-content"]
        guard container.exists else { return }
        for _ in 0..<5 {
            if element.waitForExistence(timeout: 1), element.isHittable { return }
            if element.exists, element.frame.midY < container.frame.midY { container.swipeDown() }
            else { container.swipeUp() }
        }
    }

    @MainActor
    private func waitForLabel(_ value: String, on element: XCUIElement) {
        reveal(element)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
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
