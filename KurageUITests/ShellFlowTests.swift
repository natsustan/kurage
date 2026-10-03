import XCTest

final class ShellFlowTests: XCTestCase {
    @MainActor
    func testSkillMentionLoadingMenuKeepsFullWidth() {
        verifyMentionLoadingMenu(trigger: "$", alternate: "@")
    }

    @MainActor
    func testCombinedMentionLoadingMenuKeepsFullWidth() {
        verifyMentionLoadingMenu(trigger: "@", alternate: "$")
    }

    @MainActor
    private func verifyMentionLoadingMenu(trigger: String, alternate: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-slow-mentions"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        let field = app.descendants(matching: .any)["follow-up-field"]
        tap(field)
        field.typeText(trigger)
        let menu = app.scrollViews["mention-suggestions"]
        let composer = app.otherElements["follow-up-composer"]
        let loading = app.staticTexts["Loading suggestions"]
        XCTAssertTrue(loading.waitForExistence(timeout: 2))
        let loadingWidth = menu.frame.width
        XCTAssertEqual(loadingWidth, composer.frame.width, accuracy: 1)
        XCTAssertLessThanOrEqual(menu.frame.maxY, composer.frame.minY)
        XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertLessThanOrEqual(app.buttons["send-follow-up"].frame.maxY, app.keyboards.firstMatch.frame.minY)
        attachScreen(app, name: "\(trigger) loading suggestions full width")

        XCTAssertTrue(app.buttons["mention-skill-review-and-simplify-changes"].waitForExistence(timeout: 10))
        XCTAssertTrue(loading.waitForNonExistence(timeout: 3))
        XCTAssertEqual(menu.frame.width, loadingWidth, accuracy: 1)
        XCTAssertEqual(menu.frame.width, composer.frame.width, accuracy: 1)
        attachScreen(app, name: "\(trigger) loaded suggestions full width")

        field.typeText(XCUIKeyboardKey.delete.rawValue + alternate)
        XCTAssertTrue(app.buttons["mention-skill-review-and-simplify-changes"].waitForExistence(timeout: 2))
        XCTAssertFalse(loading.exists)
        XCTAssertEqual(menu.frame.width, loadingWidth, accuracy: 1)
        if alternate == "@" {
            XCTAssertTrue(app.buttons["mention-session-session-tests"].exists)
        }
        attachScreen(app, name: "\(alternate) cached suggestions after trigger switch")
    }

    @MainActor
    func testLongMentionMenusStayAboveKeyboard() {
        verifyLongMentionMenu(newSession: false)
    }

    @MainActor
    func testNewSessionLongMentionMenusStayAboveKeyboard() {
        verifyLongMentionMenu(newSession: true)
    }

    @MainActor
    private func verifyLongMentionMenu(newSession: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        if newSession {
            tap(app.buttons["new-session-local:machine-1:prism"])
        } else {
            tap(app.descendants(matching: .any)["session-session-long"])
        }
        let field = app.descendants(matching: .any)[newSession ? "new-session-field" : "follow-up-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        tap(field)
        field.typeText("$")
        let menu = app.scrollViews["mention-suggestions"]
        XCTAssertTrue(app.buttons["mention-skill-review-and-simplify-changes"].waitForExistence(timeout: 5))
        assertMentionMenuGeometry(app, field: field, menu: menu, newSession: newSession)
        attachScreen(app, name: "Long skills menu top \(newSession ? "new" : "existing")")
        let first = app.buttons["mention-skill-review-and-simplify-changes"]
        XCTAssertTrue(first.isHittable)
        tap(first)
        XCTAssertTrue((field.value as? String)?.contains("$review-and-simplify-changes") == true)
        field.typeText(" $")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let last = app.buttons["mention-skill-sample-skill-12"]
        for _ in 0..<10 {
            if last.isHittable && last.frame.maxY <= menu.frame.maxY { break }
            menu.swipeUp()
        }
        XCTAssertTrue(last.isHittable)
        assertMentionMenuGeometry(app, field: field, menu: menu, newSession: newSession)
        attachScreen(app, name: "Long skills menu bottom \(newSession ? "new" : "existing")")
        tap(last)
        field.typeText(" @")
        XCTAssertTrue(app.buttons[newSession ? "mention-session-session-pr" : "mention-session-session-tests"].waitForExistence(timeout: 5))
        assertMentionMenuGeometry(app, field: field, menu: menu, newSession: newSession)
        attachScreen(app, name: "Combined mentions menu \(newSession ? "new" : "existing")")
        for _ in 0..<10 {
            if last.isHittable && last.frame.maxY <= menu.frame.maxY { break }
            menu.swipeUp()
        }
        XCTAssertTrue(last.isHittable)
        assertMentionMenuGeometry(app, field: field, menu: menu, newSession: newSession)
        attachScreen(app, name: "Combined mentions bottom \(newSession ? "new" : "existing")")
    }

    @MainActor
    private func assertMentionMenuGeometry(_ app: XCUIApplication, field: XCUIElement,
                                           menu: XCUIElement, newSession: Bool,
                                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(menu.waitForExistence(timeout: 5), file: file, line: line)
        let send = app.buttons[newSession ? "new-session-send" : "send-follow-up"]
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(field.isHittable, file: file, line: line)
        XCTAssertTrue(send.isHittable, file: file, line: line)
        XCTAssertGreaterThan(menu.frame.height, 0, file: file, line: line)
        let row = menu.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
                                                     "mention-skill-", "mention-session-")).firstMatch
        XCTAssertGreaterThan(row.frame.height, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(menu.frame.height, row.frame.height * 3 + 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(menu.frame.maxY, field.frame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(send.frame.maxY, keyboard.frame.minY, file: file, line: line)
    }

    @MainActor
    func testSelectedMentionsDeleteAsWholeTokens() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        let field = app.descendants(matching: .any)["follow-up-field"]
        tap(field)
        for (query, candidate) in [("$review", "mention-skill-review-and-simplify-changes"),
                                    ("@fix", "mention-session-session-tests")] {
            field.typeText(query)
            let suggestion = app.buttons[candidate]
            XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
            tap(suggestion)
            field.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue)
            let empty = NSPredicate(format: "value == %@ OR value == %@", "", "Send a follow-up")
            expectation(for: empty, evaluatedWith: field)
            waitForExpectations(timeout: 3)
            XCTAssertFalse(app.buttons["send-follow-up"].isEnabled)
        }
        field.typeText("Still editable")
        XCTAssertEqual(field.value as? String, "Still editable")
    }

    @MainActor
    func testComposerSkillAndCurrentProjectSessionMentions() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        let field = app.descendants(matching: .any)["follow-up-field"]
        tap(field)
        field.typeText("$review")
        let skill = app.buttons["mention-skill-review-and-simplify-changes"]
        XCTAssertTrue(skill.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mention-session-session-pr"].exists)
        XCTAssertFalse(app.buttons["mention-skill-swiftui-specialist"].exists)
        attachScreen(app, name: "Skill mention candidates")
        tap(skill)
        XCTAssertTrue((field.value as? String)?.contains("$review-and-simplify-changes") == true)

        field.typeText(" @fix")
        let session = app.buttons["mention-session-session-tests"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        attachScreen(app, name: "Session mention candidates")
        tap(session)
        XCTAssertTrue((field.value as? String)?.contains("@fix-flaky-tests") == true)
        attachScreen(app, name: "Selected skill and session in composer")
        tap(app.buttons["send-follow-up"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND NOT label CONTAINS %@", "fix flaky tests", "session://"))
            .firstMatch.waitForExistence(timeout: 5))
        attachScreen(app, name: "Skill and session in user bubble")
    }

    @MainActor
    func testNewSessionComposerOffersProjectMentions() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["new-session-local:machine-1:prism"])
        let field = app.descendants(matching: .any)["new-session-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        tap(field)
        field.typeText("$review")
        let skill = app.buttons["mention-skill-review-and-simplify-changes"]
        XCTAssertTrue(skill.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mention-skill-swiftui-specialist"].exists)
        tap(skill)
        field.typeText(" @review")
        let session = app.buttons["mention-session-session-pr"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["mention-session-session-tests"].exists)
        tap(session)
        XCTAssertTrue((field.value as? String)?.contains("@review-the-PR") == true)
        attachScreen(app, name: "New session selected mentions")
    }

    @MainActor
    func testConversationRetryDoesNotShowEmptyState() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-search-failure", "--fixture-slow-conversation"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        let emptyState = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: app.staticTexts["No messages yet"]
        )
        emptyState.isInverted = true
        wait(for: [emptyState], timeout: 6)
        XCTAssertTrue(app.staticTexts["Latest reply in long conversation"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testUnreadSessionClearsAfterOpening() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        let row = app.descendants(matching: .any)["session-session-long"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "Idle, Unread")
        attachScreen(app, name: "Unread session")
        tap(row)
        XCTAssertTrue(app.descendants(matching: .any)["follow-up-field"].waitForExistence(timeout: 5))
        tap(app.navigationBars.buttons.element(boundBy: 0))
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let read = NSPredicate(format: "value == %@", "Idle, Read")
        expectation(for: read, evaluatedWith: row)
        waitForExpectations(timeout: 5)
        attachScreen(app, name: "Read session")
    }

    @MainActor
    func testSubtasksOpenReadOnlyAndReturnToParentDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-subtasks"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        XCTAssertFalse(app.descendants(matching: .any)["session-review-reuse"].exists)
        tap(app.descendants(matching: .any)["session-session-long"])
        let field = app.descendants(matching: .any)["follow-up-field"]
        tap(field)
        field.typeText("Keep parent draft")
        let subtasks = app.buttons["conversation-subtasks"]
        XCTAssertTrue(subtasks.waitForExistence(timeout: 5))
        XCTAssertTrue(subtasks.label.contains("2 agents"))
        XCTAssertTrue(app.buttons["turn-changes-toggle-long-agent-20"].isHittable)
        attachScreen(app, name: "Parent subtask summary")
        tap(subtasks)
        let reuse = app.buttons["subtask-review-reuse"]
        XCTAssertTrue(reuse.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["subtask-review-quality"].exists)
        attachScreen(app, name: "Subtasks with states")
        tap(reuse)
        XCTAssertTrue(app.staticTexts["Reuse review finished."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Completed"].exists)
        XCTAssertTrue(app.staticTexts["Interact with subagent reuse_review"].waitForExistence(timeout: 5))
        let child = app.descendants(matching: .any)["subtask-transcript"]
        XCTAssertTrue(child.waitForExistence(timeout: 5))
        XCTAssertFalse(child.buttons["send-follow-up"].exists)
        XCTAssertFalse(child.descendants(matching: .any)["follow-up-field"].exists)
        attachScreen(app, name: "Read-only subtask transcript")
        tap(app.buttons["close-subtask"])
        XCTAssertTrue(subtasks.waitForExistence(timeout: 5))
        tap(subtasks)
        tap(app.buttons["subtask-review-quality"])
        XCTAssertTrue(app.staticTexts["Checking state isolation."].waitForExistence(timeout: 5))
        XCTAssertFalse(child.buttons["pause-session"].exists)
        tap(app.buttons["close-subtask"])
        XCTAssertEqual(field.value as? String, "Keep parent draft")
        XCTAssertTrue(subtasks.exists)
        attachScreen(app, name: "Parent draft after subtask")
    }

    @MainActor
    func testRecordedFileChangesHUDAndDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        let hud = app.buttons["conversation-changes-hud"]
        XCTAssertTrue(hud.waitForExistence(timeout: 5))
        XCTAssertTrue(hud.label.contains("2 files changed"))
        let turnToggle = app.buttons["turn-changes-toggle-long-agent-20"]
        XCTAssertTrue(turnToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(turnToggle.value as? String, "Expanded")
        tap(turnToggle)
        XCTAssertEqual(turnToggle.value as? String, "Collapsed")
        tap(turnToggle)
        let inlineFile = app.buttons["turn-changed-file-KurageApp/Features/Conversation/ConversationView.swift"]
        XCTAssertTrue(inlineFile.waitForExistence(timeout: 5))
        attachScreen(app, name: "This turn inline file changes")
        tap(inlineFile)
        XCTAssertTrue(app.buttons["file-changes-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["file-changes-title"].label, "This turn")
        tap(app.buttons["close-file-changes"])
        let field = app.descendants(matching: .any)["follow-up-field"]
        tap(field)
        field.typeText("Keep this draft")
        XCTAssertLessThan(hud.frame.maxY, field.frame.minY)
        let keyboardCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        keyboardCapture.name = "Changes HUD above composer"
        keyboardCapture.lifetime = .keepAlways
        add(keyboardCapture)
        tap(hud)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let scope = app.buttons["file-changes-title"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertEqual(scope.label, "All turns")
        XCTAssertTrue(app.staticTexts["Turn 20"].exists)
        tap(scope)
        tap(app.buttons["Last turn"])
        XCTAssertTrue(scope.wait(for: \.label, toEqual: "Last turn", timeout: 5))
        tap(scope)
        tap(app.buttons["All turns"])
        XCTAssertTrue(scope.wait(for: \.label, toEqual: "All turns", timeout: 5))
        let resize = app.buttons["resize-file-changes"]
        let expandedHeaderY = scope.frame.minY
        tap(resize)
        XCTAssertTrue(resize.wait(for: \.label, toEqual: "Expand drawer", timeout: 5))
        XCTAssertGreaterThan(scope.frame.minY, expandedHeaderY)
        attachScreen(app, name: "Compact file changes drawer")
        tap(resize)
        XCTAssertTrue(resize.wait(for: \.label, toEqual: "Collapse drawer", timeout: 5))
        let file = app.descendants(matching: .any)["changed-file-KurageApp/Features/Conversation/ConversationView.swift"]
        attachScreen(app, name: "File changes before expanding")
        if !file.isHittable {
            app.scrollViews["file-changes-list"].swipeUp()
        }
        XCTAssertTrue(file.isHittable)
        XCTAssertEqual(file.value as? String, "Collapsed")
        tap(file)
        XCTAssertEqual(file.value as? String, "Expanded")
        let changedLine = app.staticTexts["    let showsChanges = true"]
        XCTAssertTrue(app.descendants(matching: .any)["historical-file-diff-KurageApp/Features/Conversation/ConversationView.swift"].waitForExistence(timeout: 5))
        XCTAssertTrue(changedLine.waitForExistence(timeout: 5))
        for _ in 0..<4 where !changedLine.isHittable {
            app.scrollViews["file-changes-list"].swipeUp()
        }
        XCTAssertTrue(changedLine.isHittable)
        let diffCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        diffCapture.name = "Recorded code difference"
        diffCapture.lifetime = .keepAlways
        add(diffCapture)
        let hunk = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'file-diff-hunk-'")).firstMatch
        XCTAssertTrue(hunk.exists)
        for _ in 0..<4 where !hunk.isHittable {
            app.scrollViews["file-changes-list"].swipeDown()
        }
        let hunkTitle = hunk.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Lines '")).firstMatch
        XCTAssertTrue(hunkTitle.exists)
        let expandedHunkFrame = hunk.frame
        let expandedTitleFrame = hunkTitle.frame
        tap(hunk)
        XCTAssertEqual(hunk.value as? String, "Collapsed")
        XCTAssertEqual(hunk.frame.height, expandedHunkFrame.height, accuracy: 0.5)
        XCTAssertEqual(hunk.frame.width, expandedHunkFrame.width, accuracy: 0.5)
        XCTAssertEqual(hunkTitle.frame.minX - hunk.frame.minX,
                       expandedTitleFrame.minX - expandedHunkFrame.minX, accuracy: 0.5)
        XCTAssertEqual(hunkTitle.frame.minY - hunk.frame.minY,
                       expandedTitleFrame.minY - expandedHunkFrame.minY, accuracy: 0.5)
        XCTAssertEqual(hunkTitle.frame.height, expandedTitleFrame.height, accuracy: 0.5)
        attachScreen(app, name: "Collapsed code difference header")
        tap(hunk)
        XCTAssertEqual(hunk.value as? String, "Expanded")
        XCTAssertEqual(hunk.frame.height, expandedHunkFrame.height, accuracy: 0.5)
        XCTAssertEqual(hunkTitle.frame.minX - hunk.frame.minX,
                       expandedTitleFrame.minX - expandedHunkFrame.minX, accuracy: 0.5)
        XCTAssertEqual(hunkTitle.frame.minY - hunk.frame.minY,
                       expandedTitleFrame.minY - expandedHunkFrame.minY, accuracy: 0.5)
        attachScreen(app, name: "Expanded code difference header")
        tap(app.buttons["close-file-changes"])
        XCTAssertEqual(field.value as? String, "Keep this draft")
    }

    @MainActor
    func testSummaryOnlyFileLoadsHistoricalCodePreview() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-file-preview-failure", "--fixture-slow-file-preview"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        tap(app.buttons["conversation-changes-hud"])
        let file = app.buttons["changed-file-KurageTests/ConversationChangesTests.swift"]
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        tap(file)
        let retry = app.buttons["retry-file-preview"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        attachScreen(app, name: "Historical preview retry after network failure")
        tap(retry)
        let preview = app.descendants(matching: .any)["historical-file-diff-KurageTests/ConversationChangesTests.swift"]
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["// Historical test line 1"].exists)
        XCTAssertFalse(app.buttons["retry-file-preview"].exists)
        attachScreen(app, name: "Large file with small historical additions")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(preview.exists)
        XCTAssertFalse(preview.waitForNonExistence(timeout: 1))
        XCTAssertFalse(app.progressIndicators["file-preview-loading"].exists)
        XCTAssertTrue(app.staticTexts["// Historical test line 1"].exists)
    }

    @MainActor
    func testHistoricalComparisonLimitKeepsRecordedExcerpt() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-file-preview-large-rewrite"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        tap(app.buttons["conversation-changes-hud"])
        let file = app.buttons["changed-file-KurageApp/Features/Conversation/ConversationView.swift"]
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        tap(file)
        XCTAssertTrue(app.staticTexts["This file has too many changes to compare on this device."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recorded excerpt · relative line numbers"].exists)
        let changedLine = app.staticTexts["    let showsChanges = true"]
        XCTAssertTrue(changedLine.waitForExistence(timeout: 5))
        for _ in 0..<4 where !changedLine.isHittable {
            app.scrollViews["file-changes-list"].swipeUp()
        }
        XCTAssertTrue(changedLine.isHittable)
        XCTAssertFalse(app.buttons["retry-file-preview"].exists)
        attachScreen(app, name: "Historical comparison limit with recorded excerpt")
    }

    @MainActor
    func testMachineSnapshotLimitExplainsCauseWithoutRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-file-preview-too-large"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        tap(app.buttons["conversation-changes-hud"])
        tap(app.buttons["changed-file-KurageTests/ConversationChangesTests.swift"])
        let notice = app.staticTexts["The session machine could not provide this snapshot because it exceeds its size limit."]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["retry-file-preview"].exists)
        attachScreen(app, name: "Machine snapshot limit without retry")
    }

    @MainActor
    func testWorkingTimerTicks() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-tests"])
        let label = app.staticTexts["turn-working-tests-agent"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        let reply = app.staticTexts["Running npm test"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(label.frame.maxY, reply.frame.minY)
        let initial = label.label
        XCTAssertTrue(initial.hasPrefix("Working… "))
        let changes = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in label.label != initial }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changes], timeout: 4), .completed)
        attachScreen(app, name: "Working timer")
        tap(app.buttons["pause-session"])
        XCTAssertTrue(label.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testWorkedForDisclosureRevealsEarlierWork() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        let toggle = app.buttons["turn-work-toggle-long-agent-20"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Worked for 1m 27s")
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertTrue(app.staticTexts["Latest reply in long conversation"].exists)
        XCTAssertFalse(app.staticTexts["I will check the conversation layout first."].exists)
        let attachment = app.staticTexts["Before work.txt"]
        XCTAssertTrue(attachment.exists)
        XCTAssertLessThan(attachment.frame.maxY, toggle.frame.minY)
        attachScreen(app, name: "Worked for collapsed")

        let headerY = toggle.frame.minY
        tap(toggle)
        XCTAssertEqual(toggle.value as? String, "Expanded")
        XCTAssertLessThan(attachment.frame.maxY, toggle.frame.minY)
        XCTAssertEqual(toggle.frame.minY, headerY, accuracy: 2)
        // Expanding at the bottom must not scroll the tapped header away.
        XCTAssertTrue(toggle.isHittable)
        XCTAssertTrue(app.staticTexts["I will check the conversation layout first."].waitForExistence(timeout: 5))
        let transcript = app.tables["conversation-transcript"]
        let activity = app.buttons["turn-activity-2:long-tool-1"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        XCTAssertEqual(activity.label, "Ran 2 commands · Read 1 file")
        for _ in 0..<4 where !activity.isHittable { transcript.swipeUp(velocity: .slow) }
        tap(activity)
        XCTAssertEqual(activity.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["git status --short"].waitForExistence(timeout: 5))
        attachScreen(app, name: "Worked for expanded with commands")

        for _ in 0..<4 where !toggle.isHittable { transcript.swipeDown(velocity: .slow) }
        let collapseY = toggle.frame.minY
        tap(toggle)
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertEqual(toggle.frame.minY, collapseY, accuracy: 2)
        XCTAssertFalse(app.staticTexts["git status --short"].exists)
        // Reopening restores the command list without moving its header.
        for _ in 0..<4 where !toggle.isHittable { transcript.swipeDown(velocity: .slow) }
        let reopenY = toggle.frame.minY
        tap(toggle)
        XCTAssertEqual(toggle.frame.minY, reopenY, accuracy: 2)
        XCTAssertTrue(app.staticTexts["git status --short"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMissingHistoryRejectionRequiresEditingAndPreservesTheRejectedBubble() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-send-not-delivered"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        let field = app.descendants(matching: .any)["follow-up-field"]
        tap(field)
        field.typeText("Recover this guidance")
        tap(app.buttons["send-follow-up"])
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "edit-message-")).firstMatch
        let retry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "retry-message-")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(edit.isEnabled)
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(retry.isEnabled)
        let rejectedEditID = edit.identifier
        attachScreen(app, name: "Missing-history rejection requires a new message")
        tap(edit)
        XCTAssertEqual(field.value as? String, "Recover this guidance")
        XCTAssertTrue(app.buttons[rejectedEditID].waitForNonExistence(timeout: 5))
        tap(app.buttons["send-follow-up"])
        XCTAssertTrue(retry.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Recover this guidance"))
            .firstMatch.waitForExistence(timeout: 5))
        attachScreen(app, name: "Rejected guidance remains visible after redelivery")
    }

    @MainActor
    func testRejectedMessageCanRestoreItsOriginalMentionDraftForEditing() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-send-rejected"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        let field = app.descendants(matching: .any)["follow-up-field"]
        tap(field)
        field.typeText("$review")
        tap(app.buttons["mention-skill-review-and-simplify-changes"])
        field.typeText("Please check")
        let original = field.value as? String
        tap(app.buttons["send-follow-up"])
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "edit-message-")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(field.value as? String == "" || field.value as? String == "Send a follow-up")
        XCTAssertTrue(edit.isEnabled)
        attachScreen(app, name: "Rejected message stays in its bubble")
        tap(edit)
        XCTAssertEqual(field.value as? String, original)
        XCTAssertTrue(edit.waitForNonExistence(timeout: 5))
        tap(app.buttons["send-follow-up"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Please check")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testRetryKeepsNextDraftAndConfirmsOnlyOneMessage() {
        for editDraft in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--fixture", "--fixture-send-unconfirmed"]
            app.launch()
            tap(app.buttons["sign-in-button"])
            tap(app.descendants(matching: .any)["session-session-tests"])
            let field = app.descendants(matching: .any)["follow-up-field"]
            tap(field)
            field.typeText("Retry this message")
            tap(app.buttons["send-follow-up"])
            let retry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "retry-message-")).firstMatch
            XCTAssertTrue(retry.waitForExistence(timeout: 5))
            XCTAssertTrue(field.value as? String == "" || field.value as? String == "Send a follow-up")
            XCTAssertTrue(app.staticTexts["Retry this message"].exists)
            if editDraft { tap(field); field.typeText("Next draft") }
            tap(retry)
            XCTAssertTrue(retry.waitForNonExistence(timeout: 5))
            if editDraft { XCTAssertEqual(field.value as? String, "Next draft") }
            else { XCTAssertTrue(field.value as? String == "" || field.value as? String == "Send a follow-up") }
            XCTAssertEqual(app.staticTexts.matching(identifier: "Retry this message").count, 1)
            app.terminate()
        }
    }

    @MainActor
    func testUnconfirmedBubbleSurvivesReopeningAndPreservesNewDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-send-unconfirmed"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-tests"])
        let field = app.descendants(matching: .any)["follow-up-field"]
        tap(field)
        field.typeText("Restore this message")
        tap(app.buttons["send-follow-up"])
        let retry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "retry-message-")).firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5))

        app.navigationBars.buttons.firstMatch.tap()
        tap(app.descendants(matching: .any)["session-session-long"])
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.value as? String == "" || field.value as? String == "Send a follow-up")
        XCTAssertFalse(retry.exists)
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.descendants(matching: .any)["session-session-tests"])
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(field.value as? String == "" || field.value as? String == "Send a follow-up")
        XCTAssertTrue(app.staticTexts["Restore this message"].exists)

        tap(field)
        field.typeText("Next draft")
        let editedDraft = field.value as? String
        XCTAssertTrue(editedDraft?.contains("Next draft") == true)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, editedDraft)
        tap(retry)
        XCTAssertTrue(retry.waitForNonExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, editedDraft)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Restore this message").count, 1)

        app.navigationBars.buttons.firstMatch.tap()
        tap(app.descendants(matching: .any)["session-session-tests"])
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
        XCTAssertTrue(field.value as? String == "" || field.value as? String == "Send a follow-up")
    }

    @MainActor
    func testLatestTurnWithoutChangesCanShowEmptyScope() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        let field = app.descendants(matching: .any)["follow-up-field"]
        tap(field)
        field.typeText("Explain without editing")
        tap(app.buttons["send-follow-up"])
        XCTAssertTrue(app.buttons["send-follow-up"].wait(for: \.label, toEqual: "Send", timeout: 5))
        tap(app.buttons["conversation-changes-hud"])
        let scope = app.buttons["file-changes-title"]
        XCTAssertTrue(scope.wait(for: \.label, toEqual: "All turns", timeout: 5))
        XCTAssertTrue(app.staticTexts["Turn 20"].waitForExistence(timeout: 5))
        tap(scope)
        tap(app.buttons["Last turn"])
        XCTAssertTrue(app.staticTexts["No recorded changes"].waitForExistence(timeout: 5))
        attachScreen(app, name: "Latest turn has no changes")
        tap(scope)
        tap(app.buttons["All turns"])
        XCTAssertTrue(app.staticTexts["Turn 20"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSendShowsBubbleBeforeDeliveryAndKeepsOneTurn() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-tab-send"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-tests"])

        let field = app.descendants(matching: .any)["follow-up-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        tap(field)
        let text = "This long message should keep the same bubble width and line wrapping while sending and after delivery."
        field.typeText(text)
        let send = app.buttons["send-follow-up"]
        tap(send)

        XCTAssertTrue(send.wait(for: \.label, toEqual: "Sending", timeout: 2))
        let message = app.textViews[text]
        XCTAssertTrue(message.waitForExistence(timeout: 2))
        let progress = app.activityIndicators["Sending"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 2))
        let sendingFrame = message.frame
        let progressGap = sendingFrame.minX - progress.frame.maxX
        XCTAssertGreaterThanOrEqual(progressGap, 0)
        XCTAssertLessThanOrEqual(progressGap, 8)
        XCTAssertTrue(field.value as? String == "" || field.value as? String == "Send a follow-up")
        XCTAssertTrue(field.isEnabled)
        field.typeText("Next draft")
        XCTAssertFalse(send.isEnabled)
        attachScreen(app, name: "optimistic-send")
        XCTAssertTrue(send.wait(for: \.label, toEqual: "Send", timeout: 20))
        XCTAssertTrue(progress.waitForNonExistence(timeout: 5))
        XCTAssertEqual(message.frame.width, sendingFrame.width, accuracy: 1)
        XCTAssertEqual(message.frame.height, sendingFrame.height, accuracy: 1)
        attachScreen(app, name: "delivered-bubble-same-width")
        XCTAssertEqual(field.value as? String, "Next draft")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.descendants(matching: .any)["session-session-tests"])
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews.matching(identifier: text).count, 1)
    }

    @MainActor
    func testSessionListModesAndMoreMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        let connect = app.buttons["sign-in-button"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        tap(connect)

        let projectHeading = app.buttons["project-header-local:machine-1:kurage"]
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

        let account = app.buttons["account-menu"]
        tap(account)
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testProjectHeaderWithoutCreationUsesFullWidth() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-unassigned-session"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        let table = app.tables.firstMatch
        let heading = app.buttons["project-header-unassigned"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["new-session-unassigned"].exists)
        XCTAssertEqual(heading.frame.maxX, table.frame.maxX - 16, accuracy: 1)
        attachScreen(app, name: "project-header-without-creation-full-width")

        // Tap the column previously reserved for the hidden new-session button.
        let rightEdge = table.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: table.frame.width - 20, dy: heading.frame.midY - table.frame.minY
        ))
        rightEdge.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Collapsed"), object: heading
        )], timeout: 3), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["session-fixture-unassigned-session"].exists)
        rightEdge.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Expanded"), object: heading
        )], timeout: 3), .completed)
        XCTAssertTrue(app.descendants(matching: .any)["session-fixture-unassigned-session"].waitForExistence(timeout: 3))
        attachScreen(app, name: "project-header-without-creation-expanded")
    }

    @MainActor
    func testProjectHeadersStayPinnedAndKeepTheirActions() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-long-session-list"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        let table = app.tables.firstMatch
        let kurage = app.buttons["project-header-local:machine-1:kurage"]
        let prism = app.buttons["project-header-local:machine-1:prism"]
        XCTAssertTrue(kurage.waitForExistence(timeout: 5))
        let start = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        let end = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(app.buttons.matching(identifier: "project-header-local:machine-1:kurage").count, 1)
        let pinnedY = kurage.frame.minY
        XCTAssertEqual(pinnedY, table.frame.minY, accuracy: 2)
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(kurage.frame.minY, pinnedY, accuracy: 2)
        XCTAssertEqual(app.buttons.matching(identifier: "new-session-local:machine-1:kurage").count, 1)
        attachScreen(app, name: "kurage-project-pinned")
        tap(app.buttons["new-session-local:machine-1:kurage"])
        XCTAssertTrue(app.descendants(matching: .any)["new-session-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["kurage"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(kurage.waitForExistence(timeout: 5))

        for _ in 0..<10 {
            if prism.isHittable && abs(prism.frame.minY - pinnedY) < 2 { break }
            table.swipeUp()
        }
        XCTAssertTrue(prism.isHittable)
        XCTAssertEqual(prism.frame.minY, pinnedY, accuracy: 2)
        XCTAssertFalse(kurage.isHittable)
        attachScreen(app, name: "prism-project-pinned")
        tap(app.buttons["new-session-local:machine-1:prism"])
        XCTAssertTrue(app.descendants(matching: .any)["new-session-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["prism"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(prism.waitForExistence(timeout: 5))
        tap(prism)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Collapsed"), object: prism
        )], timeout: 3), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["session-list-prism-12"].exists)
        attachScreen(app, name: "project-collapsed-after-pinning")
        // Collapsing a long section can adjust the content offset and move its
        // header below the viewport, especially with accessibility text sizes.
        for _ in 0..<3 {
            if prism.exists && prism.isHittable { break }
            table.swipeUp()
        }
        XCTAssertTrue(prism.waitForExistence(timeout: 3))
        tap(prism)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Expanded"), object: prism
        )], timeout: 3), .completed)
        let restoredSession = app.descendants(matching: .any)["session-list-prism-12"]
        for _ in 0..<3 {
            if restoredSession.exists { break }
            table.swipeUp()
        }
        XCTAssertTrue(restoredSession.waitForExistence(timeout: 5))
        attachScreen(app, name: "project-expanded-after-pinning")
    }

    @MainActor
    func testArchivedSessionsSheetIsNewestFirstAndSupportsRestore() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])

        let more = app.buttons["more-options"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        tap(more)
        let archived = app.buttons["archived-sessions"]
        XCTAssertTrue(archived.waitForExistence(timeout: 2))
        tap(archived)

        let newer = app.staticTexts["newer archived"]
        let older = app.staticTexts["older archived"]
        XCTAssertTrue(newer.waitForExistence(timeout: 5))
        XCTAssertTrue(older.waitForExistence(timeout: 2))
        XCTAssertLessThan(newer.frame.minY, older.frame.minY)
        XCTAssertTrue(app.buttons["close-archived-sessions"].exists)
        XCTAssertFalse(app.buttons["delete-archived-older"].exists)
        attachScreen(app, name: "archived-sessions-sheet")

        let restoreNewer = app.buttons["restore-archived-newer"]
        tap(restoreNewer)
        XCTAssertTrue(restoreNewer.wait(for: \.exists, toEqual: false, timeout: 5))

        tap(app.buttons["close-archived-sessions"])
        XCTAssertTrue(app.descendants(matching: .any)["session-archived-newer"].waitForExistence(timeout: 5))

        tap(more)
        XCTAssertTrue(archived.waitForExistence(timeout: 2))
        tap(archived)
        XCTAssertTrue(older.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["delete-archived-older"].exists)
    }

    @MainActor
    func testRunningComposerSteersWithoutQueueConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-tests"])
        tap(app.buttons["permission-review"])
        tap(app.buttons["permission-allow"].firstMatch)

        let field = app.descendants(matching: .any)["follow-up-field"]
        let pause = app.buttons["pause-session"]
        let send = app.buttons["send-follow-up"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertFalse(send.exists)
        attachScreen(app, name: "running-empty-stop")

        tap(field)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            attachScreen(app, name: "running-focus-retry")
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("Steer this reply")
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled)
        XCTAssertFalse(pause.exists)
        XCTAssertEqual(field.value as? String, "Steer this reply")
        attachScreen(app, name: "running-input-send")

        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Steer this reply".count))
        if let remainder = field.value as? String, !remainder.isEmpty, remainder != "Send a follow-up" {
            attachScreen(app, name: "running-delete-remainder")
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: remainder.count))
        }
        XCTAssertTrue(field.value as? String == "" || field.value as? String == "Send a follow-up")
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertFalse(send.exists)

        field.typeText("Steer this reply")
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        tap(send)
        XCTAssertTrue(app.staticTexts["Steer this reply"].waitForExistence(timeout: 5))
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertFalse(send.exists)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attachScreen(app, name: "steer-sent-stop")

        tap(pause)
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(pause.exists)
    }

    @MainActor
    func testSignInOpenSessionAllowAndSend() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()

        let connect = app.buttons["sign-in-button"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["welcome-title"].label.contains("Welcome to"))
        XCTAssertEqual(connect.label, "Get Started")
        attachScreen(app, name: "sign-in")
        tap(connect)

        let session = app.descendants(matching: .any)["session-session-tests"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(session.label.contains("fix flaky tests"))
        XCTAssertTrue(app.descendants(matching: .any)["session-session-pr"].exists)
        attachScreen(app, name: "sessions")
        tap(session)

        XCTAssertTrue(app.staticTexts["conversation-project-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["conversation-project-name"].label, "kurage")
        XCTAssertEqual(app.staticTexts["conversation-machine-name"].label, "spike@mac")

        let review = app.buttons["permission-review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Allow npm test?"].exists)
        let firstMessage = app.staticTexts["Run the tests again"]
        XCTAssertTrue(firstMessage.waitForExistence(timeout: 5))
        let firstMessageVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: firstMessage
        )
        XCTAssertEqual(XCTWaiter.wait(for: [firstMessageVisible], timeout: 5), .completed)
        attachScreen(app, name: "conversation")
        tap(review)
        let allow = app.buttons["permission-allow"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        tap(allow)
        XCTAssertFalse(review.waitForExistence(timeout: 2))

        let field = app.descendants(matching: .any)["follow-up-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let pause = app.buttons["pause-session"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertEqual(pause.label, "Stop reply")
        XCTAssertFalse(app.buttons["send-follow-up"].exists)
        tap(field)
        field.typeText("look again")

        XCTAssertTrue(pause.waitForNonExistence(timeout: 5))
        let runningSend = app.buttons["send-follow-up"]
        XCTAssertTrue(runningSend.waitForExistence(timeout: 5))
        XCTAssertTrue(runningSend.isEnabled)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "look again".count))
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertFalse(runningSend.exists)
        field.typeText("look again")
        XCTAssertTrue(runningSend.waitForExistence(timeout: 5))
        attachScreen(app, name: "running-steer-send")
        tap(runningSend)
        XCTAssertTrue(app.staticTexts["look again"].waitForExistence(timeout: 5))
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertFalse(runningSend.exists)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        tap(pause)
        XCTAssertTrue(app.buttons["send-follow-up"].waitForExistence(timeout: 5))
        tap(field)
        field.typeText("continue after stopping")
        XCTAssertEqual(field.value as? String, "continue after stopping")

        tap(app.buttons["send-follow-up"])
        let sentMessage = app.staticTexts["continue after stopping"]
        XCTAssertTrue(sentMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Run the tests again"].isHittable)
        XCTAssertLessThan(field.frame.minY - sentMessage.frame.maxY, 160)
        attachScreen(app, name: "sent")

        app.tables["conversation-transcript"].swipeDown()
        XCTAssertFalse(app.keyboards.firstMatch.isHittable)
        tap(field)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThan(field.frame.minY - sentMessage.frame.maxY, 160)
        attachScreen(app, name: "keyboard-reopened")
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
        XCTAssertTrue(latest.wait(for: \.frame.isEmpty, toEqual: false, timeout: 5))
        let transcript = app.tables["conversation-transcript"]
        let composer = app.otherElements["follow-up-composer"]
        let visibleTranscript = CGRect(x: transcript.frame.minX, y: transcript.frame.minY,
                                       width: transcript.frame.width,
                                       height: composer.frame.minY - transcript.frame.minY)
        XCTAssertTrue(visibleTranscript.contains(latest.frame))

        transcript.swipeDown()
        XCTAssertFalse(latest.exists && visibleTranscript.intersects(latest.frame))
        tap(app.descendants(matching: .any)["follow-up-field"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(latest.isHittable)
    }

    @MainActor
    func testMentionButtonInsertsTriggerAndPreservesDraft() {
        verifyMentionButton(newSession: false)
    }

    @MainActor
    func testNewSessionMentionButtonInsertsTriggerAndPreservesDraft() {
        verifyMentionButton(newSession: true)
    }

    @MainActor
    func testNewTabMentionButtonInsertsTriggerAndPreservesDraft() {
        verifyMentionButton(newSession: false, newTab: true)
    }

    @MainActor
    private func verifyMentionButton(newSession: Bool, newTab: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        if newSession {
            tap(app.buttons["new-session-local:machine-1:prism"])
        } else {
            tap(app.descendants(matching: .any)["session-session-long"])
            if newTab { tap(app.buttons["new-session-tab"]) }
        }
        let isNew = newSession || newTab
        let field = app.descendants(matching: .any)[isNew ? "new-session-field" : "follow-up-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let mention = app.buttons["add-mention"]
        XCTAssertTrue(mention.waitForExistence(timeout: 5))
        XCTAssertTrue(mention.isHittable)
        XCTAssertEqual(mention.frame.width, 44, accuracy: 0.5)
        XCTAssertEqual(mention.frame.height, 44, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(mention.frame.minX, app.buttons["add-attachment"].frame.maxX)
        XCTAssertEqual(mention.label, "Mention")
        XCTAssertFalse(app.buttons["full-access-mode"].exists)

        tap(mention)
        XCTAssertEqual(field.value as? String, "@")
        let menu = app.scrollViews["mention-suggestions"]
        let skill = app.buttons["mention-skill-review-and-simplify-changes"]
        XCTAssertTrue(skill.waitForExistence(timeout: 5))
        assertMentionMenuGeometry(app, field: field, menu: menu, newSession: isNew)
        attachScreen(app, name: "Mention button empty draft \(newSession)-\(newTab)")

        field.typeText(XCUIKeyboardKey.delete.rawValue + "Keep this draft🙂")
        tap(mention)
        XCTAssertEqual(field.value as? String, "Keep this draft🙂 @")
        XCTAssertTrue(skill.waitForExistence(timeout: 5))
        assertMentionMenuGeometry(app, field: field, menu: menu, newSession: isNew)
        attachScreen(app, name: "Mention button after text \(newSession)-\(newTab)")

        field.typeText(XCUIKeyboardKey.delete.rawValue)
        tap(mention)
        XCTAssertEqual(field.value as? String, "Keep this draft🙂 @")
        field.typeText(XCUIKeyboardKey.delete.rawValue + "\n")
        tap(mention)
        XCTAssertEqual(field.value as? String, "Keep this draft🙂 \n@")
        // Filter to the skill before selecting it: accessibility sizes show
        // one candidate row, with sessions first for an empty @ query.
        field.typeText("review-and")
        XCTAssertTrue(skill.waitForExistence(timeout: 5))
        XCTAssertTrue(skill.isHittable)
        tap(skill)
        XCTAssertEqual(field.value as? String, "Keep this draft🙂 \n$review-and-simplify-changes ")
        tap(mention)
        XCTAssertEqual(field.value as? String, "Keep this draft🙂 \n$review-and-simplify-changes @")
        XCTAssertTrue(skill.waitForExistence(timeout: 5))
        assertMentionMenuGeometry(app, field: field, menu: menu, newSession: isNew)
        attachScreen(app, name: "Mention button preserves selected skill \(newSession)-\(newTab)")
    }

    @MainActor
    func testFocusedComposerShowsRunConfigAndChangesReasoning() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        let session = app.descendants(matching: .any)["session-session-long"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        tap(session)

        let field = app.descendants(matching: .any)["follow-up-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let menu = app.buttons["run-config-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let context = app.buttons["context-window-usage"]
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(context.frame.maxX, menu.frame.minX)
        XCTAssertEqual(context.label, "Context window")
        XCTAssertEqual(context.value as? String, "217K used of 258K")
        tap(context)
        XCTAssertEqual(app.staticTexts["context-window-detail"].label, "217K used / 258K")
        app.tables["conversation-transcript"].tap()
        XCTAssertTrue(app.staticTexts["context-window-detail"].wait(for: \.exists, toEqual: false, timeout: 5))
        tap(field)
        XCTAssertGreaterThan(menu.frame.minY, field.frame.minY)
        XCTAssertGreaterThan(app.buttons["send-follow-up"].frame.minY, field.frame.minY)
        XCTAssertEqual(menu.label, "Model gpt-5.5, reasoning High")
        attachScreen(app, name: "run-config-row")

        tap(menu)
        let dial = app.otherElements["reasoning-dial"]
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        app.buttons["run-config-dismiss"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertTrue(dial.wait(for: \.exists, toEqual: false, timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        tap(menu)
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        dial.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertEqual(dial.value as? String, "Low")
        attachScreen(app, name: "reasoning-low-at-start")
        dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(dial.value as? String, "Medium")
        let start = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(dial.value as? String, "High")
        attachScreen(app, name: "reasoning-dial")
        tap(app.buttons["run-config-advanced"])
        tap(app.staticTexts["run-config-reasoning-label"])
        XCTAssertFalse(app.buttons["Low"].exists)
        tap(app.buttons["run-config-reasoning"])
        let low = app.buttons["Low"]
        XCTAssertTrue(low.waitForExistence(timeout: 5))
        attachScreen(app, name: "run-config-menu")
        tap(low)
        XCTAssertTrue(app.keyboards.firstMatch.wait(for: \.exists, toEqual: false, timeout: 5))
        let speed = app.descendants(matching: .any)["run-config-speed"]
        XCTAssertTrue(speed.exists)
        XCTAssertFalse(speed.frame.isEmpty)
        XCTAssertTrue(app.frame.contains(speed.frame))
        attachScreen(app, name: "run-config-advanced")
        tap(app.buttons["run-config-done"])
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "Model gpt-5.5, reasoning Low")

        tap(field)
        field.typeText("go faster")
        tap(app.buttons["send-follow-up"])
        XCTAssertTrue(app.staticTexts["go faster"].waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "Model gpt-5.5, reasoning Low")
    }

    @MainActor
    func testKeyboardAndMultilineComposerKeepLatestMessageVisible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        let session = app.descendants(matching: .any)["session-session-long"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        tap(session)

        let latest = app.staticTexts["Latest reply in long conversation"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        let field = app.descendants(matching: .any)["follow-up-field"]
        for _ in 0..<2 {
            tap(field)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            assertMessageAboveComposer(latest, field: field)
            app.tables["conversation-transcript"].swipeDown()
            XCTAssertFalse(app.keyboards.firstMatch.isHittable)
            // Dismissing the keyboard also scrolls into history. Reach the actual bottom
            // (not just a visible last row) before testing automatic following again.
            app.tables["conversation-transcript"].swipeUp()
            app.tables["conversation-transcript"].swipeUp()
        }
        tap(field)
        let composer = app.otherElements["follow-up-composer"]
        let singleLineHeight = composer.frame.height
        field.typeText("First line\nSecond line\nThird line\nFourth line\nFifth line")
        XCTAssertGreaterThan(composer.frame.height, singleLineHeight + 50)
        XCTAssertTrue(composer.frame.contains(field.frame))
        XCTAssertLessThanOrEqual(composer.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertTrue(composer.frame.contains(app.buttons["send-follow-up"].frame))
        assertMessageAboveComposer(latest, field: field)
        attachScreen(app, name: "multiline-keyboard")
        tap(app.buttons["send-follow-up"])
        let sent = app.textViews["First line\nSecond line\nThird line\nFourth line\nFifth line"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        XCTAssertTrue(sent.wait(for: \.frame.isEmpty, toEqual: false, timeout: 5))
        try XCTSkipIf(!app.frame.intersects(app.keyboards.firstMatch.frame),
                      "The simulator software keyboard is offscreen; keyboard visibility needs device verification.")
        XCTAssertTrue(app.keyboards.firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertGreaterThan(sent.frame.height, 70)
        XCTAssertGreaterThan(sent.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(sent.frame.maxY, field.frame.minY)
        attachScreen(app, name: "multiline-sent")
    }

    @MainActor
    func testNewSessionReadsBranchPreservesDraftAndRefreshesOnForeground() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        let newSession = app.buttons["new-session-local:machine-1:prism"]
        XCTAssertTrue(newSession.waitForExistence(timeout: 5))
        tap(newSession)
        let field = app.descendants(matching: .any)["new-session-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        tap(field)
        field.typeText("Build in this project")
        let branch = app.buttons["new-session-branch"]
        XCTAssertTrue(branch.wait(for: \.label, toEqual: "Branch, main", timeout: 5))
        let machine = app.descendants(matching: .any)["new-session-machine"]
        let project = app.buttons["new-session-project"]
        XCTAssertEqual(project.frame.midY - machine.frame.midY, branch.frame.midY - project.frame.midY, accuracy: 1)
        attachScreen(app, name: "Read-only current branch with draft")
        tap(branch)
        XCTAssertTrue(branch.wait(for: \.label, toEqual: "Branch, main", timeout: 5))
        XCTAssertFalse(app.buttons["feature/client"].exists)
        XCTAssertFalse(app.buttons["create-project-branch"].exists)
        XCTAssertEqual(field.value as? String, "Build in this project")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(branch.wait(for: \.label, toEqual: "Branch, main", timeout: 5))
        XCTAssertEqual(field.value as? String, "Build in this project")
        attachScreen(app, name: "Read-only branch after returning from background")
        XCTAssertTrue(app.buttons["new-session-send"].wait(for: \.isEnabled, toEqual: true, timeout: 5))
        tap(app.buttons["new-session-send"])
        XCTAssertTrue(app.descendants(matching: .any)["follow-up-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Build in this project"].exists)
    }

    @MainActor
    func testNewSessionShowsBranchReadFailureAndRetriesWithoutBlockingSend() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-project-git-failure"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        let newSession = app.buttons["new-session-local:machine-1:prism"]
        XCTAssertTrue(newSession.waitForExistence(timeout: 5))
        tap(newSession)
        let field = app.descendants(matching: .any)["new-session-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        tap(field)
        field.typeText("Keep this draft")
        let branch = app.buttons["new-session-branch"]
        XCTAssertTrue(branch.wait(for: \.label, toEqual: "Branch, No access to this project's Git state.", timeout: 5))
        XCTAssertTrue(app.buttons["new-session-send"].wait(for: \.isEnabled, toEqual: true, timeout: 5))
        attachScreen(app, name: "Branch read failure leaves composer usable")
        tap(branch)
        XCTAssertTrue(branch.wait(for: \.label, toEqual: "Branch, main", timeout: 5))
        XCTAssertEqual(field.value as? String, "Keep this draft")
        tap(app.buttons["new-session-project"])
        tap(app.buttons["kurage"])
        XCTAssertTrue(branch.wait(for: \.label, toEqual: "Branch, main", timeout: 5))
        XCTAssertEqual(field.value as? String, "Keep this draft")
        attachScreen(app, name: "Branch readable for a running project")
    }

    @MainActor
    func testNewChatChoosesProjectAndMachineFolder() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])

        let newChat = app.buttons["new-chat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 5))
        XCTAssertTrue(newChat.isHittable)
        tap(newChat)
        let field = app.descendants(matching: .any)["new-session-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        tap(field)
        field.typeText("Build the new app")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY)
        attachScreen(app, name: "New chat project row with focused draft")
        let project = app.buttons["new-session-project"]
        tap(project)
        // UIKit's native menu preserves these project labels, but not the
        // identifiers attached to the dynamically generated SwiftUI buttons.
        let prism = app.buttons["prism"]
        XCTAssertTrue(prism.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["kurage"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.navigationBars["Choose Project"].exists)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        XCTAssertTrue(app.buttons["choose-machine-folder"].label.contains("Add new folder"))
        attachScreen(app, name: "New chat anchored project menu")
        tap(prism)
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        XCTAssertTrue(project.label.contains("prism"))
        XCTAssertEqual(field.value as? String, "Build the new app")

        tap(project)
        let chooseFolder = app.buttons["choose-machine-folder"]
        XCTAssertTrue(chooseFolder.waitForExistence(timeout: 5))
        XCTAssertTrue(chooseFolder.label.contains("Add new folder"))
        tap(chooseFolder)
        let projectsFolder = app.buttons["folder-projects"]
        XCTAssertTrue(projectsFolder.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Choose Folder"].exists)
        XCTAssertFalse(app.navigationBars["Choose Project"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attachScreen(app, name: "Connected machine folder choices")
        // The trailing blank area must activate the row, not only its label.
        XCTAssertTrue(projectsFolder.isHittable)
        projectsFolder.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let currentFolder = app.buttons["folder-Current folder"]
        XCTAssertTrue(currentFolder.waitForExistence(timeout: 5))
        for _ in 0..<2 {
            tap(currentFolder)
            XCTAssertTrue(currentFolder.wait(for: \.isEnabled, toEqual: true, timeout: 5))
            XCTAssertEqual(app.staticTexts["folder-path"].label, "/Users/demo/projects")
            XCTAssertFalse(app.descendants(matching: .any)["folder-loading"].exists)
        }
        let newAppFolder = app.buttons["folder-New App"]
        XCTAssertTrue(newAppFolder.waitForExistence(timeout: 5))
        let aliasFolder = app.buttons["folder-New App alias"]
        XCTAssertTrue(aliasFolder.exists)
        attachScreen(app, name: "Machine folder aliases have distinct rows")
        tap(newAppFolder)
        XCTAssertTrue(app.staticTexts["No subfolders"].waitForExistence(timeout: 5))
        tap(app.buttons["folder-parent"])
        XCTAssertTrue(aliasFolder.waitForExistence(timeout: 5))
        XCTAssertTrue(newAppFolder.exists)
        tap(aliasFolder)
        XCTAssertTrue(app.staticTexts["No subfolders"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["folder-path"].label, "/Users/demo/projects/New App")
        tap(app.buttons["folder-parent"])
        XCTAssertTrue(newAppFolder.waitForExistence(timeout: 5))
        tap(app.buttons["folder-parent"])
        XCTAssertTrue(projectsFolder.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["folder-path"].label, "/Users/demo")
        tap(projectsFolder)
        XCTAssertTrue(newAppFolder.waitForExistence(timeout: 5))
        tap(newAppFolder)
        XCTAssertTrue(app.staticTexts["No subfolders"].waitForExistence(timeout: 5))
        attachScreen(app, name: "Selected machine folder")
        tap(app.buttons["choose-current-folder"])

        XCTAssertTrue(project.waitForExistence(timeout: 5))
        XCTAssertTrue(project.label.contains("New App"))
        XCTAssertFalse(app.staticTexts["/Users/demo/projects/New App"].exists)
        XCTAssertEqual(field.value as? String, "Build the new app")
        let send = app.buttons["new-session-send"]
        XCTAssertTrue(send.wait(for: \.isEnabled, toEqual: true, timeout: 5))
        attachScreen(app, name: "New chat in selected machine folder")
        tap(send)
        XCTAssertTrue(app.staticTexts["Build the new app"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["follow-up-field"].waitForExistence(timeout: 5))
        attachScreen(app, name: "Machine folder session started")
    }

    @MainActor
    func testProjectRowStartsNewSessionWithChosenModel() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])

        let newSession = app.buttons["new-session-local:machine-1:prism"]
        XCTAssertTrue(newSession.waitForExistence(timeout: 5))
        XCTAssertEqual(newSession.label, "New session in prism")
        attachScreen(app, name: "project-new-session-button")
        tap(newSession)

        let field = app.descendants(matching: .any)["new-session-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["spike@mac"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["prism"].exists)
        // New sessions and follow-ups share the gauge and Advanced controls.
        let menu = app.buttons["run-config-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "Provider Claude Code, model Sonnet")
        XCTAssertFalse(app.buttons["new-session-send"].isEnabled)

        tap(menu)
        tap(app.buttons["run-config-advanced"])
        tap(app.buttons["run-config-model"])
        let opus = app.buttons["Opus"]
        XCTAssertTrue(opus.waitForExistence(timeout: 5))
        tap(opus)
        tap(app.buttons["run-config-done"])
        XCTAssertTrue(menu.wait(for: \.label, toEqual: "Provider Claude Code, model Opus", timeout: 5))
        tap(field)
        XCTAssertTrue(field.isHittable)

        tap(menu)
        tap(app.buttons["run-config-advanced"])
        tap(app.buttons["run-config-provider"])
        let codex = app.buttons["Codex"]
        XCTAssertTrue(codex.waitForExistence(timeout: 5))
        attachScreen(app, name: "new-session-menu")
        tap(codex)
        let reasoningControl = app.buttons["run-config-reasoning"]
        XCTAssertTrue(reasoningControl.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["run-config-model"].label.contains("gpt-5.5"))
        tap(reasoningControl)
        let medium = app.buttons["Medium"]
        XCTAssertTrue(medium.waitForExistence(timeout: 5))
        tap(medium)
        attachScreen(app, name: "new-session-advanced-neutral")
        tap(app.buttons["run-config-done"])
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "Provider Codex, model gpt-5.5, reasoning Medium")
        attachScreen(app, name: "new-session")

        tap(field)
        field.typeText("Add a settings screen")
        tap(app.buttons["new-session-send"])

        let sent = app.staticTexts["Add a settings screen"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["follow-up-field"].waitForExistence(timeout: 5))
        attachScreen(app, name: "new-session-started")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(newSession.waitForExistence(timeout: 5))
        let started = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "session-", "Add a settings screen")
        ).firstMatch
        XCTAssertTrue(started.waitForExistence(timeout: 5))
        XCTAssertLessThan(started.frame.minY, app.descendants(matching: .any)["session-session-pr"].frame.minY)
    }

    @MainActor
    func testUnconfirmedStartCanRetryAfterBackgroundAndTemplateArchival() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-start-unconfirmed"]
        app.launch()
        XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
        tap(app.buttons["sign-in-button"])
        let newSession = app.buttons["new-session-local:machine-1:prism"]
        XCTAssertTrue(newSession.waitForExistence(timeout: 5))
        tap(newSession)
        let field = app.descendants(matching: .any)["new-session-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        tap(field)
        field.typeText("Recover original task")
        tap(app.buttons["new-session-send"])
        let retry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "retry-message-")).firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Recover original task"].waitForExistence(timeout: 5))
        XCTAssertTrue(retry.isEnabled)
        attachScreen(app, name: "pending-start-options-failed")
        app.navigationBars.buttons.firstMatch.tap()
        let pending = app.buttons["pending-session-starts"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        let list = app.tables.firstMatch
        let pullStart = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let pullEnd = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        pullStart.press(forDuration: 0.1, thenDragTo: pullEnd)
        // A refreshed list has no active template, but retains the recovery entry.
        XCTAssertTrue(app.buttons["new-session-local:machine-1:prism"].waitForNonExistence(timeout: 5))
        tap(pending)
        tap(app.buttons["Recover original task"])
        XCTAssertTrue(app.staticTexts["Recover original task"].waitForExistence(timeout: 5))
        attachScreen(app, name: "pending-start-reopened")
        tap(retry)
        XCTAssertTrue(app.descendants(matching: .any)["follow-up-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recover original task"].exists)
        attachScreen(app, name: "pending-start-recovered")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertFalse(pending.exists)
    }

    @MainActor
    func testIncompleteSearchCanRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-search-failure"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        let search = app.textFields["session-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        tap(search)
        search.typeText("Question 7")
        let retry = app.buttons["retry-session-search"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(retry.isHittable)
        XCTAssertEqual(search.value as? String, "Question 7")
        XCTAssertTrue(app.keyboards.firstMatch.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["session-session-long"].exists)
        attachScreen(app, name: "search-incomplete")
        tap(retry)
        XCTAssertTrue(app.descendants(matching: .any)["session-session-long"].waitForExistence(timeout: 5))
        XCTAssertFalse(retry.exists)
        attachScreen(app, name: "search-retry-recovered")
    }

    @MainActor
    func testSessionSearchMatchesTitleAndMessageBody() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        let connect = app.buttons["sign-in-button"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        tap(connect)

        let search = app.textFields["session-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let table = app.tables.firstMatch
        let sessionList = table.waitForExistence(timeout: 2) ? table : app.collectionViews.firstMatch
        XCTAssertTrue(sessionList.waitForExistence(timeout: 5))
        XCTAssertLessThan(search.frame.minY, sessionList.frame.maxY)
        tap(search)
        search.typeText("flaky")

        let tests = app.descendants(matching: .any)["session-session-tests"].firstMatch
        let long = app.descendants(matching: .any)["session-session-long"].firstMatch
        let pr = app.descendants(matching: .any)["session-session-pr"].firstMatch
        XCTAssertTrue(tests.waitForExistence(timeout: 5))
        XCTAssertTrue(tests.label.contains("fix flaky tests"))
        XCTAssertFalse(app.descendants(matching: .any)["session-session-long"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["session-session-pr"].exists)
        XCTAssertTrue(app.buttons["project-header-local:machine-1:kurage"].exists)
        XCTAssertFalse(app.buttons["project-header-local:machine-1:prism"].exists)
        attachScreen(app, name: "search-title")

        tap(app.buttons["session-search-clear"])
        XCTAssertTrue(long.waitForExistence(timeout: 5))
        XCTAssertTrue(pr.waitForExistence(timeout: 5))

        tap(search)
        search.typeText("Question 7")
        XCTAssertTrue(long.waitForExistence(timeout: 5))
        XCTAssertTrue(long.label.contains("Question 7"))
        XCTAssertFalse(app.descendants(matching: .any)["session-session-tests"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["session-session-pr"].exists)
        attachScreen(app, name: "search-body")

        tap(app.buttons["session-search-clear"])
        tap(search)
        search.typeText("no-matching-conversation-123\n")
        XCTAssertTrue(app.staticTexts["No matching sessions"].waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        let emptyList = app.scrollViews.firstMatch
        XCTAssertTrue(emptyList.waitForExistence(timeout: 2))
        emptyList.swipeDown()
        XCTAssertTrue(app.staticTexts["No matching sessions"].waitForExistence(timeout: 5))
        attachScreen(app, name: "search-empty")

        tap(app.buttons["session-search-clear"])
        XCTAssertTrue(long.waitForExistence(timeout: 5))
        app.tables.firstMatch.swipeDown()
        XCTAssertTrue(tests.waitForExistence(timeout: 5))
        attachScreen(app, name: "list-refreshed")
    }

    @MainActor
    func testSwipeArchiveRequiresConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        let connect = app.buttons["sign-in-button"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        tap(connect)

        let session = app.descendants(matching: .any)["session-session-pr"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        let row = app.cells.containing(.any, identifier: "session-session-pr").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.swipeLeft()
        let archive = app.buttons["Archive"].firstMatch
        XCTAssertTrue(archive.waitForExistence(timeout: 2))
        tap(archive)

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(alert.staticTexts["This archives the session and its child sessions."].exists)
        tap(alert.buttons["Cancel"])
        XCTAssertTrue(session.waitForExistence(timeout: 2))

        row.swipeLeft()
        XCTAssertTrue(archive.waitForExistence(timeout: 2))
        tap(archive)
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        let confirm = app.buttons.matching(identifier: "archive-confirm").element(boundBy: 0)
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(session.waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["session-session-tests"].exists)
    }

    @MainActor
    func testConversationShowsSessionImages() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        tap(app.buttons["sign-in-button"])

        let session = app.descendants(matching: .any)["session-session-pr"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        tap(session)

        let image = app.buttons["conversation-image-pr-shot"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The diff is small. Waiting for you."].exists)
        XCTAssertEqual(image.label, "diff.png")
        let images = [image, app.buttons["conversation-image-pr-shot-2"], app.buttons["conversation-image-pr-shot-3"]]
        for thumbnail in images {
            XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(thumbnail.frame.minX, app.frame.minX + 19.5)
            XCTAssertLessThanOrEqual(thumbnail.frame.maxX, app.frame.maxX - 19.5)
            XCTAssertEqual(thumbnail.frame.width, thumbnail.frame.height, accuracy: 1)
        }
        XCTAssertEqual(images[0].frame.minY, images[2].frame.minY, accuracy: 1)
        let portrait = app.buttons["conversation-image-pr-user-shot"]
        XCTAssertTrue(portrait.waitForExistence(timeout: 5))
        let portraitSized = NSPredicate { _, _ in
            abs(portrait.frame.width - 165) < 1 && abs(portrait.frame.height - 220) < 1
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portraitSized, object: portrait)], timeout: 5), .completed)
        XCTAssertEqual(portrait.frame.maxX, app.frame.maxX - 20, accuracy: 1)
        attachScreen(app, name: "conversation-image")
        tap(image)

        let preview = app.descendants(matching: .any)["conversation-image-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        attachScreen(app, name: "conversation-image-preview")
        tap(app.buttons["conversation-image-close"])
        XCTAssertFalse(preview.waitForExistence(timeout: 2))
        XCTAssertTrue(image.exists)
        tap(portrait)
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        attachScreen(app, name: "conversation-portrait-preview")
        tap(app.buttons["conversation-image-close"])
        XCTAssertFalse(preview.waitForExistence(timeout: 2))
        XCTAssertEqual(portrait.frame.width, 165, accuracy: 1)
        XCTAssertEqual(portrait.frame.height, 220, accuracy: 1)
    }

    @MainActor
    private func assertMessageAboveComposer(_ message: XCUIElement, field: XCUIElement,
                                           file: StaticString = #filePath, line: UInt = #line) {
        let app = XCUIApplication()
        let hud = app.buttons["conversation-changes-hud"]
        let boundary = hud.exists ? hud : field
        // File cards belong to the message row and sit below its text.
        // A tall row may exceed the space above a multiline composer on small
        // screens. Its bottom must remain visible; require its text when it fits.
        let transcript = app.tables["conversation-transcript"]
        let row = transcript.cells
            .containing(.staticText, identifier: message.label).firstMatch
        let settled = NSPredicate { _, _ in
            row.exists && row.isHittable
                && (row.frame.height > boundary.frame.minY - transcript.frame.minY || message.isHittable)
                && row.frame.maxY <= boundary.frame.minY
                && boundary.frame.minY - row.frame.maxY < 100
        }
        let expectation = XCTNSPredicateExpectation(predicate: settled, object: message)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
        XCTAssertTrue(row.isHittable, file: file, line: line)
        if row.frame.height <= boundary.frame.minY - transcript.frame.minY {
            XCTAssertTrue(message.isHittable, file: file, line: line)
        }
        XCTAssertLessThanOrEqual(message.frame.maxY, boundary.frame.minY, file: file, line: line)
        XCTAssertLessThan(boundary.frame.minY - row.frame.maxY, 100, file: file, line: line)
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
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension ShellFlowTests {
    @MainActor
    func testAttachmentSourcesAndPrivatePhotoPicker() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-long"])
        let add = app.buttons["add-attachment"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        attachScreen(app, name: "attachment-composer")
        tap(add)
        XCTAssertTrue(app.buttons["Files"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Camera"].exists)
        XCTAssertTrue(app.buttons["Photos"].exists)
        attachScreen(app, name: "attachment-menu")
        app.buttons["Files"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        attachScreen(app, name: "attachment-files-picker")
        tap(app.buttons["Cancel"])
        tap(add)
        app.buttons["Photos"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Loading…"].waitForNonExistence(timeout: 30))
        attachScreen(app, name: "attachment-private-photos-picker")
        tap(app.buttons["Cancel"])
        tap(add)
        app.buttons["Camera"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let cameraDismiss = app.buttons["DismissButton"]
        if cameraDismiss.waitForExistence(timeout: 5) {
            XCTAssertTrue(app.buttons["PhotoCapture"].exists)
            attachScreen(app, name: "system-camera")
            tap(cameraDismiss)
        } else {
            XCTAssertTrue(app.staticTexts["Camera is unavailable on this device."].exists)
            tap(app.buttons["OK"])
        }
        XCTAssertTrue(add.waitForExistence(timeout: 5))
    }
}

extension ShellFlowTests {
    @MainActor
    func testExistingSessionPhotoComposerStaysAboveKeyboard() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Photo selection requires an isolated test simulator with sample photos.")
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-subtasks", "--fixture-tab-send"]
        app.launch()
        XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 8))
        tap(app.buttons["sign-in-button"])
        let session = app.descendants(matching: .any)["session-session-long"]
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        tap(session)
        let field = app.descendants(matching: .any)["follow-up-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        tap(field)
        field.typeText("Photo above the keyboard")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        try XCTSkipIf(!app.frame.intersects(keyboard.frame) || !keyboard.isHittable,
                      "This regression requires the simulator software keyboard to be visible.")
        let composer = app.otherElements["follow-up-composer"]
        let send = app.buttons["send-follow-up"]
        XCTAssertTrue(send.isHittable)
        let initialFrame = composer.frame

        tap(app.buttons["add-attachment"])
        tap(app.buttons["Photos"])
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Loading…"].waitForNonExistence(timeout: 30))
        let privacyBannerClose = app.buttons["Close"].firstMatch
        if privacyBannerClose.exists { tap(privacyBannerClose) }
        let photos = app.images.matching(identifier: "PXGGridLayout-Info")
        guard photos.firstMatch.waitForExistence(timeout: 30) else {
            throw XCTSkip("This device needs a test photo in the system library.")
        }
        tap(photos.element(boundBy: photos.count - 1))
        tap(app.buttons["Done"])
        let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove Photo.'")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        tap(field)
        XCTAssertTrue(keyboard.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertGreaterThan(composer.frame.height, initialFrame.height + 100)
        assertComposerAboveKeyboard(app, composer: composer, send: send)
        attachScreen(app, name: "existing-photo-above-keyboard")

        let changes = app.buttons["conversation-changes-hud"]
        if changes.frame.minY < app.navigationBars.firstMatch.frame.maxY {
            let footer = app.scrollViews.containing(.any, identifier: "follow-up-composer").firstMatch
            XCTAssertTrue(footer.exists)
            footer.swipeDown()
            XCTAssertGreaterThanOrEqual(changes.frame.minY, app.navigationBars.firstMatch.frame.maxY)
            XCTAssertTrue(changes.isHittable)
            XCTAssertTrue(app.buttons["conversation-subtasks"].isHittable)
            attachScreen(app, name: "existing-photo-oversized-footer-scrolled")
            footer.swipeUp()
            assertComposerAboveKeyboard(app, composer: composer, send: send)
        }

        verifyComposerImagePreview(app, name: "existing-photo-preview-with-keyboard")
        tap(field)
        XCTAssertTrue(keyboard.wait(for: \.isHittable, toEqual: true, timeout: 5))
        attachScreen(app, name: "existing-photo-after-preview-above-keyboard")
        assertComposerAboveKeyboard(app, composer: composer, send: send)
        XCTAssertTrue(remove.exists)
        tap(send)
        XCTAssertTrue(app.staticTexts["Photo above the keyboard"].waitForExistence(timeout: 2))
        XCTAssertTrue(remove.waitForNonExistence(timeout: 2))
        let image = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'conversation-image-' AND identifier != 'conversation-image-close'")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 2))
        XCTAssertEqual(send.label, "Sending")
        XCTAssertTrue(field.isEnabled)
        attachScreen(app, name: "existing-photo-immediately-in-bubble")
        tap(image)
        XCTAssertTrue(app.images["conversation-image-preview"].waitForExistence(timeout: 2))
        tap(app.buttons["conversation-image-close"])
        tap(field)
        field.typeText("Next photo draft")
        XCTAssertTrue(send.wait(for: \.label, toEqual: "Send", timeout: 20))
        XCTAssertEqual(field.value as? String, "Next photo draft")
        XCTAssertEqual(app.staticTexts.matching(identifier: "Photo above the keyboard").count, 1)
        attachScreen(app, name: "existing-photo-confirmed-with-next-draft")
    }

    @MainActor
    private func assertComposerAboveKeyboard(_ app: XCUIApplication, composer: XCUIElement,
                                            send: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        // AX Keyboard reports only the keys; inputView includes the candidate
        // bar and follows its height changes after presentations or refocusing.
        let inputView = app.otherElements["inputView"].firstMatch
        XCTAssertTrue(inputView.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(app.frame.intersects(inputView.frame), file: file, line: line)
        XCTAssertLessThanOrEqual(composer.frame.maxY, inputView.frame.minY + 0.5, file: file, line: line)
        XCTAssertTrue(composer.frame.contains(send.frame), file: file, line: line)
        XCTAssertTrue(send.isHittable, file: file, line: line)
    }

    @MainActor
    func testPhotoAttachmentPreviewRemovalAndSend() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Photo selection requires an isolated test simulator with sample photos.")
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
        tap(app.buttons["sign-in-button"])
        let newSession = app.buttons["new-session-local:machine-1:prism"]
        XCTAssertTrue(newSession.waitForExistence(timeout: 10))
        tap(newSession)
        let add = app.buttons["add-attachment"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        let composer = app.otherElements["new-session-composer"]
        let initialFrame = composer.frame
        for shouldSend in [false, true] {
            tap(add)
            tap(app.buttons["Photos"])
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Loading…"].waitForNonExistence(timeout: 30))
            let privacyBannerClose = app.buttons["Close"].firstMatch
            if privacyBannerClose.exists { tap(privacyBannerClose) }
            let photos = app.images.matching(identifier: "PXGGridLayout-Info")
            guard photos.firstMatch.waitForExistence(timeout: 30) else {
                throw XCTSkip("This device needs a test photo in the system library.")
            }
            // Run only on an isolated simulator whose library contains test sample photos.
            tap(photos.element(boundBy: photos.count - 1))
            tap(app.buttons["Done"])
            let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove Photo.'")).firstMatch
            XCTAssertTrue(remove.waitForExistence(timeout: 10))
            let send = app.buttons["new-session-send"]
            XCTAssertTrue(send.isEnabled)
            XCTAssertGreaterThan(composer.frame.height, initialFrame.height + 100)
            XCTAssertLessThan(composer.frame.minY, initialFrame.minY - 100)
            XCTAssertEqual(composer.frame.maxY, initialFrame.maxY, accuracy: 2)
            XCTAssertTrue(composer.frame.contains(send.frame))
            attachScreen(app, name: "photo-attachment-preview")
            verifyComposerImagePreview(app, name: "new-session-photo-full-preview")
            XCTAssertTrue(remove.exists)
            XCTAssertTrue(send.isEnabled)
            if shouldSend {
                tap(send)
                XCTAssertTrue(app.descendants(matching: .any)["follow-up-field"].waitForExistence(timeout: 10))
                XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
                XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'conversation-image-' AND identifier != 'conversation-image-close'")).firstMatch.waitForExistence(timeout: 5))
                attachScreen(app, name: "photo-attachment-only-sent")
            } else {
                tap(remove)
                XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
                XCTAssertFalse(send.isEnabled)
                XCTAssertEqual(composer.frame.maxY, initialFrame.maxY, accuracy: 2)
                attachScreen(app, name: "photo-attachment-removed")
            }
        }
        tap(add)
        tap(app.buttons["Photos"])
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Loading…"].waitForNonExistence(timeout: 30))
        let photos = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 30))
        tap(photos.element(boundBy: photos.count - 1))
        tap(app.buttons["Done"])
        let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove Photo.'")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        verifyComposerImagePreview(app, name: "follow-up-photo-full-preview")
        XCTAssertTrue(remove.exists)
        tap(remove)
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["composer-image-thumbnail"].waitForNonExistence(timeout: 5))
        attachScreen(app, name: "follow-up-photo-removed-after-preview")
    }

    @MainActor
    private func verifyComposerImagePreview(_ app: XCUIApplication, name: String) {
        let thumbnail = app.buttons["composer-image-thumbnail"].firstMatch
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
        tap(thumbnail)
        let preview = app.descendants(matching: .any)["composer-image-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.staticTexts[thumbnail.label].isHittable)
        attachScreen(app, name: name)
        let close = app.buttons["composer-image-close"]
        XCTAssertTrue(close.isHittable)
        tap(close)
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
    }
}

extension ShellFlowTests {
    @MainActor
    func testSessionContextMenuPinRenameCopyAndArchive() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
        tap(app.buttons["sign-in-button"])
        let session = app.descendants(matching: .any)["session-session-tests"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Pin"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Rename session"].exists)
        XCTAssertTrue(app.buttons["Copy Session URL"].exists)
        XCTAssertTrue(app.buttons["Archive"].exists)
        attachScreen(app, name: "Session context menu")
        tap(app.buttons["Pin"])
        XCTAssertTrue(app.staticTexts["Pinned"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "session-session-tests").count, 1)
        attachScreen(app, name: "Pinned session group")
        tap(app.buttons["more-options"])
        tap(app.buttons["By Time"])
        XCTAssertTrue(app.staticTexts["Pinned"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "session-session-tests").count, 1)
        attachScreen(app, name: "Pinned session by time")
        tap(app.buttons["more-options"])
        tap(app.buttons["By Project"])
        session.press(forDuration: 1)
        tap(app.buttons["Unpin"])
        XCTAssertTrue(app.staticTexts["Pinned"].waitForNonExistence(timeout: 5))
        session.press(forDuration: 1)
        tap(app.buttons["Rename session"])
        let title = app.alerts.textFields["Session title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        replaceSessionTitle(title, with: "Renamed fixture session")
        attachScreen(app, name: "Rename session prompt")
        tap(app.alerts.buttons["Save"])
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Renamed fixture session"), object: session
        )], timeout: 5), .completed)
        session.press(forDuration: 1)
        tap(app.buttons["Copy Session URL"])
        XCTAssertTrue(app.buttons["Copy Session URL"].waitForNonExistence(timeout: 3))
        tap(session)
        let composer = app.descendants(matching: .any)["follow-up-field"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        tap(composer)
        composer.press(forDuration: 1)
        let paste = app.menuItems["Paste"].firstMatch
        if paste.waitForExistence(timeout: 2) {
            tap(paste)
        } else {
            tap(app.buttons["Paste"].firstMatch)
        }
        let allowPaste = app.buttons["Allow Paste"]
        if allowPaste.waitForExistence(timeout: 1) { tap(allowPaste) }
        XCTAssertTrue((composer.value as? String)?.contains("/demo/sessions/session-tests") == true)
        app.navigationBars.buttons.firstMatch.tap()
        session.press(forDuration: 1)
        tap(app.buttons["Archive"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        tap(app.alerts.buttons["Cancel"])
        XCTAssertTrue(session.exists)
        session.press(forDuration: 1)
        tap(app.buttons["Archive"])
        tap(app.buttons.matching(identifier: "archive-confirm").firstMatch)
        XCTAssertTrue(session.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testDetailSessionActionsKeepConversationOpenUntilArchive() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
        tap(app.buttons["sign-in-button"])
        let session = app.descendants(matching: .any)["session-session-tests"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        tap(session)
        let options = app.buttons["session-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        tap(options)
        XCTAssertTrue(app.buttons["Pin"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Rename session"].exists)
        XCTAssertTrue(app.buttons["Copy Session URL"].exists)
        XCTAssertTrue(app.buttons["Archive"].exists)
        attachScreen(app, name: "Conversation session menu")
        tap(app.buttons["Pin"])
        XCTAssertTrue(app.descendants(matching: .any)["follow-up-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(options.exists)
        tap(options)
        XCTAssertTrue(app.buttons["Unpin"].waitForExistence(timeout: 3))
        tap(app.buttons["Copy Session URL"])
        XCTAssertTrue(options.exists)
        tap(options)
        tap(app.buttons["Rename session"])
        let title = app.alerts.textFields["Session title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        replaceSessionTitle(title, with: "Renamed in detail")
        tap(app.alerts.buttons["Save"])
        XCTAssertTrue(app.staticTexts["Renamed in detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(options.exists)
        attachScreen(app, name: "Renamed conversation title")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pinned"].waitForExistence(timeout: 5))
        tap(session)
        tap(options)
        tap(app.buttons["Archive"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        attachScreen(app, name: "Conversation archive confirmation")
        tap(app.buttons.matching(identifier: "archive-confirm").firstMatch)
        XCTAssertTrue(app.buttons["more-options"].waitForExistence(timeout: 5))
        XCTAssertTrue(session.waitForNonExistence(timeout: 5))
    }
}


extension ShellFlowTests {
    @MainActor
    private func replaceSessionTitle(_ field: XCUIElement, with title: String) {
        // The alert focuses the initial title. Keep that selection/caret position;
        // tapping long text can move the caret into the middle at accessibility sizes.
        let count = (field.value as? String)?.count ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        field.typeText(title)
        XCTAssertEqual(field.value as? String, title)
    }
}

extension ShellFlowTests {
    @MainActor
    func testQuestionAnswersPreserveDraftsAndSubmit() {
        let app = openQuestionFixture()
        let card = app.descendants(matching: .any)["question-card"].firstMatch
        let reply = app.descendants(matching: .any)["question-reply"].firstMatch
        let next = app.buttons["question-next"]
        XCTAssertFalse(next.isEnabled)
        attachScreen(app, name: "Question first page")
        tap(reply)
        reply.typeText("Review the question demo session")
        XCTAssertTrue(next.isEnabled)
        XCTAssertTrue(next.isHittable)
        attachScreen(app, name: "Question focused draft")
        tap(next)
        let codeDiff = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Code diff")).firstMatch
        XCTAssertTrue(codeDiff.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["question-send"].isEnabled)
        tap(codeDiff)
        XCTAssertTrue(codeDiff.isSelected)
        XCTAssertTrue(app.buttons["question-send"].isEnabled)
        attachScreen(app, name: "Question selected choice")
        tap(app.buttons["question-previous"])
        XCTAssertEqual(reply.value as? String, "Review the question demo session")
        tap(next)
        XCTAssertTrue(codeDiff.isSelected)
        tap(app.buttons["question-send"])
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Answer received."].waitForExistence(timeout: 5))
        attachScreen(app, name: "Question answer delivered")
    }

    @MainActor
    func testQuestionSkipAndCloseResolveRequest() {
        for action in ["question-skip", "question-close"] {
            let app = openQuestionFixture()
            tap(app.buttons[action])
            XCTAssertTrue(app.descendants(matching: .any)["question-card"].firstMatch.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Question skipped."].waitForExistence(timeout: 5))
            attachScreen(app, name: "Question resolved by \(action)")
            app.terminate()
        }
    }

    @MainActor
    private func openQuestionFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-questions"]
        app.launch()
        XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
        tap(app.buttons["sign-in-button"])
        let session = app.descendants(matching: .any)["session-session-question"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        tap(session)
        XCTAssertTrue(app.descendants(matching: .any)["question-card"].firstMatch.waitForExistence(timeout: 5))
        return app
    }
}
