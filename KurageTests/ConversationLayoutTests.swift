import SwiftUI
import Testing
import UIKit
@testable import Kurage

@MainActor
struct ConversationLayoutTests {
    @Test func readOnlyRunStartsBelowItsHeaderAndFollowsGrowthFromTheBottom() async throws {
        let (controller, window) = try makeController(startsAtTop: true)
        defer { window.isHidden = true; window.rootViewController = nil }
        var turns = [ConversationTurn(id: "output", author: .agent, text: "Review complete.")]
        update(controller, turns: turns)
        await settle(controller)
        let table = try transcript(in: controller.view)
        #expect(table.contentInset.top == 6)
        #expect(abs(table.contentOffset.y + 6) < 1)

        turns[0].text = String(repeating: "More output\n", count: 80)
        update(controller, turns: turns)
        await settle(controller)
        expectAtBottom(table)
        #expect(table.contentInset.top == 6)
    }

    @Test func longReadOnlyRunOpensAtTheBeginningAndPreservesReadingDuringUpdates() async throws {
        let (controller, window) = try makeController(startsAtTop: true)
        defer { window.isHidden = true; window.rootViewController = nil }
        var turns = sampleTurns()
        update(controller, turns: turns)
        await settle(controller)
        let table = try transcript(in: controller.view)
        #expect(abs(table.contentOffset.y + 6) < 1)
        turns[turns.count - 1].text += String(repeating: " More output.", count: 80)
        update(controller, turns: turns)
        controller.view.frame.size.height = 430
        await settle(controller)
        #expect(abs(table.contentOffset.y + 6) < 1)

        controller.scrollViewWillBeginDragging(table)
        table.contentOffset.y = max(-6, table.contentSize.height + table.contentInset.bottom - table.bounds.height)
        controller.scrollViewDidEndDragging(table, willDecelerate: false)
        turns[turns.count - 1].text += String(repeating: " More output.", count: 80)
        update(controller, turns: turns)
        await settle(controller)
        expectAtBottom(table)
    }

    @Test func singleLongAnswerDoesNotFollowItsEstimatedRowHeightToTheEnd() async throws {
        let (controller, window) = try makeController(startsAtTop: true)
        defer { window.isHidden = true; window.rootViewController = nil }
        let turns = [ConversationTurn(id: "output", author: .agent, text: String(repeating: "Review finding.\n", count: 80))]
        update(controller, turns: turns)
        await settle(controller)
        let table = try transcript(in: controller.view)
        #expect(table.contentSize.height > table.bounds.height)
        #expect(abs(table.contentOffset.y + 6) < 1)
        update(controller, turns: turns)
        await settle(controller)
        #expect(abs(table.contentOffset.y + 6) < 1)
    }

    @Test func wideTranscriptAndComposerShareACenteredReadableWidth() async throws {
        let (controller, window) = try makeController()
        defer { window.isHidden = true; window.rootViewController = nil }
        update(controller, turns: sampleTurns())
        controller.view.frame.size.width = 1200
        await settle(controller)
        let content = try #require(controller.view.subviews.first)
        let table = try transcript(in: controller.view)
        let footer = try #require(content.subviews.compactMap { $0 as? UIScrollView }
            .first { !($0 is UITableView) })
        #expect(abs(content.frame.width - ConversationMetrics.maximumContentWidth) < 1)
        #expect(abs(content.frame.midX - controller.view.safeAreaLayoutGuide.layoutFrame.midX) < 1)
        #expect(abs(table.frame.width - footer.frame.width) < 1)
        expectAtBottom(table)

        controller.view.frame.size.width = 360
        await settle(controller)
        #expect(abs(content.frame.width - controller.view.safeAreaLayoutGuide.layoutFrame.width) < 1)
        expectAtBottom(table)
    }

    @Test func readingAnchorSurvivesWidthChangesThatReflowMessages() async throws {
        let (controller, window) = try makeController()
        defer { window.isHidden = true; window.rootViewController = nil }
        let turns = sampleTurns().map { turn in
            ConversationTurn(id: turn.id, author: .user, text: String(repeating: "A message that wraps as the window changes. ", count: 6))
        }
        update(controller, turns: turns)
        await settle(controller)
        let table = try transcript(in: controller.view)
        controller.scrollViewWillBeginDragging(table)
        table.contentOffset.y = 500
        table.layoutIfNeeded()
        controller.scrollViewDidEndDragging(table, willDecelerate: false)
        let row = try #require(table.indexPathsForVisibleRows?.first)
        let position = table.rectForRow(at: row).minY - table.contentOffset.y
        for width in [CGFloat(1100), CGFloat(360)] {
            controller.view.frame.size.width = width
            await settle(controller)
            #expect(abs(table.rectForRow(at: row).minY - table.contentOffset.y - position) < 1)
        }
    }

    @Test func streamingGrowthAndDeletionKeepBottomVisible() throws {
        let (controller, window) = try makeController()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        var turns = sampleTurns()
        update(controller, turns: turns)
        let table = try transcript(in: controller.view)
        expectAtBottom(table)

        turns[turns.count - 1].text = String(repeating: "More output\n", count: 30)
        update(controller, turns: turns)
        expectAtBottom(table)
        #expect(table.numberOfRows(inSection: 0) == turns.count)

        turns.removeLast(3)
        update(controller, turns: turns)
        #expect(table.numberOfRows(inSection: 0) == turns.count)
        expectAtBottom(table)
    }

    @Test func transcriptFillsPastTheHomeIndicatorWhileTheComposerStaysAboveIt() throws {
        let (controller, window) = try makeController()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        controller.additionalSafeAreaInsets.bottom = 34
        update(controller, turns: sampleTurns())
        let content = try #require(controller.view.subviews.first)
        #expect(abs(content.frame.maxY - controller.view.bounds.height) < 1)
        let footer = try #require(content.subviews.filter { !($0 is UITableView) }.max { $0.frame.maxY < $1.frame.maxY })
        let footerBottom = content.convert(footer.frame, to: controller.view).maxY
        let safeBottom = controller.view.bounds.height - controller.view.safeAreaInsets.bottom
        #expect(abs(footerBottom - safeBottom) < 1)
        let table = try transcript(in: controller.view)
        #expect(abs(table.frame.maxY - content.bounds.height) < 1)
        #expect(table.frame.maxY > footer.frame.maxY + 20)
    }

    @Test(arguments: [false, true], [CGFloat(290), CGFloat(520)])
    func tallComposerKeepsItsBottomEdgeInACompactViewport(hasMessages: Bool, height: CGFloat) async throws {
        let (controller, window) = try makeController()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.update(turns: hasMessages ? sampleTurns() : [], isLoading: false,
                          scrollRequestID: 0, footer: TestFooter(height: height), onRefresh: {})
        await settle(controller)
        controller.view.frame.size.height = 430
        await settle(controller)

        let content = try #require(controller.view.subviews.first)
        let footer = try #require(content.subviews.compactMap { $0 as? UIScrollView }
            .first { !($0 is UITableView) })
        let footerBottom = content.convert(footer.frame, to: controller.view).maxY
        let safeBottom = controller.view.bounds.height - controller.view.safeAreaInsets.bottom
        let availableHeight = safeBottom - content.frame.minY
        #expect(abs(footer.frame.height - min(height, availableHeight)) < 1)
        #expect(abs(footerBottom - safeBottom) < 1)
        #expect(footer.isScrollEnabled == (height > availableHeight))
        #expect(abs(footer.contentOffset.y - max(0, height - footer.bounds.height)) < 1)
    }

    @Test func composerBottomScrollWaitsForTheChildViewportResize() async throws {
        let (controller, window) = try makeController()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.update(turns: sampleTurns(), isLoading: false, scrollRequestID: 0,
                          footer: TestFooter(height: 520), onRefresh: {})
        controller.view.frame.size.height = 457
        await settle(controller)
        let content = try #require(controller.view.subviews.first)
        let footer = try #require(content.subviews.compactMap { $0 as? UIScrollView }
            .first { !($0 is UITableView) })

        // Keyboard tracking can lay out the parent before applying the new
        // viewport bounds to the child scroll view.
        let finalHeight = footer.bounds.height - 27
        content.frame.size.height -= 27
        controller.viewDidLayoutSubviews()
        footer.frame.size.height = finalHeight
        footer.setNeedsLayout()
        footer.layoutIfNeeded()
        #expect(abs(footer.bounds.height - finalHeight) < 1)
        #expect(abs(footer.contentOffset.y - (520 - footer.bounds.height)) < 1)
    }

    @Test func readingHistorySurvivesResizeAndOutputUntilSend() throws {
        let (controller, window) = try makeController()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        var turns = sampleTurns()
        update(controller, turns: turns)
        let table = try transcript(in: controller.view)
        controller.scrollViewWillBeginDragging(table)
        table.contentOffset.y = 100
        table.layoutIfNeeded()
        controller.scrollViewDidEndDragging(table, willDecelerate: false)
        let readingRow = try #require(table.indexPathsForVisibleRows?.first)
        let readingPosition = table.rectForRow(at: readingRow).minY - table.contentOffset.y

        controller.view.frame.size.height = 450
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        #expect(abs(table.rectForRow(at: readingRow).minY - table.contentOffset.y - readingPosition) < 1)
        turns[turns.count - 1].text += String(repeating: " More output.", count: 40)
        update(controller, turns: turns)
        #expect(abs(table.rectForRow(at: readingRow).minY - table.contentOffset.y - readingPosition) < 1)

        update(controller, turns: turns, scrollRequestID: 1)
        expectAtBottom(table)
    }

    @Test(arguments: ["Done", ""]) func fileChangesRefreshWithoutChangingMessageText(text: String) throws {
        let (controller, window) = try makeController()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let turns = [ConversationTurn(id: "long-agent-20", author: .agent, text: text)]
        update(controller, turns: turns)
        let table = try transcript(in: controller.view)
        let originalHeight = table.rectForRow(at: IndexPath(row: 0, section: 0)).height
        controller.update(turns: turns, fileChanges: [.fixture], isLoading: false,
                          scrollRequestID: 0, footer: TestFooter(), onRefresh: {})
        controller.view.layoutIfNeeded()
        #expect(table.numberOfRows(inSection: 0) == 1)
        #expect(table.rectForRow(at: IndexPath(row: 0, section: 0)).height > originalHeight + 80)
        expectAtBottom(table)
        update(controller, turns: turns)
        #expect(abs(table.rectForRow(at: IndexPath(row: 0, section: 0)).height - originalHeight) < 1)
        expectAtBottom(table)
    }

    @Test func receiptsWaitForLayoutAndResumeOnlyAfterReturningToBottom() async throws {
        let (controller, window) = try makeController()
        defer { window.isHidden = true; window.rootViewController = nil }
        var receipts: [Double?] = []
        controller.onBottomMessage = { receipts.append($0) }
        var turns = sampleTurns()
        controller.update(turns: turns, isLoading: false, scrollRequestID: 0, messageTimestamp: 100,
                          footer: TestFooter(), onRefresh: {})
        #expect(receipts.isEmpty)
        await settle(controller)
        #expect(receipts.last == .some(100))
        let table = try transcript(in: controller.view)
        controller.scrollViewWillBeginDragging(table)
        table.contentOffset.y = 100
        controller.scrollViewDidEndDragging(table, willDecelerate: false)
        await settle(controller)
        #expect(receipts.last == .some(nil))
        turns.append(ConversationTurn(id: "new", author: .agent, text: "New output"))
        controller.update(turns: turns, isLoading: false, scrollRequestID: 0, messageTimestamp: 200,
                          footer: TestFooter(), onRefresh: {})
        controller.view.frame.size.height = 450
        await settle(controller)
        #expect(!receipts.contains(.some(200)))
        controller.scrollViewWillBeginDragging(table)
        table.contentOffset.y = max(-table.contentInset.top,
            table.contentSize.height + table.contentInset.bottom - table.bounds.height)
        controller.scrollViewDidEndDragging(table, willDecelerate: true)
        await settle(controller)
        #expect(!receipts.contains(.some(200)))
        // Self-sizing can revise the bottom while decelerating; simulate the
        // gesture reaching the final measured offset before it ends.
        table.contentOffset.y = max(-table.contentInset.top,
            table.contentSize.height + table.contentInset.bottom - table.bounds.height)
        controller.scrollViewDidEndDecelerating(table)
        await settle(controller)
        #expect(receipts.last == .some(200))
        expectAtBottom(table)
        controller.view.frame.size.height = 700
        await settle(controller)
        #expect(receipts.last == .some(200))
    }

    @Test func queuedBottomNotificationCannotAcknowledgeNewContentWhileDragging() async throws {
        let (controller, window) = try makeController()
        defer { window.isHidden = true; window.rootViewController = nil }
        var receipts: [Double?] = []
        controller.onBottomMessage = { receipts.append($0) }
        controller.update(turns: sampleTurns(), isLoading: false, scrollRequestID: 0, messageTimestamp: 100,
                          footer: TestFooter(), onRefresh: {})
        controller.view.layoutIfNeeded()
        let table = try transcript(in: controller.view)
        controller.scrollViewWillBeginDragging(table)
        await settle(controller)
        #expect(receipts.isEmpty)
    }

    private func settle(_ controller: ConversationLayoutController<TestFooter>) async {
        for _ in 0..<3 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private func makeController(startsAtTop: Bool = false) throws -> (ConversationLayoutController<TestFooter>, UIWindow) {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let controller = ConversationLayoutController(footer: TestFooter(), startsAtTop: startsAtTop)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        return (controller, window)
    }

    private struct TestFooter: View {
        var height: CGFloat = 70

        var body: some View { Color.clear.frame(height: height) }
    }

    private func sampleTurns() -> [ConversationTurn] {
        (0..<30).map { ConversationTurn(id: "turn-\($0)", author: .user, text: "Message \($0)") }
    }

    private func update(_ controller: ConversationLayoutController<TestFooter>, turns: [ConversationTurn],
                        scrollRequestID: Int = 0) {
        controller.update(turns: turns, isLoading: false, scrollRequestID: scrollRequestID,
                          footer: TestFooter(), onRefresh: {})
        controller.view.layoutIfNeeded()
    }

    private func transcript(in view: UIView) throws -> UITableView {
        let content = try #require(view.subviews.first)
        return try #require(content.subviews.compactMap { $0 as? UITableView }.first)
    }

    private func expectAtBottom(_ table: UITableView, sourceLocation: SourceLocation = #_sourceLocation) {
        let bottom = max(-table.contentInset.top,
                         table.contentSize.height + table.contentInset.bottom - table.bounds.height)
        #expect(abs(table.contentOffset.y - bottom) < 1, sourceLocation: sourceLocation)
    }
}
