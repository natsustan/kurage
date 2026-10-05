import XCTest

final class QuickActionsFlowTests: XCTestCase {
    @MainActor
    func testActionCreatesNamedTabPreservesDraftAndPersistsIndependentConfiguration() {
        let app = launch()
        tap(app.descendants(matching: .any)["session-session-pr"].firstMatch)
        let field = app.descendants(matching: .any)["follow-up-field"].firstMatch
        tap(field)
        field.typeText("Keep my main draft")
        tap(app.buttons["quick-actions-button"])
        tap(app.buttons["quick-action-reset"])
        choose("quick-action-agent", value: "Codex", app: app)
        choose("quick-action-model", value: "gpt-5.4-mini", app: app)
        choose("quick-action-reasoning", value: "Low", app: app)
        attach(app, "Quick Actions with an independent model")
        tap(app.buttons["quick-action-create-branch-and-commit"])
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
        let blocked = app.descendants(matching: .any)["quick-action-blocked"].firstMatch
        reveal(blocked)
        XCTAssertTrue(blocked.waitForExistence(timeout: 5))
        attach(app, "Running project explains why actions are disabled")
        let commit = app.buttons["quick-action-commit"]
        reveal(commit)
        XCTAssertTrue(commit.waitForExistence(timeout: 5))
        XCTAssertFalse(commit.isEnabled)
        reveal(app.buttons["quick-action-create-branch"])
        XCTAssertFalse(app.buttons["quick-action-create-branch"].isEnabled)
        attach(app, "Running project disables Git actions")
        tap(app.buttons["quick-actions-close"])
        XCTAssertFalse(app.descendants(matching: .any)["session-tab-bar"].exists)
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
