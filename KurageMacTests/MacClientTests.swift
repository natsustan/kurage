import AppKit
import Foundation
import Testing
import Synchronization
import WebKit
@testable import KurageCore
@testable import KurageMac

@MainActor
struct MacClientTests {
    @Test func titlebarRestoresHostStateWhenMovingBetweenWindows() throws {
        let first = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let second = NSWindow(contentRect: first.frame, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        first.titlebarAppearsTransparent = false
        first.titlebarSeparatorStyle = .shadow
        second.titlebarAppearsTransparent = true
        second.titlebarSeparatorStyle = .line
        let titlebar = try #require(first.standardWindowButton(.closeButton)?.superview)
        let visibleFill = NSVisualEffectView(frame: titlebar.bounds)
        let hiddenFill = NSVisualEffectView(frame: titlebar.bounds)
        hiddenFill.isHidden = true
        titlebar.addSubview(visibleFill)
        titlebar.addSubview(hiddenFill)
        let bridge = MacTitlebarSplitView(frame: .zero)
        defer { bridge.removeFromSuperview() }

        try #require(first.contentView).addSubview(bridge)
        #expect(first.titlebarAppearsTransparent)
        #expect(first.titlebarSeparatorStyle == .none)
        #expect(visibleFill.isHidden)
        #expect(hiddenFill.isHidden)
        bridge.needsLayout = true
        bridge.layoutSubtreeIfNeeded()

        try #require(second.contentView).addSubview(bridge)
        #expect(!first.titlebarAppearsTransparent)
        #expect(first.titlebarSeparatorStyle == .shadow)
        #expect(!visibleFill.isHidden)
        #expect(hiddenFill.isHidden)
        #expect(second.titlebarSeparatorStyle == .none)
        bridge.removeFromSuperview()
        #expect(second.titlebarAppearsTransparent)
        #expect(second.titlebarSeparatorStyle == .line)
    }

    @Test func transcriptLayoutRecoveryPreservesFollowIntentAcrossRepeatedLayoutChanges() throws {
        var recovery = MacTranscriptLayoutRecovery()
        recovery.schedule(wasAtBottom: true, userScrolling: false)
        let first = try #require(recovery.requestID)
        // Reflow may report away from bottom before the next layout switch.
        recovery.schedule(wasAtBottom: false, userScrolling: false)
        let latest = try #require(recovery.requestID)
        let completedSuperseded = recovery.complete(first)
        let completedLatest = recovery.complete(latest)
        #expect(!completedSuperseded)
        #expect(completedLatest)
        #expect(recovery.requestID == nil)
        let completedTwice = recovery.complete(latest)
        #expect(!completedTwice)
    }

    @Test func userScrollCancelsPendingTranscriptLayoutRecovery() throws {
        var recovery = MacTranscriptLayoutRecovery()
        recovery.schedule(wasAtBottom: true, userScrolling: false)
        let pending = try #require(recovery.requestID)
        recovery.cancel()
        let completedCancelled = recovery.complete(pending)
        #expect(!completedCancelled)
        recovery.schedule(wasAtBottom: false, userScrolling: false)
        #expect(recovery.requestID == nil)
        recovery.schedule(wasAtBottom: true, userScrolling: true)
        #expect(recovery.requestID == nil)
        // Explicitly returning to the bottom allows a future layout recovery.
        recovery.schedule(wasAtBottom: true, userScrolling: false)
        let next = try #require(recovery.requestID)
        let completedNext = recovery.complete(next)
        #expect(completedNext)
    }

    @Test func windowSelectionAndDraftsAreIndependent() {
        let first = MacWindowState()
        let second = MacWindowState()
        first.open("task-a", rootID: "root-a")
        first[draft: "task-a"].text = "Task draft"
        first[draft: "root-a"].text = "Main draft"
        first.showsChanges = true
        second.open("root-b")
        #expect(first.selectedRootID == "root-a")
        #expect(first.selectedTab(rootID: "root-a") == "task-a")
        #expect(first[draft: "task-a"].text == "Task draft")
        #expect(first[draft: "root-a"].text == "Main draft")
        #expect(second[draft: "task-a"].text.isEmpty)
        #expect(second.selectedTab(rootID: "root-a") == "root-a")
        #expect(!second.showsChanges)
    }

    @Test func rejectedMessageCanBeEditedWithoutOverwritingANewerDraft() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true, rejectMissingHistoryOnce: true))
        await model.adoptExistingAccount()
        let window = MacWindowState()
        let attachment = try ComposerAttachment(fileName: "notes.txt", mimeType: "text/plain",
                                                data: Data("Notes".utf8), isImage: false)
        try model.stageOutgoingMessage("Rejected", composerText: "Rejected", mentions: .init(),
            attachments: [attachment], runConfig: nil, sessionID: "session-long")
        await #expect(throws: LodyClientError.sendNotDelivered) {
            try await model.deliverOutgoingMessage(sessionID: "session-long")
        }
        #expect(model.outgoingMessage(sessionID: "session-long")?.canRetry == false)
        window[draft: "session-long"].text = "Newer draft"
        #expect(!window.editFailedMessage(sessionID: "session-long", model: model))
        #expect(window[draft: "session-long"].text == "Newer draft")
        #expect(model.outgoingMessage(sessionID: "session-long") != nil)
        #expect(window.editFailedMessage(sessionID: "session-long", model: model, replacingDraft: true))
        #expect(window[draft: "session-long"].text == "Rejected")
        #expect(window[draft: "session-long"].attachments == [attachment])
        #expect(model.outgoingMessage(sessionID: "session-long") == nil)
        try model.stageOutgoingMessage("Revised", composerText: "Revised", mentions: .init(),
            attachments: [], runConfig: nil, sessionID: "session-long")
        try await model.deliverOutgoingMessage(sessionID: "session-long")
    }

    @Test func unconfirmedRootCanReopenAfterLeavingEvenWithoutItsTemplate() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true, failStartAndArchiveProjectOnce: true))
        await model.adoptExistingAccount()
        let window = MacWindowState()
        let id = try model.stageSessionStart("Pending root", composerText: "Pending root", mentions: .init(),
            attachments: [], agentConfigID: nil, selections: [], projectID: "local:machine-1:kurage",
            projectName: "Kurage", templateSessionID: "session-long")
        let turnID = try #require(model.outgoingMessage(sessionID: id)?.id)
        window.open(id)
        await #expect(throws: LodyClientError.deliveryUnconfirmed) {
            try await model.deliverOutgoingMessage(sessionID: id)
        }
        await model.refreshSessions()
        #expect(!model.sessions.contains { $0.id == id })
        #expect(!window.editFailedMessage(sessionID: id, model: model))
        window.open("session-pr")
        let pending = try #require(model.pendingSessionStarts.first { $0.id == id })
        try window.openPendingStart(pending, model: model)
        #expect(window.selectedRootID == id)
        #expect(model.outgoingMessage(sessionID: id)?.id == turnID)
        #expect(model.retryOutgoingMessage(sessionID: id))
        try await model.deliverOutgoingMessage(sessionID: id)
        let conversation = try await model.conversation(sessionID: id)
        #expect(conversation.turns.map(\.id) == [turnID])
        #expect(model.pendingSessionStarts.isEmpty)
    }

    @Test(arguments: [false, true])
    func rejectedFirstTurnReturnsToCreationWithItsDraftAndConfiguration(isTab: Bool) async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()
        let window = MacWindowState()
        let choices = [RunConfigChoice(configOptionID: "invalid", value: "invalid")]
        let attachment = try ComposerAttachment(fileName: "notes.txt", mimeType: "text/plain",
                                                data: Data("Notes".utf8), isImage: false)
        let id = try model.stageSessionStart("First", composerText: "First", mentions: .init(),
            attachments: [attachment], agentConfigID: "codex", selections: choices,
            projectID: "local:machine-1:kurage", projectName: "Kurage", templateSessionID: "session-long",
            parentSessionID: isTab ? "session-long" : nil)
        window.open(id, rootID: isTab ? "session-long" : nil)
        await #expect(throws: isTab ? LodyClientError.sessionCreationRejected : .notConnected) {
            try await model.deliverOutgoingMessage(sessionID: id)
        }
        #expect(window.editFailedMessage(sessionID: id, model: model))
        #expect(window.newSession?.restoredMessage?.composerText == "First")
        #expect(window.newSession?.restoredMessage?.attachments == [attachment])
        #expect(window.newSession?.restoredStart?.request.selections == choices)
        #expect(window.newSession?.isTab == isTab)
        #expect(window.selectedRootID == "session-long")
        #expect(model.pendingSessionStarts.isEmpty)
        #expect(model.pendingSessionTab(rootID: "session-long") == nil)
        #expect(model.sessionSummary(id) == nil)
    }

    @Test func draftConfigurationConsumesOnlySentChoicesAndDropsUnsupportedChoices() {
        let window = MacWindowState()
        let config = SessionRunConfig(model: .init(value: "model", label: "Model"),
            reasoning: .init(value: "medium", label: "Medium"),
            editable: .init(kind: .reasoning, configOptionID: "effort", options: [
                .init(value: "low", label: "Low"), .init(value: "high", label: "High")]))
        window[draft: "session"].runConfig.receive(config)
        window[draft: "session"].runConfig.choose("low")
        let sent = window[draft: "session"].runConfig.choice
        window.open("another-session")
        window[draft: "session"].runConfig.didSend(sent)
        #expect(window[draft: "session"].runConfig.choice == nil)
        let remote = config.applying(.init(configOptionID: "effort", value: "high"))
        window[draft: "session"].runConfig.receive(remote)
        #expect(window[draft: "session"].runConfig.displayed?.reasoning?.value == "high")
        window[draft: "session"].runConfig.choose("high")
        window[draft: "session"].runConfig.didSend(sent)
        #expect(window[draft: "session"].runConfig.choice?.value == "high")
        var readOnly = remote
        readOnly.editable = nil
        window[draft: "session"].runConfig.receive(readOnly)
        #expect(window[draft: "session"].runConfig.choice == nil)
        #expect(window[draft: "another-session"].runConfig.config == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingPreviewStopsItsDetachedComparison() async throws {
        let started = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            await RecordedFileDiff.previewInBackground(for: .init(id: "cancel", oldText: "old", newText: "new")) { _ in
                started.withLock { $0 = true }
                while !Task.isCancelled {
                    if release.wait(timeout: .now() + .milliseconds(5)) == .success { break }
                }
                return .unavailable(reason: Task.isCancelled ? "cancelled" : "completed")
            }
        }
        defer { task.cancel(); release.signal() }
        for _ in 0..<200 {
            if started.withLock({ $0 }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(started.withLock { $0 })
        task.cancel()
        // A missing cancellation handler must fail instead of hanging the test run.
        let timeout = Task.detached {
            try? await Task.sleep(for: .seconds(2))
            release.signal()
        }
        defer { timeout.cancel() }
        guard case .unavailable(let reason) = await task.value else {
            Issue.record("Cancelled comparison unexpectedly produced a preview")
            return
        }
        #expect(reason == "cancelled")
    }

    @Test func projectTemplatesUseRecentLocalRootsRatherThanListOrder() throws {
        var old = SessionSummary(id: "old", title: "Old", agentName: "codex", activity: .idle,
            preview: "", projectID: "local:a", isPinned: true, lastMessageAt: 10)
        var recent = old
        recent.projectID = "local:b"
        recent.lastMessageAt = nil
        recent.lastActivityAt = 40
        var child = old
        child.projectID = "local:child"
        child.parentSessionID = "root"
        child.lastMessageAt = 100
        var remote = old
        remote.projectID = "github:remote"
        remote.lastMessageAt = 200
        let duplicate = old
        old.lastMessageAt = 30
        let result = NewSessionDestination.projectTemplates(in: [duplicate, child, remote, old, recent])
        #expect(result.map(\.projectID) == ["local:b", "local:a"])
        #expect(result.last?.lastMessageAt == 30)
    }

    @Test func pasteboardPrefersFilesAndDoesNotTreatTextAsAttachments() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("file:///tmp/not-an-attachment.txt", forType: .string)
        #expect(MacAttachmentSource.read(from: pasteboard).isEmpty)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("file:///tmp/report.txt", forType: .fileURL)
        item.setData(Data([1, 2, 3]), forType: .png)
        pasteboard.writeObjects([item])
        let sources = MacAttachmentSource.read(from: pasteboard)
        #expect(sources.count == 1)
        guard case .file(let url) = try #require(sources.first).content else {
            Issue.record("Expected a file, not Finder's preview")
            return
        }
        #expect(url.lastPathComponent == "report.txt")
    }

    @Test func attachmentImportReadsFilesConvertsTIFFAndRejectsInvalidInputs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.txt")
        let bytes = Data("Attachment text with Unicode 你好".utf8)
        try bytes.write(to: file)
        let attachment = try await MacAttachmentSource(content: .file(file)).load()
        #expect(attachment.data == bytes)
        #expect(attachment.fileName == "notes.txt")
        #expect(!attachment.isImage)
        #expect(attachment.mimeType == "text/plain")
        let image = NSImage(size: NSSize(width: 80, height: 40), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let photo = try await MacAttachmentSource(content: .image(tiff, "image/tiff")).load()
        #expect(photo.isImage)
        #expect(photo.mimeType == "image/jpeg")
        #expect(photo.fileName == "Pasted image.jpg")
        let decoded = try #require(NSBitmapImageRep(data: photo.data))
        #expect(decoded.pixelsWide == 160 || decoded.pixelsWide == 80)
        #expect(decoded.pixelsWide == decoded.pixelsHigh * 2)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let original = try await MacAttachmentSource(content: .image(png, "image/png")).load()
        #expect(original.data == png)
        #expect(original.mimeType == "image/png")
        await #expect(throws: AttachmentError.self) {
            _ = try await MacAttachmentSource(content: .file(directory)).load()
        }
        try Data(count: 16 * 1024 * 1024).write(to: file)
        let atLimit = try await MacAttachmentSource(content: .file(file)).load()
        #expect(atLimit.data.count == 16 * 1024 * 1024)
        try Data(count: 16 * 1024 * 1024 + 1).write(to: file)
        await #expect(throws: AttachmentError.self) {
            _ = try await MacAttachmentSource(content: .file(file)).load()
        }
        await #expect(throws: AttachmentError.self) {
            _ = try await MacAttachmentSource(content: .image(Data([1, 2]), "image/png")).load()
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MacAttachmentSource(content: .image(tiff, "image/tiff")).load()
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func nativeClientUsesSharedOutboxAndIndependentBranchData() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        #expect(!model.notifications.isConfigured)
        let conversation = try await model.conversation(sessionID: "session-long")
        let branch = try await model.branchChanges(sessionID: "session-long", workspaceID: "ws-demo")
        #expect(branch.status == .ready)
        #expect(!branch.files.isEmpty)
        #expect(Set(branch.files.map(\.path)).count == branch.files.count)
        let before = conversation.turns.count
        try model.stageOutgoingMessage("Mac integration message", composerText: "Mac integration message", mentions: .init(),
                                       attachments: [], runConfig: nil, sessionID: "session-long", turnID: "mac-message")
        #expect(model.displayedTurns(conversation.turns, sessionID: "session-long").last?.id == "mac-message")
        try await model.deliverOutgoingMessage(sessionID: "session-long")
        let after = try await model.conversation(sessionID: "session-long")
        #expect(after.turns.count > before)
        #expect(after.turns.filter { $0.id == "mac-message" }.count == 1)
        #expect(after.turns.first { $0.id == "mac-message" }?.text == "Mac integration message")
    }

    @Test(.timeLimit(.minutes(1)))
    func bundledWebKitRuntimeStartsOnMac() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let page = try #require(SessionSyncBridge.bundledPageURL)
        #expect(page.path.contains("KurageCore"))
        _ = try #require(webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent()))
        defer { webView.stopLoading(); webView.loadHTMLString("", baseURL: nil) }
        for _ in 0..<500 {
            if !webView.isLoading && webView.url == page { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let result = try await webView.callAsyncJavaScript("""
            await window.kurageBridgeReady;
            const bytes = new TextEncoder().encode('Kurage 你好');
            const compressed = await new Response(new Blob([bytes]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer();
            const restored = await new Response(new Blob([compressed]).stream().pipeThrough(new DecompressionStream('gzip'))).arrayBuffer();
            return typeof window.kurageSessions === 'function' &&
                   typeof window.kurageStartSession === 'function' &&
                   new TextDecoder().decode(restored) === 'Kurage 你好';
            """, arguments: [:], in: nil, contentWorld: .page)
        #expect(result as? Bool == true)
    }
}
