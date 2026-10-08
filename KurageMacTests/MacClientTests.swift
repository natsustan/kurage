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
