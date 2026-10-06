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
        openActions(app)
        XCTAssertTrue(actionButton("Create Branch & Commit", app: app).wait(for: \.isEnabled, toEqual: true, timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["quick-actions-panel"].exists)
        XCTAssertFalse(app.staticTexts["Working Directory"].exists)
        XCTAssertFalse(app.staticTexts["Execution"].exists)
        XCTAssertFalse(app.buttons["quick-action-agent"].exists)
        XCTAssertFalse(app.buttons["quick-action-model"].exists)
        XCTAssertFalse(app.buttons["quick-action-reasoning"].exists)
        XCTAssertFalse(app.buttons["quick-action-reset"].exists)
        XCTAssertFalse(app.staticTexts["Review the changes and create a local commit."].exists)
        XCTAssertTrue(actionButton("Review Changes", app: app).exists)
        XCTAssertFalse(actionButton("Commit…", app: app).exists)
        XCTAssertFalse(actionButton("Push", app: app).exists)
        XCTAssertFalse(actionButton("Create PR…", app: app).exists)
        XCTAssertFalse(actionButton("Create Branch", app: app).exists)
        attach(app, "Default branch with changes offers review and branch plus commit")
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
    func testRunningProjectHidesGitActions() {
        let app = launch()
        tap(app.descendants(matching: .any)["session-session-long"].firstMatch)
        openActions(app)
        let blocked = app.buttons["quick-action-blocked"]
        reveal(blocked)
        XCTAssertTrue(blocked.waitForExistence(timeout: 5))
        XCTAssertFalse(actionButton("Commit…", app: app).exists)
        XCTAssertFalse(actionButton("Create Branch", app: app).exists)
        XCTAssertFalse(actionButton("Review Changes", app: app).exists)
        XCTAssertFalse(actionButton("Create PR…", app: app).exists)
        attach(app, "Running project shows its status without inapplicable actions")
        tap(blocked)
        let alert = app.alerts["Quick Actions"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["A session in this project is running. Stop it before starting a Git action."].exists)
        attach(app, "Unavailable actions explain their reason on demand")
        tap(alert.buttons["Cancel"])
        XCTAssertFalse(app.descendants(matching: .any)["session-tab-bar"].exists)
    }

    @MainActor
    func testReviewPushAndPRActionsCreateNamedTaskTabs() {
        let app = launch("unpublished")
        tap(app.descendants(matching: .any)["session-session-pr"].firstMatch)
        for title in ["Review Changes", "Push", "Create PR", "Create Draft PR"] {
            openActions(app)
            XCTAssertFalse(app.descendants(matching: .any)["quick-actions-panel"].exists)
            attach(app, "Quick Actions menu before \(title)")
            if title == "Create PR" || title == "Create Draft PR" {
                tap(actionButton("Create PR…", app: app))
                XCTAssertTrue(actionButton("Regular PR", app: app).exists)
                XCTAssertTrue(actionButton("Draft PR", app: app).exists)
                attach(app, "PR submenu groups regular and draft choices")
                tap(actionButton(title == "Create PR" ? "Regular PR" : "Draft PR", app: app))
            } else {
                tap(actionButton(title, app: app))
            }
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
    func testZeroLineStatsKeepReviewAndPRAvailable() {
        let app = launch("zero-lines")
        tap(app.descendants(matching: .any)["session-session-pr"].firstMatch)
        openActions(app)
        XCTAssertTrue(actionButton("Review Changes", app: app).exists)
        XCTAssertTrue(actionButton("Create PR…", app: app).exists)
        XCTAssertFalse(actionButton("Push", app: app).exists)
        XCTAssertFalse(actionButton("Commit…", app: app).exists)
        attach(app, "Zero line totals preserve review and PR actions")
        tap(actionButton("Create PR…", app: app))
        XCTAssertTrue(actionButton("Regular PR", app: app).exists)
        XCTAssertTrue(actionButton("Draft PR", app: app).exists)
        tap(actionButton("Regular PR", app: app))
        let tab = app.buttons.matching(NSPredicate(format: "label == %@", "Create PR")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        XCTAssertTrue(tab.wait(for: \.isSelected, toEqual: true, timeout: 5))
        let instruction = app.tables["conversation-transcript"].staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Run this Git quick action")).firstMatch
        XCTAssertTrue(instruction.waitForExistence(timeout: 8))
        attach(app, "Unknown branch diff starts a checked PR task")
    }

    @MainActor
    func testCommitChoicesAreGroupedAndKeepBranchCreationInMoreActions() {
        let app = launch("feature-dirty")
        tap(app.descendants(matching: .any)["session-session-pr"].firstMatch)
        for title in ["Commit only", "Commit & Push"] {
            openActions(app)
            XCTAssertTrue(actionButton("Review Changes", app: app).exists)
            XCTAssertTrue(actionButton("Commit…", app: app).exists)
            XCTAssertFalse(actionButton("Push", app: app).exists)
            XCTAssertFalse(actionButton("Create PR…", app: app).exists)
            XCTAssertFalse(actionButton("Create Branch", app: app).exists)
            attach(app, "Working branch with changes groups commit choices")
            tap(actionButton("Commit…", app: app))
            attach(app, "Commit submenu offers local commit or commit and push")
            tap(actionButton(title, app: app))
            let taskTitle = title == "Commit only" ? "Commit" : title
            let tab = app.buttons.matching(NSPredicate(format: "label == %@", taskTitle)).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            XCTAssertTrue(tab.wait(for: \.isSelected, toEqual: true, timeout: 5))
        }
        openActions(app)
        tap(actionButton("More Actions", app: app))
        XCTAssertTrue(actionButton("Create Branch", app: app).exists)
        XCTAssertTrue(actionButton("Refresh Actions", app: app).exists)
        attach(app, "More Actions keeps infrequent branch creation available")
    }

    @MainActor
    func testExistingPRHidesCreationAndGitReadFailureCanBeRetried() {
        var app = launch("existing-pr")
        tap(app.descendants(matching: .any)["session-session-pr"].firstMatch)
        openActions(app)
        XCTAssertTrue(actionButton("Review Changes", app: app).exists)
        XCTAssertTrue(actionButton("Push", app: app).exists)
        XCTAssertFalse(actionButton("Create PR…", app: app).exists)
        attach(app, "Existing PR only offers review and push")
        app.terminate()
        app = launch("unpublished", extraArguments: ["--fixture-project-git-failure"])
        tap(app.descendants(matching: .any)["session-session-pr"].firstMatch)
        openActions(app)
        XCTAssertFalse(actionButton("Push", app: app).exists)
        XCTAssertFalse(actionButton("Create PR…", app: app).exists)
        tap(actionButton("Retry Git Status", app: app))
        openActions(app)
        XCTAssertTrue(actionButton("Push", app: app).exists)
        XCTAssertTrue(actionButton("Create PR…", app: app).exists)
        attach(app, "Git status retry restores matching actions")
    }

    @MainActor
    private func openActions(_ app: XCUIApplication) {
        let button = app.buttons["quick-actions-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ready"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        tap(button)
    }

    @MainActor
    private func actionButton(_ title: String, app: XCUIApplication) -> XCUIElement {
        // Native Menu actions expose their title, but discard identifiers from ForEach rows.
        app.collectionViews.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    @MainActor
    private func launch(_ scenario: String = "main-dirty", extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-git-\(scenario)"] + extraArguments
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
