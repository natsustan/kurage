import Foundation
import Testing
import WebKit
@testable import KurageCore
@testable import KurageMac

@MainActor
struct MacClientTests {
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
