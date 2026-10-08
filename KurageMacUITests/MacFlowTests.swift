import XCTest
import AppKit

@MainActor
final class MacFlowTests: XCTestCase {
    func testSidebarSearchAndNewSession() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        app.activate()
        let newSession = app.buttons["new-session"]
        let search = app.buttons["session-search"]
        let longSession = app.staticTexts["session-session-long"].firstMatch
        let reviewSession = app.staticTexts["session-session-pr"].firstMatch
        XCTAssertTrue(longSession.waitForExistence(timeout: 15))
        XCTAssertTrue(newSession.exists)
        XCTAssertTrue(search.exists)
        XCTAssertTrue(search.label.contains("Search sessions"))
        XCTAssertFalse(app.staticTexts["codex"].exists)
        XCTAssertFalse(app.staticTexts["claude"].exists)
        try await capture(app, name: "mac-sidebar-initial")
        XCTAssertGreaterThan(search.frame.minY, newSession.frame.maxY)
        XCTAssertEqual(search.frame.minX, newSession.frame.minX, accuracy: 2)
        XCTAssertFalse(app.toolbars.descendants(matching: .any)["new-session"].exists)
        XCTAssertFalse(app.toolbars.descendants(matching: .any)["session-search"].exists)
        XCTAssertFalse(app.buttons["Refresh"].exists)
        let workspace = app.menuButtons["workspace-menu"]
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(workspace.exists)
        XCTAssertTrue(settingsButton.exists)
        XCTAssertFalse(app.windows["Settings"].exists)
        XCTAssertEqual(workspace.frame.minX, newSession.frame.minX, accuracy: 2)
        XCTAssertEqual(workspace.frame.midY, settingsButton.frame.midY, accuracy: 2)
        XCTAssertLessThan(workspace.frame.maxX, settingsButton.frame.minX)
        XCTAssertLessThan(app.windows.firstMatch.frame.maxY - workspace.frame.maxY, 30)
        XCTAssertFalse(app.staticTexts["demo@kurage.app"].exists)
        let workspaceY = workspace.frame.minY
        app.activate()
        longSession.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(app.textViews["message-editor"].waitForExistence(timeout: 10))
        try await capture(app, name: "mac-sidebar-controls")

        search.click()
        let field = app.textFields["session-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["session-search-heading"].waitForExistence(timeout: 5))
        paste("Question 7", into: field, app: app)
        let longResult = app.buttons["session-search-result-session-long"]
        XCTAssertTrue(longResult.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["session-search-result-session-pr"].exists)
        app.buttons["clear-session-search"].click()
        XCTAssertEqual(field.value as? String, "")
        paste("PrIsM", into: field, app: app)
        let reviewResult = app.buttons["session-search-result-session-pr"]
        XCTAssertTrue(reviewResult.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["session-search-result-session-long"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(longSession.exists)
        try await capture(app, name: "mac-sidebar-search")
        reviewResult.click()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Look at this PR"].firstMatch.waitForExistence(timeout: 10))
        search.click()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        paste("no-matching-session-xyz", into: field, app: app)
        XCTAssertTrue(app.staticTexts["session-search-empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["session-search-result-session-pr"].exists)
        XCTAssertTrue(reviewSession.exists)
        XCTAssertEqual(workspace.frame.minY, workspaceY, accuracy: 2)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        workspace.click()
        XCTAssertTrue(app.menuItems["Demo"].waitForExistence(timeout: 5))
        let menuAttachment = XCTAttachment(screenshot: app.menuItems["Demo"].screenshot())
        menuAttachment.name = "mac-sidebar-workspace-menu"
        menuAttachment.lifetime = .keepAlways
        add(menuAttachment)
        app.typeKey(.escape, modifierFlags: [])
        newSession.click()
        XCTAssertTrue(app.textViews["new-message"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.popUpButtons["new-model"].waitForExistence(timeout: 10))
        try await capture(app, name: "mac-new-session-empty")
        app.menuButtons["new-project"].click()
        XCTAssertTrue(app.menuItems["kurage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["prism"].exists)
        try await capture(app, name: "mac-new-project-menu")
        app.menuItems["kurage"].click()
        XCTAssertTrue(app.textViews["new-message"].waitForExistence(timeout: 10))
        dismissNewSessionByScrim(app)
        XCTAssertTrue(longSession.waitForExistence(timeout: 5))
        XCTAssertTrue(reviewSession.exists)
        XCTAssertFalse(app.textFields["session-search-field"].exists)
    }

    func testNewTabRequiresSessionCreationCapability() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-no-session-creation"]
        app.launch()
        app.activate()
        let session = app.staticTexts["session-session-long"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        let header = app.buttons["project-header-local:machine-1:kurage"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["new-session-local:machine-1:kurage"].exists)
        header.click()
        XCTAssertTrue(session.waitForNonExistence(timeout: 5))
        XCTAssertEqual(header.value as? String, "Collapsed")
        header.click()
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.click()
        let newTab = app.buttons["new-tab"]
        XCTAssertTrue(newTab.waitForExistence(timeout: 10))
        XCTAssertFalse(newTab.isEnabled)
        XCTAssertFalse(app.textViews["new-message"].exists)
    }

    func testProjectHeadersCollapseAndOpenNewSession() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        app.activate()
        let kurage = app.buttons["project-header-local:machine-1:kurage"]
        let prism = app.buttons["project-header-local:machine-1:prism"]
        let longSession = app.staticTexts["session-session-long"].firstMatch
        let reviewSession = app.staticTexts["session-session-pr"].firstMatch
        XCTAssertTrue(kurage.waitForExistence(timeout: 15))
        XCTAssertTrue(prism.waitForExistence(timeout: 5))
        XCTAssertEqual(kurage.value as? String, "Expanded")
        XCTAssertTrue(longSession.waitForExistence(timeout: 5))
        let newSession = app.buttons["new-session"]
        // Folder icons share the New Session icon's left edge.
        XCTAssertEqual(kurage.frame.minX, newSession.frame.minX, accuracy: 2)
        // Session titles line up with the project name, after the 16pt icon and 6pt gap.
        XCTAssertEqual(longSession.frame.minX - kurage.frame.minX, 22, accuracy: 2)
        let newKurage = app.buttons["new-session-local:machine-1:kurage"]
        let newPrism = app.buttons["new-session-local:machine-1:prism"]
        XCTAssertTrue(newKurage.exists)
        XCTAssertTrue(newPrism.exists)
        XCTAssertGreaterThan(newKurage.frame.minX, kurage.frame.maxX - 8)
        XCTAssertEqual(newKurage.frame.midY, kurage.frame.midY, accuracy: 4)
        XCTAssertEqual(newPrism.frame.midY, prism.frame.midY, accuracy: 4)
        let sidebar = app.outlines.firstMatch.exists ? app.outlines.firstMatch : app.tables.firstMatch
        XCTAssertTrue(sidebar.exists)
        XCTAssertGreaterThan(newKurage.frame.midX, sidebar.frame.midX)
        XCTAssertGreaterThan(newPrism.frame.midX, sidebar.frame.midX)
        XCTAssertEqual(newKurage.frame.maxX, newPrism.frame.maxX, accuracy: 2)
        XCTAssertLessThan(sidebar.frame.maxX - newKurage.frame.maxX, 40)
        try await capture(app, name: "mac-project-headers")

        kurage.click()
        XCTAssertEqual(kurage.value as? String, "Collapsed")
        XCTAssertTrue(longSession.waitForNonExistence(timeout: 5))
        XCTAssertTrue(reviewSession.exists)
        try await capture(app, name: "mac-project-collapsed")
        kurage.click()
        XCTAssertEqual(kurage.value as? String, "Expanded")
        XCTAssertTrue(longSession.waitForExistence(timeout: 5))

        prism.click()
        XCTAssertTrue(reviewSession.waitForNonExistence(timeout: 5))
        app.buttons["session-search"].click()
        let field = app.textFields["session-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        paste("PrIsM", into: field, app: app)
        let reviewResult = app.buttons["session-search-result-session-pr"]
        XCTAssertTrue(reviewResult.waitForExistence(timeout: 5))
        XCTAssertTrue(reviewSession.waitForNonExistence(timeout: 2))
        XCTAssertEqual(prism.value as? String, "Collapsed")
        reviewResult.click()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Expanded"), object: prism)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        XCTAssertTrue(reviewSession.waitForExistence(timeout: 5))

        newPrism.click()
        XCTAssertTrue(app.textViews["new-message"].waitForExistence(timeout: 10))
        let project = app.menuButtons["new-project"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        XCTAssertEqual(project.title, "prism")
        try await capture(app, name: "mac-project-new-session")
        dismissNewSessionByScrim(app)
    }

    func testReadReceiptRetriesTransientFailures() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-read-retry"]
        app.launch()
        app.activate()
        let session = app.staticTexts["session-session-long"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        XCTAssertEqual(session.value as? String, "Unread")
        session.click()
        XCTAssertTrue(app.textViews["message-editor"].waitForExistence(timeout: 10))
        let read = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Read"), object: session)
        XCTAssertEqual(XCTWaiter.wait(for: [read], timeout: 10), .completed)
    }

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
        XCTAssertTrue(app.buttons["new-session"].waitForExistence(timeout: 15))
        try await capture(app, name: "mac-sidebar-initial-dark")
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.menuButtons["new-project"].waitForExistence(timeout: 5))
        app.menuButtons["new-project"].click()
        app.menuItems["kurage"].click()
        let editor = app.textViews["new-message"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let model = app.popUpButtons["new-model"]
        XCTAssertTrue(model.waitForExistence(timeout: 10))
        let agent = app.popUpButtons["new-agent"]
        for name in ["Claude Code", "Codex", "Codex"] {
            agent.click()
            app.menuItems[name].click()
            XCTAssertTrue(model.waitForExistence(timeout: 10))
        }
        model.click()
        app.menuItems["gpt-5.4-mini"].click()
        XCTAssertTrue((model.value as? String ?? "").contains("gpt-5.4-mini"))
        paste("Mac root integration", into: editor, app: app)
        try await capture(app, name: "mac-new-root-dark")
        editor.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Mac root integration"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textViews["message-editor"].waitForExistence(timeout: 10))
        try await capture(app, name: "mac-conversation-dark")
        app.buttons["Settings"].click()
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-nav-account"].waitForExistence(timeout: 5))
        app.buttons["settings-nav-account"].click()
        XCTAssertTrue(app.buttons["sign-out-button"].waitForExistence(timeout: 5))
        app.buttons["sign-out-button"].click()
        XCTAssertTrue(app.sheets.buttons["Sign out"].waitForExistence(timeout: 5))
        app.sheets.buttons["Sign out"].click()
        XCTAssertTrue(app.buttons["Sign in with Lody"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.windows["Settings"].waitForNonExistence(timeout: 5))
        try await capture(app, name: "mac-sign-in")
    }

    func testSettingsAppearanceAndAccount() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.windows["Settings"].exists)
        app.buttons["open-settings"].click()
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 5))
        let light = app.buttons["appearance-theme-light"]
        let dark = app.buttons["appearance-theme-dark"]
        let system = app.buttons["appearance-theme-system"]
        XCTAssertTrue(system.waitForExistence(timeout: 5))
        light.click()
        XCTAssertTrue(light.wait(for: \.isSelected, toEqual: true, timeout: 5))
        try await captureWindow(app.windows["Settings"], name: "mac-settings-general-light")
        try await captureWindow(app.windows["Kurage"], name: "mac-main-theme-light")
        dark.click()
        XCTAssertTrue(dark.wait(for: \.isSelected, toEqual: true, timeout: 5))
        XCTAssertFalse(light.isSelected)
        try await captureWindow(app.windows["Settings"], name: "mac-settings-general-dark")
        try await captureWindow(app.windows["Kurage"], name: "mac-main-theme-dark")
        app.buttons["settings-nav-account"].click()
        XCTAssertTrue(app.staticTexts["demo@kurage.app"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sign-out-button"].exists)
        XCTAssertFalse(app.windows["Kurage"].staticTexts["demo@kurage.app"].exists)
        try await captureWindow(app.windows["Settings"], name: "mac-settings-account")

        app.terminate()
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 15))
        app.buttons["open-settings"].click()
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appearance-theme-dark"].wait(for: \.isSelected, toEqual: true, timeout: 5))
        app.buttons["appearance-theme-system"].click()
        XCTAssertTrue(app.buttons["appearance-theme-system"].wait(for: \.isSelected, toEqual: true, timeout: 5))
        try await captureWindow(app.windows["Settings"], name: "mac-settings-general-system")
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

    func testPastedAttachmentsAndProjectSwitchPreserveDraft() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["new-session"].waitForExistence(timeout: 15))
        app.buttons["new-session"].click()
        let editor = app.textViews["new-message"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        paste("Check these attachments", into: editor, app: app)
        editor.typeKey(.return, modifierFlags: [])
        editor.typeText("Second line")
        let draft = "Check these attachments\nSecond line"
        XCTAssertEqual(editor.value as? String, draft)

        let image = NSImage(size: NSSize(width: 160, height: 100), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 40, dy: 20)).fill()
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        withPasteboard { pasteboard in
            pasteboard.setData(tiff, forType: .tiff)
            editor.typeKey("v", modifierFlags: .command)
            XCTAssertTrue(app.buttons["Remove Pasted image.jpg"].waitForExistence(timeout: 10))
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("paste-\(UUID()).txt")
        try Data("File attachment contents".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        withPasteboard { pasteboard in
            pasteboard.writeObjects([file as NSURL])
            editor.typeKey("v", modifierFlags: .command)
            XCTAssertTrue(app.buttons["Remove \(file.lastPathComponent)"].waitForExistence(timeout: 10))
        }
        app.menuButtons["new-project"].click()
        app.menuItems["prism"].click()
        XCTAssertEqual(editor.value as? String, draft)
        XCTAssertTrue(app.buttons["Remove Pasted image.jpg"].exists)
        XCTAssertTrue(app.buttons["Remove \(file.lastPathComponent)"].exists)
        XCTAssertTrue(app.popUpButtons["new-model"].waitForExistence(timeout: 10))
        try await capture(app, name: "mac-new-session-attachments")
        app.buttons["start-session"].click()
        XCTAssertTrue(app.textViews["message-editor"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[file.lastPathComponent].firstMatch.waitForExistence(timeout: 10))
        let composer = app.textViews["message-editor"]
        composer.click()
        withPasteboard { pasteboard in
            pasteboard.setData(tiff, forType: .tiff)
            composer.typeKey("v", modifierFlags: .command)
            XCTAssertTrue(app.buttons["Remove Pasted image.jpg"].waitForExistence(timeout: 10))
        }
        XCTAssertEqual(composer.value as? String, "")
        XCTAssertTrue(app.buttons["send-message"].isEnabled)
        try await capture(app, name: "mac-composer-pasted-image")
        app.buttons["Remove Pasted image.jpg"].click()
        XCTAssertFalse(app.buttons["send-message"].isEnabled)
    }

    func testRejectedMessageEditingProtectsNewDraftAndAllowsSendingAgain() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-send-not-delivered"]
        app.launch()
        app.activate()
        let session = app.staticTexts["session-session-long"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        session.click()
        let editor = app.textViews["message-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        paste("Rejected message", into: editor, app: app)
        app.buttons["send-message"].click()
        let edit = app.buttons["edit-failed-message"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["send-message"].isEnabled)
        paste("Newer draft", into: editor, app: app)
        edit.click()
        XCTAssertTrue(app.sheets.buttons["Replace draft"].waitForExistence(timeout: 5))
        app.sheets.buttons["Cancel"].click()
        XCTAssertEqual(editor.value as? String, "Newer draft")
        edit.click()
        app.sheets.buttons["Replace draft"].click()
        XCTAssertEqual(editor.value as? String, "Rejected message")
        XCTAssertTrue(app.buttons["send-message"].isEnabled)
        try await capture(app, name: "mac-recovered-message")
        app.buttons["send-message"].click()
        XCTAssertTrue(edit.waitForNonExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "")
    }

    func testPendingRootCanBeReopenedAndRetriedFromSidebar() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-start-unconfirmed"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["new-session"].waitForExistence(timeout: 15))
        app.buttons["new-session"].click()
        let editor = app.textViews["new-message"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(app.popUpButtons["new-model"].waitForExistence(timeout: 10))
        paste("Recover pending root", into: editor, app: app)
        app.buttons["start-session"].click()
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["edit-failed-message"].exists)
        let other = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session-")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 10))
        other.click()
        let pending = app.menuButtons["pending-sessions"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        pending.click()
        app.menuItems["Recover pending root"].click()
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 10))
        try await capture(app, name: "mac-pending-session-reopened")
        app.buttons["Retry"].click()
        XCTAssertTrue(pending.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Recover pending root"].firstMatch.waitForExistence(timeout: 10))
    }

    func testRejectedRootReturnsToCreationEditor() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-start-rejected"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["new-session"].waitForExistence(timeout: 15))
        app.buttons["new-session"].click()
        let editor = app.textViews["new-message"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(app.popUpButtons["new-model"].waitForExistence(timeout: 10))
        app.popUpButtons["new-model"].click()
        app.menuItems["gpt-5.4-mini"].click()
        paste("Edit rejected first turn", into: editor, app: app)
        app.buttons["start-session"].click()
        XCTAssertTrue(app.buttons["edit-failed-message"].waitForExistence(timeout: 15))
        app.buttons["edit-failed-message"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "Edit rejected first turn")
        XCTAssertTrue(app.popUpButtons["new-model"].waitForExistence(timeout: 10))
        XCTAssertTrue((app.popUpButtons["new-model"].value as? String ?? "").contains("gpt-5.4-mini"))
        try await capture(app, name: "mac-recovered-first-turn")
        app.buttons["start-session"].click()
        XCTAssertTrue(app.textViews["message-editor"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.menuButtons["pending-sessions"].waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.buttons["edit-failed-message"].exists)
    }

    func testDelayedImageFollowsBottom() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-slow-images"]
        app.launch()
        app.activate()
        let session = app.staticTexts["session-session-long"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        session.click()
        let end = app.staticTexts["After delayed image"].firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["delayed.png"].firstMatch.waitForExistence(timeout: 15))
        try await capture(app, name: "mac-delayed-image-follow")
        XCTAssertLessThanOrEqual(end.frame.maxY, app.scrollViews["transcript"].frame.maxY)
        XCTAssertGreaterThanOrEqual(end.frame.minY, app.scrollViews["transcript"].frame.minY)
        XCTAssertFalse(app.buttons["scroll-latest"].exists)
    }

    func testRemovedAgentCanRecoverWithDefaultAgent() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-agent-removed"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["new-session"].waitForExistence(timeout: 15))
        app.buttons["new-session"].click()
        let editor = app.textViews["new-message"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(app.popUpButtons["new-agent"].waitForExistence(timeout: 10))
        app.popUpButtons["new-agent"].click()
        app.menuItems["Claude Code"].click()
        XCTAssertTrue(app.popUpButtons["new-model"].waitForExistence(timeout: 10))
        paste("Recover removed agent", into: editor, app: app)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("recovery-\(UUID()).txt")
        try Data("Keep this attachment".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        withPasteboard { pasteboard in
            pasteboard.writeObjects([file as NSURL])
            editor.typeKey("v", modifierFlags: .command)
        }
        let attachment = app.buttons["Remove \(file.lastPathComponent)"]
        XCTAssertTrue(attachment.waitForExistence(timeout: 10))
        app.buttons["start-session"].click()
        XCTAssertTrue(app.buttons["edit-failed-message"].waitForExistence(timeout: 15))
        app.buttons["edit-failed-message"].click()
        let fallback = app.buttons["use-default-agent"]
        XCTAssertTrue(fallback.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "Recover removed agent")
        XCTAssertTrue(attachment.exists)
        XCTAssertFalse(app.buttons["start-session"].isEnabled)
        app.buttons["Retry"].click()
        XCTAssertTrue(fallback.waitForExistence(timeout: 10))
        try await capture(app, name: "mac-removed-agent-recovery")
        fallback.click()
        XCTAssertTrue(app.popUpButtons["new-agent"].waitForExistence(timeout: 10))
        XCTAssertTrue((app.popUpButtons["new-agent"].value as? String ?? "").contains("Codex"))
        XCTAssertEqual(editor.value as? String, "Recover removed agent")
        XCTAssertTrue(attachment.exists)
        XCTAssertTrue(app.buttons["start-session"].isEnabled)
        app.buttons["start-session"].click()
        XCTAssertTrue(app.textViews["message-editor"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[file.lastPathComponent].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["edit-failed-message"].exists)
    }

    func testActivityGroupRevealsToolTitles() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture"]
        app.launch()
        app.activate()
        let session = app.staticTexts["session-session-long"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        session.click()
        let work = app.disclosureTriangles.matching(NSPredicate(format: "label BEGINSWITH %@", "Worked for")).firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10))
        work.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 26, dy: 8)).click()
        let activity = app.disclosureTriangles.matching(NSPredicate(format: "label CONTAINS %@", "Ran 2 commands")).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["git status --short"].exists)
        activity.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 26, dy: 8)).click()
        for title in ["git status --short", "Read ConversationView.swift", "xcodebuild test"] {
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5))
        }
        // An unrelated parent update must not reset the disclosure state.
        app.buttons["toggle-changes"].click()
        XCTAssertTrue(app.staticTexts["git status --short"].exists)
        app.buttons["toggle-changes"].click()
        if app.buttons["scroll-latest"].exists { app.buttons["scroll-latest"].click() }
        try await capture(app, name: "mac-activity-tool-titles")
        activity.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 26, dy: 8)).click()
        XCTAssertTrue(app.staticTexts["git status --short"].waitForNonExistence(timeout: 5))
    }

    func testFullImageFailureCanBeRetried() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-image-failure"]
        app.launch()
        app.activate()
        let session = app.staticTexts["session-session-pr"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        session.click()
        let image = app.buttons["result.png"].firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        let thumbnailWidth = image.frame.width
        image.click()
        let retry = app.buttons["Retry full image"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(image.exists)
        XCTAssertEqual(image.frame.width, thumbnailWidth, accuracy: 1)
        try await capture(app, name: "mac-original-image-failed")
        retry.click()
        XCTAssertTrue(retry.waitForNonExistence(timeout: 10))
        XCTAssertTrue(image.exists)
        XCTAssertGreaterThan(image.frame.width, thumbnailWidth)
    }

    func testQuestionAnswerAndSkip() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture", "--fixture-questions"]
        app.launch()
        app.activate()
        let session = app.staticTexts["session-session-question"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        session.click()
        let reply = app.textFields["question-reply"].firstMatch
        let multilineReply = app.textViews["question-reply"].firstMatch
        XCTAssertTrue(app.buttons["question-next"].waitForExistence(timeout: 10))
        let input = reply.exists ? reply : multilineReply
        paste("Review PR 48", into: input, app: app)
        app.buttons["question-next"].click()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Code diff")).firstMatch.click()
        app.buttons["question-previous"].click()
        XCTAssertEqual(input.value as? String, "Review PR 48")
        app.buttons["question-next"].click()
        try await capture(app, name: "mac-question-answer")
        app.buttons["question-send"].click()
        XCTAssertTrue(app.buttons["question-send"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Answer received."].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments += ["--fixture-dark"]
        app.launch()
        app.activate()
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        session.click()
        XCTAssertTrue(app.buttons["question-skip"].waitForExistence(timeout: 10))
        try await capture(app, name: "mac-question-skip-dark")
        app.buttons["question-skip"].click()
        XCTAssertTrue(app.buttons["question-skip"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Question skipped."].firstMatch.waitForExistence(timeout: 10))
    }

    private func paste(_ text: String, into editor: XCUIElement, app: XCUIApplication) {
        withPasteboard { pasteboard in
            pasteboard.setString(text, forType: .string)
            app.activate()
            editor.click()
            editor.typeKey("v", modifierFlags: .command)
            XCTAssertEqual(editor.value as? String, text)
        }
    }

    private func withPasteboard(_ body: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        pasteboard.clearContents()
        body(pasteboard)
        pasteboard.clearContents()
        pasteboard.writeObjects(saved)
    }

    private func dismissNewSessionByScrim(_ app: XCUIApplication) {
        let message = app.textViews["new-message"]
        XCTAssertTrue(message.exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)
        let window = app.windows.allElementsBoundByIndex.max { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        } ?? app.windows.firstMatch
        // Left edge of the dimmed sidebar, beside the centered card.
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 18, dy: window.frame.height * 0.55))
            .click()
        XCTAssertTrue(message.waitForNonExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, name: String) async throws {
        app.activate()
        try await Task.sleep(for: .milliseconds(300))
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureWindow(_ window: XCUIElement, name: String) async throws {
        XCTAssertTrue(window.exists)
        try await Task.sleep(for: .milliseconds(300))
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
