import XCTest

final class ShellFlowTests: XCTestCase {
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
        XCTAssertTrue(app.buttons["turn-changes-toggle-long-agent-20"].isHittable)
        attachScreen(app, name: "Parent subtask summary")
        tap(subtasks)
        let reuse = app.buttons["subtask-review-reuse"]
        XCTAssertTrue(reuse.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["subtask-review-quality"].exists)
        attachScreen(app, name: "Subtasks with states")
        tap(reuse)
        XCTAssertTrue(app.staticTexts["Reuse review finished."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Read-only conversation"].exists)
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
        let scope = app.buttons["file-changes-title"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertEqual(scope.label, "Last turn")
        tap(scope)
        tap(app.buttons["All turns"])
        XCTAssertTrue(scope.wait(for: \.label, toEqual: "All turns", timeout: 5))
        XCTAssertTrue(app.staticTexts["Turn 20"].exists)
        tap(scope)
        tap(app.buttons["Last turn"])
        XCTAssertTrue(scope.wait(for: \.label, toEqual: "Last turn", timeout: 5))
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
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(file.isHittable)
        XCTAssertEqual(file.value as? String, "Collapsed")
        tap(file)
        XCTAssertEqual(file.value as? String, "Expanded")
        let changedLine = app.staticTexts["    let showsChanges = true"]
        XCTAssertTrue(changedLine.waitForExistence(timeout: 5))
        for _ in 0..<4 where !changedLine.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(changedLine.isHittable)
        let diffCapture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        diffCapture.name = "Recorded code difference"
        diffCapture.lifetime = .keepAlways
        add(diffCapture)
        tap(app.buttons["close-file-changes"])
        XCTAssertEqual(field.value as? String, "Keep this draft")
    }

    @MainActor
    func testRetryClearsConfirmedDraftAndPreservesEditedDraft() {
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
            let retry = app.buttons["Retry earlier message"]
            XCTAssertTrue(retry.waitForExistence(timeout: 5))
            XCTAssertEqual(field.value as? String, "Retry this message")
            if editDraft { tap(field); field.typeText(" edited") }
            tap(retry)
            XCTAssertTrue(retry.waitForNonExistence(timeout: 5))
            XCTAssertEqual(field.value as? String, editDraft ? "Retry this message edited" : "Send a follow-up")
            XCTAssertEqual(app.staticTexts.matching(identifier: "Retry this message").count, 1)
            app.terminate()
        }
    }

    @MainActor
    func testUnconfirmedSendRestoresAfterReopeningConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-send-unconfirmed"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-tests"])
        let field = app.descendants(matching: .any)["follow-up-field"]
        tap(field)
        field.typeText("Restore this message")
        tap(app.buttons["send-follow-up"])
        let retry = app.buttons["Retry earlier message"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))

        app.navigationBars.buttons.firstMatch.tap()
        tap(app.descendants(matching: .any)["session-session-long"])
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Send a follow-up")
        XCTAssertFalse(retry.exists)
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.descendants(matching: .any)["session-session-tests"])
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Restore this message")

        tap(field)
        field.typeText(" edited")
        let editedDraft = field.value as? String
        XCTAssertTrue(editedDraft?.contains(" edited") == true)
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
        XCTAssertEqual(field.value as? String, "Send a follow-up")
    }

    @MainActor
    func testLatestTurnWithoutChangesShowsEmptyScope() {
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
        XCTAssertTrue(app.staticTexts["No recorded changes"].waitForExistence(timeout: 5))
        attachScreen(app, name: "Latest turn has no changes")
        tap(app.buttons["file-changes-title"])
        tap(app.buttons["All turns"])
        XCTAssertTrue(app.staticTexts["Turn 20"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSendShowsBubbleBeforeDeliveryAndKeepsOneTurn() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-slow-send"]
        app.launch()
        tap(app.buttons["sign-in-button"])
        tap(app.descendants(matching: .any)["session-session-tests"])

        let field = app.descendants(matching: .any)["follow-up-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        tap(field)
        field.typeText("Instant bubble")
        let send = app.buttons["send-follow-up"]
        tap(send)

        XCTAssertTrue(send.wait(for: \.label, toEqual: "Sending", timeout: 2))
        let message = app.staticTexts["Instant bubble"]
        XCTAssertTrue(message.waitForExistence(timeout: 2))
        XCTAssertEqual(field.value as? String, "Send a follow-up")
        XCTAssertFalse(app.staticTexts["Sending…"].exists)
        attachScreen(app, name: "optimistic-send")
        XCTAssertTrue(send.wait(for: \.label, toEqual: "Send", timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.descendants(matching: .any)["session-session-tests"])
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Instant bubble").count, 1)
    }

    @MainActor
    func testSessionListModesAndMoreMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        let connect = app.buttons["sign-in-button"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        tap(connect)

        let projectHeading = app.staticTexts["kurage"]
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

        tap(more)
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 2))
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
    func testSignInOpenSessionAllowAndSend() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()

        let connect = app.buttons["sign-in-button"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["See running sessions when you step away."].exists)
        XCTAssertEqual(connect.label, "Connect Lody Cloud")
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
        tap(field)
        field.typeText("look again")

        let pause = app.buttons["pause-session"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertEqual(pause.label, "Stop reply")
        // Fixture supports sending while running; stopping remains independently available.
        let runningSend = app.buttons["send-follow-up"]
        XCTAssertTrue(runningSend.waitForExistence(timeout: 5))
        XCTAssertTrue(runningSend.isEnabled)
        attachScreen(app, name: "running-send-and-stop")
        tap(runningSend)
        XCTAssertTrue(app.staticTexts["look again"].waitForExistence(timeout: 5))
        XCTAssertTrue(pause.exists)
        XCTAssertEqual(field.value as? String, "Send a follow-up")
        tap(field)
        field.typeText("continue after stopping")
        tap(pause)
        XCTAssertTrue(app.buttons["send-follow-up"].waitForExistence(timeout: 5))
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
        XCTAssertLessThan(context.frame.maxX, menu.frame.minX)
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
    func testKeyboardAndMultilineComposerKeepLatestMessageVisible() {
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
        let sent = app.staticTexts["First line\nSecond line\nThird line\nFourth line\nFifth line"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        XCTAssertTrue(sent.wait(for: \.frame.isEmpty, toEqual: false, timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertGreaterThan(sent.frame.height, 70)
        XCTAssertGreaterThan(sent.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(sent.frame.maxY, field.frame.minY)
        attachScreen(app, name: "multiline-sent")
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
            NSPredicate(format: "identifier BEGINSWITH 'session-session-new-'")
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
        let retry = app.buttons["new-session-retry-start"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["new-session-retry"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["new-session-retry"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["kurage"].exists)
        XCTAssertFalse(app.staticTexts["prism"].exists)
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
        XCTAssertTrue(alert.staticTexts["This removes the task from the remote task list."].exists)
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
    func testPhotoAttachmentPreviewRemovalAndSend() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Photo selection requires an isolated test simulator with sample photos.")
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
        tap(app.buttons["sign-in-button"])
        tap(app.buttons["new-session-local:machine-1:prism"])
        let add = app.buttons["add-attachment"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
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
            attachScreen(app, name: "photo-attachment-preview")
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
                attachScreen(app, name: "photo-attachment-removed")
            }
        }
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
        tap(app.alerts.buttons["Archive"])
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
        tap(app.alerts.buttons["Archive"])
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
