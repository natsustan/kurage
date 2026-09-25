import SwiftUI
import Testing
import UIKit
@testable import Kurage

@MainActor
struct ConversationLayoutTests {
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

    private func makeController() throws -> (ConversationLayoutController<TestFooter>, UIWindow) {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let controller = ConversationLayoutController(footer: TestFooter())
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        return (controller, window)
    }

    private struct TestFooter: View {
        var body: some View { Color.clear.frame(height: 70) }
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
