import XCTest

final class ShellFlowTests: XCTestCase {
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
        attachScreen(app, name: "conversation-image")
        tap(image)

        let preview = app.descendants(matching: .any)["conversation-image-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        attachScreen(app, name: "conversation-image-preview")
        tap(app.buttons["conversation-image-close"])
        XCTAssertFalse(preview.waitForExistence(timeout: 2))
        XCTAssertTrue(image.exists)
    }

    @MainActor
    private func assertMessageAboveComposer(_ message: XCUIElement, field: XCUIElement,
                                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(message.isHittable, file: file, line: line)
        XCTAssertLessThanOrEqual(message.frame.maxY, field.frame.minY, file: file, line: line)
        XCTAssertLessThan(field.frame.minY - message.frame.maxY, 100, file: file, line: line)
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
