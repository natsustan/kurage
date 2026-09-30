import SwiftUI
import UIKit

/// UIKit owns keyboard avoidance and scrolling; SwiftUI owns message and composer content.
struct ConversationLayout<Footer: View>: UIViewControllerRepresentable {
    let turns: [ConversationTurn]
    var fileChanges: [ConversationFileChangeGroup] = []
    var onOpenTurnChanges: (Int) -> Void = { _ in }
    let isLoading: Bool
    var isRunning = false
    let scrollRequestID: Int
    var messageTimestamp: Double? = nil
    var onBottomMessage: (Double?) -> Void = { _ in }
    let loadImage: @MainActor (ConversationImage, SessionImageVariant) async throws -> Data
    let onPreviewImage: (ConversationImage) -> Void
    let onRefresh: () -> Void
    var canRetryMessage = false
    var canEditMessage = false
    var onRetryMessage: (ConversationTurn.ID) -> Void = { _ in }
    var onEditMessage: (ConversationTurn.ID) -> Void = { _ in }
    @ViewBuilder let footer: () -> Footer

    func makeUIViewController(context: Context) -> ConversationLayoutController<Footer> {
        ConversationLayoutController(footer: footer())
    }

    func updateUIViewController(_ controller: ConversationLayoutController<Footer>, context: Context) {
        controller.onBottomMessage = onBottomMessage
        controller.loadImage = loadImage
        controller.onPreviewImage = onPreviewImage
        controller.onOpenTurnChanges = onOpenTurnChanges
        controller.onRetryMessage = onRetryMessage
        controller.onEditMessage = onEditMessage
        controller.update(turns: turns, fileChanges: fileChanges, isLoading: isLoading, isRunning: isRunning, scrollRequestID: scrollRequestID, messageTimestamp: messageTimestamp,
                          canRetryMessage: canRetryMessage, canEditMessage: canEditMessage,
                          footer: footer(), onRefresh: onRefresh)
    }
}

final class ConversationLayoutController<Footer: View>: UIViewController, UITableViewDelegate {
    private let contentView = UIView()
    private let tableView = ConversationTableView(frame: .zero, style: .plain)
    private let footerScrollView = ConversationFooterScrollView()
    private let footerHost: UIHostingController<MeasuredConversationFooter<Footer>>
    private var footerHeightConstraint: NSLayoutConstraint!
    private var footerViewportHeightConstraint: NSLayoutConstraint!
    private var needsFooterBottomScroll = true
    private let emptyHost = UIHostingController(rootView: ConversationEmptyState(isLoading: true))
    private var dataSource: UITableViewDiffableDataSource<Int, ConversationTurn.ID>!
    private var turnsByID: [ConversationTurn.ID: ConversationTurn] = [:]
    private var changesByID: [String: ConversationFileChangeGroup] = [:]
    var onOpenTurnChanges: (Int) -> Void = { _ in }
    var onRetryMessage: (ConversationTurn.ID) -> Void = { _ in }
    var onEditMessage: (ConversationTurn.ID) -> Void = { _ in }
    private var canRetryMessage = false
    private var canEditMessage = false
    private var isRunning = false
    private var turnIDs: [ConversationTurn.ID] = []
    private var scrollRequestID = 0
    private struct ReadingAnchor {
        let id: ConversationTurn.ID
        let viewportOffset: CGFloat
    }

    private var readingAnchor: ReadingAnchor?
    private var anchorsDisclosure = false
    var onBottomMessage: (Double?) -> Void = { _ in }
    private var messageTimestamp: Double?
    private var reportedBottomMessage: Double?
    private var needsReceiptLayout = true
    private var snapshotGeneration = 0
    private var applyingSnapshot = false
    private var followsOutput = true
    private var isUserScrolling = false
    private var isAdjustingLayout = false
    /// Opened "Worked for …" and activity disclosures, restored when cells are reconfigured or reused.
    private var expandedDisclosures: Set<String> = []
    private var onRefresh: (() -> Void)?
    var loadImage: (@MainActor (ConversationImage, SessionImageVariant) async throws -> Data)?
    var onPreviewImage: ((ConversationImage) -> Void)?

    init(footer: Footer) {
        footerHost = UIHostingController(rootView: MeasuredConversationFooter(content: footer, onHeightChange: { _ in }))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        // Track the screen edge when the keyboard is hidden, so the transcript fills the
        // home-indicator area instead of leaving the view's background as an empty band.
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.selfSizingInvalidation = .enabledIncludingConstraints
        tableView.estimatedRowHeight = 100
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.automaticallyAdjustsScrollIndicatorInsets = false
        tableView.bottomEdgeEffect.isHidden = true
        tableView.keyboardDismissMode = .interactive
        tableView.alwaysBounceVertical = true
        tableView.accessibilityIdentifier = "conversation-transcript"
        tableView.delegate = self
        tableView.register(ConversationTurnCell.self, forCellReuseIdentifier: "turn")
        contentView.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        dataSource = UITableViewDiffableDataSource<Int, ConversationTurn.ID>(tableView: tableView) {
            [weak self] table, indexPath, id in
            let cell = table.dequeueReusableCell(withIdentifier: "turn", for: indexPath) as! ConversationTurnCell
            guard let turn = self?.turnsByID[id] else { return cell }
            cell.backgroundColor = .clear
            let loadImage: @MainActor (ConversationImage, SessionImageVariant) async throws -> Data
            if let imageLoader = self?.loadImage {
                loadImage = imageLoader
            } else {
                loadImage = { _, _ in throw LodyClientError.notConnected }
            }
            let onPreviewImage = self?.onPreviewImage ?? { _ in }
            let changes = self?.changesByID[id]
            let onOpenChanges = self?.onOpenTurnChanges ?? { _ in }
            let disclosures = TurnDisclosures { [weak self] key in
                self?.expandedDisclosures.contains(key) ?? false
            } onToggle: { [weak self] key, expanded in
                self?.toggleDisclosure(key, expanded: expanded, turnID: id)
            }
            cell.setContent(parent: self) {
                TurnRow(turn: turn, loadImage: loadImage, onPreviewImage: onPreviewImage,
                        fileChanges: changes, onOpenChanges: onOpenChanges,
                        onToggleChanges: { [weak self] in
                            self?.anchorDisclosureResize(turnID: id)
                        },
                        disclosures: disclosures, isRunning: self?.isRunning == true && id == self?.turnIDs.last,
                        canRetryMessage: self?.canRetryMessage == true, canEditMessage: self?.canEditMessage == true,
                        onRetryMessage: { [weak self] in self?.onRetryMessage(id) },
                        onEditMessage: { [weak self] in self?.onEditMessage(id) })
                    // A reused cell must not carry another turn's disclosure state.
                    .id(turn.id)
                    // Cell sizing must not inject a second geometry animation.
                    .transaction { transaction in
                        guard turn.author == .agent else { return }
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
            return cell
        }

        install(emptyHost, in: contentView)
        footerScrollView.translatesAutoresizingMaskIntoConstraints = false
        footerScrollView.contentInsetAdjustmentBehavior = .never
        footerScrollView.scrollsToTop = false
        contentView.addSubview(footerScrollView)
        install(footerHost, in: footerScrollView)
        footerHeightConstraint = footerHost.view.heightAnchor.constraint(equalToConstant: 78)
        footerViewportHeightConstraint = footerScrollView.heightAnchor.constraint(equalToConstant: 78)
        // Follow the keyboard, but stay above the home indicator while it is hidden.
        // The lower-priority equality yields when the safe-area cap is tighter.
        let footerFollowsKeyboard = footerScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        footerFollowsKeyboard.priority = .defaultHigh
        // A placeholder's minimum size must yield before keyboard avoidance,
        // including when an accessible composer fills the entire viewport.
        let emptyBottom = emptyHost.view.bottomAnchor.constraint(equalTo: footerScrollView.topAnchor)
        emptyBottom.priority = .defaultLow
        NSLayoutConstraint.activate([
            footerHeightConstraint,
            footerViewportHeightConstraint,
            footerHost.view.topAnchor.constraint(equalTo: footerScrollView.contentLayoutGuide.topAnchor),
            footerHost.view.bottomAnchor.constraint(equalTo: footerScrollView.contentLayoutGuide.bottomAnchor),
            footerHost.view.leadingAnchor.constraint(equalTo: footerScrollView.contentLayoutGuide.leadingAnchor),
            footerHost.view.trailingAnchor.constraint(equalTo: footerScrollView.contentLayoutGuide.trailingAnchor),
            footerHost.view.widthAnchor.constraint(equalTo: footerScrollView.frameLayoutGuide.widthAnchor),
            footerScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footerFollowsKeyboard,
            footerScrollView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            footerScrollView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
            emptyHost.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            emptyHost.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            emptyHost.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            emptyBottom
        ])
        // Empty-state artwork does not prevent pulling the list to refresh.
        emptyHost.view.isUserInteractionEnabled = false
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in
            self?.onRefresh?()
            self?.tableView.refreshControl?.endRefreshing()
        }, for: .valueChanged)
        tableView.refreshControl = refresh
        tableView.onLayout = { [weak self] in self?.adjustTranscriptLayout() }
        footerScrollView.onLayout = { [weak self] in self?.updateFooterViewport() }
    }

    private func install<Content: View>(_ host: UIHostingController<Content>, in container: UIView) {
        addChild(host)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host.view)
        host.didMove(toParent: self)
    }

    func update(turns: [ConversationTurn], fileChanges: [ConversationFileChangeGroup] = [], isLoading: Bool, isRunning: Bool = false, scrollRequestID: Int, messageTimestamp: Double? = nil,
                canRetryMessage: Bool = false, canEditMessage: Bool = false,
                footer: Footer, onRefresh: @escaping () -> Void) {
        loadViewIfNeeded()
        self.messageTimestamp = messageTimestamp
        needsReceiptLayout = true
        self.onRefresh = onRefresh
        footerHost.rootView = MeasuredConversationFooter(content: footer) { [weak self] height in
            guard let self, height.isFinite, height > 0,
                  abs(footerHeightConstraint.constant - height) > 0.5 else { return }
            footerHeightConstraint.constant = ceil(height)
            needsFooterBottomScroll = true
            view.setNeedsLayout()
            // Keep the transcript inset in step with the newly measured footer.
            view.layoutIfNeeded()
        }
        emptyHost.rootView = ConversationEmptyState(isLoading: isLoading)
        emptyHost.view.isHidden = !turns.isEmpty
        if self.scrollRequestID != scrollRequestID {
            self.scrollRequestID = scrollRequestID
            followsOutput = true
            anchorsDisclosure = false
            readingAnchor = nil
        }
        let runningChanged = self.isRunning != isRunning
        self.isRunning = isRunning
        let messageActionsChanged = self.canRetryMessage != canRetryMessage || self.canEditMessage != canEditMessage
        self.canRetryMessage = canRetryMessage
        self.canEditMessage = canEditMessage
        let updatedChanges = Dictionary(uniqueKeysWithValues: fileChanges.map { ($0.id, $0) })
        let updatedIDs = turns.map(\.id)
        let lastTurnChanged = turnIDs.last != updatedIDs.last
        let changedIDs: [ConversationTurn.ID] = turns.compactMap { turn in
            let runningDisplayChanged = (runningChanged || lastTurnChanged) &&
                (turn.id == turnIDs.last || turn.id == updatedIDs.last)
            guard let previous = turnsByID[turn.id], previous != turn ||
                    messageActionsChanged && turn.delivery != nil ||
                    changesByID[turn.id] != updatedChanges[turn.id] || runningDisplayChanged else { return nil }
            return turn.id
        }
        changesByID = updatedChanges
        if turnIDs != updatedIDs || !changedIDs.isEmpty {
            turnsByID = Dictionary(uniqueKeysWithValues: turns.map { ($0.id, $0) })
            var snapshot: NSDiffableDataSourceSnapshot<Int, ConversationTurn.ID>
            if turnIDs == updatedIDs {
                snapshot = dataSource.snapshot()
            } else {
                turnIDs = updatedIDs
                snapshot = NSDiffableDataSourceSnapshot()
                snapshot.appendSections([0])
                snapshot.appendItems(updatedIDs)
            }
            snapshot.reconfigureItems(changedIDs)
            snapshotGeneration += 1
            let generation = snapshotGeneration
            applyingSnapshot = true
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self, self.snapshotGeneration == generation else { return }
                self.applyingSnapshot = false
                self.view.setNeedsLayout()
            }
        }
        view.setNeedsLayout()
    }

    /// Both directions keep the tapped row anchored instead of following its bottom.
    private func toggleDisclosure(_ key: String, expanded: Bool, turnID: ConversationTurn.ID) {
        if expanded { expandedDisclosures.insert(key) } else { expandedDisclosures.remove(key) }
        anchorDisclosureResize(turnID: turnID)
    }

    private func anchorDisclosureResize(turnID: ConversationTurn.ID) {
        guard let indexPath = dataSource.indexPath(for: turnID) else { return }
        followsOutput = false
        anchorsDisclosure = true
        readingAnchor = ReadingAnchor(id: turnID,
                                      viewportOffset: tableView.rectForRow(at: indexPath).minY - tableView.contentOffset.y)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFooterViewport()
        adjustTranscriptLayout()
    }

    private func updateFooterViewport() {
        guard contentView.bounds.height > 0 else { return }
        let availableHeight = max(0, min(contentView.frame.maxY, view.safeAreaLayoutGuide.layoutFrame.maxY)
            - contentView.frame.minY)
        let height = min(footerHeightConstraint.constant, availableHeight)
        if abs(footerViewportHeightConstraint.constant - height) > 0.5 {
            footerViewportHeightConstraint.constant = height
            needsFooterBottomScroll = true
            view.setNeedsLayout()
        }
        footerScrollView.isScrollEnabled = footerHeightConstraint.constant > height + 0.5
        // Keep the action row visible after adding attachments or opening the
        // keyboard. Oversized content remains reachable by scrolling upward.
        if needsFooterBottomScroll, abs(footerScrollView.bounds.height - height) < 0.5 {
            footerScrollView.contentOffset.y = max(0, footerHeightConstraint.constant - height)
            needsFooterBottomScroll = false
        }
    }

    private var bottomOffset: CGFloat {
        max(-tableView.contentInset.top,
            tableView.contentSize.height + tableView.contentInset.bottom - tableView.bounds.height)
    }

    private func adjustTranscriptLayout() {
        guard !isAdjustingLayout, tableView.window != nil, tableView.bounds.height > 0 else { return }
        isAdjustingLayout = true
        defer {
            isAdjustingLayout = false
            if !applyingSnapshot { needsReceiptLayout = false }
            reportBottomMessage()
        }

        var bottomInset = max(0, contentView.bounds.height - footerScrollView.frame.minY) + 6
        // Keep room below a collapsed short transcript so clamping cannot pull
        // its header down while the contents are retracting upward.
        if anchorsDisclosure, let readingAnchor, let indexPath = dataSource.indexPath(for: readingAnchor.id) {
            let offset = tableView.rectForRow(at: indexPath).minY - readingAnchor.viewportOffset
            bottomInset = max(bottomInset, offset + tableView.bounds.height - tableView.contentSize.height)
        }
        // Short conversations sit next to the composer, without inserting a fake message row.
        let topInset = max(6, tableView.bounds.height - bottomInset - tableView.contentSize.height)
        let inset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        if tableView.contentInset != inset { tableView.contentInset = inset }
        let indicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        if tableView.verticalScrollIndicatorInsets != indicatorInsets {
            tableView.verticalScrollIndicatorInsets = indicatorInsets
        }
        // Only gesture callbacks change the reading intent. Keyboard/layout updates never do.
        guard !isUserScrolling else { return }
        let target: CGFloat
        if followsOutput {
            target = bottomOffset
        } else if let readingAnchor, let indexPath = dataSource.indexPath(for: readingAnchor.id) {
            // Self-sizing rows can change the numeric offset as estimates resolve.
            // Keep the same message at the same viewport position instead.
            let proposed = tableView.rectForRow(at: indexPath).minY - readingAnchor.viewportOffset
            target = min(bottomOffset, max(-topInset, proposed))
        } else {
            return
        }
        if abs(tableView.contentOffset.y - target) > 0.5 {
            // This is a coordinate correction, not a scroll. Animating it makes
            // the title drift while SwiftUI independently animates the body.
            let correctOffset = { [self] in
                tableView.contentOffset.y = target
                // Self-sizing can move a cell during this layout pass while its
                // hosting content still has the old position (especially at large text sizes).
                for cell in tableView.visibleCells {
                    cell.setNeedsLayout()
                    cell.layoutIfNeeded()
                }
            }
            if anchorsDisclosure { UIView.performWithoutAnimation(correctOffset) }
            else { correctOffset() }
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isUserScrolling { captureReadingAnchor() }
        reportBottomMessage()
    }

    private func captureReadingAnchor() {
        guard let indexPath = tableView.indexPathsForVisibleRows?.first,
              let id = dataSource.itemIdentifier(for: indexPath) else { return }
        readingAnchor = ReadingAnchor(id: id,
                                      viewportOffset: tableView.rectForRow(at: indexPath).minY - tableView.contentOffset.y)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserScrolling = true
        anchorsDisclosure = false
        followsOutput = false
        reportBottomMessage()
        captureReadingAnchor()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // The composer is hosted beside the table, so UIKit's interactive dismissal
        // does not always find its responder. Finish a downward dismiss gesture locally.
        if scrollView.panGestureRecognizer.translation(in: scrollView).y > 40 {
            footerHost.view.endEditing(true)
        }
        if !decelerate { finishUserScrolling() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishUserScrolling()
    }

    private func finishUserScrolling() {
        isUserScrolling = false
        followsOutput = abs(tableView.contentOffset.y - bottomOffset) <= 20
        if followsOutput { readingAnchor = nil }
        else { captureReadingAnchor() }
        view.setNeedsLayout()
        reportBottomMessage()
    }

    private func reportBottomMessage() {
        // Defer SwiftUI state writes until the representable update has ended,
        // then recheck geometry so a queued notification cannot certify old layout.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let atBottom = self.tableView.window != nil && self.tableView.bounds.height > 0 &&
                !self.needsReceiptLayout && !self.applyingSnapshot && !self.isUserScrolling &&
                self.followsOutput && abs(self.tableView.contentOffset.y - self.bottomOffset) <= 20
            let timestamp = atBottom ? self.messageTimestamp : nil
            guard timestamp != self.reportedBottomMessage else { return }
            self.reportedBottomMessage = timestamp
            self.onBottomMessage(timestamp)
        }
    }
}

/// Pin the hosting view to the cell edges so self-sizing does not translate
/// the disclosure header while its body animates.
private final class ConversationTurnCell: UITableViewCell {
    private let host = UIHostingController(rootView: AnyView(EmptyView()))
    private weak var owner: UIViewController?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        host.safeAreaRegions = []
        host.sizingOptions = .intrinsicContentSize
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func setContent<Content: View>(parent: UIViewController?, @ViewBuilder content: () -> Content) {
        owner = parent
        if host.parent == nil, let parent {
            parent.addChild(host)
            host.didMove(toParent: parent)
        }
        host.rootView = AnyView(content())
        host.view.invalidateIntrinsicContentSize()
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize,
                                          withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                          verticalFittingPriority: UILayoutPriority) -> CGSize {
        host.sizeThatFits(in: CGSize(width: targetSize.width, height: .greatestFiniteMagnitude))
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil, host.parent != nil {
            host.willMove(toParent: nil)
            host.removeFromParent()
        } else if superview != nil, host.parent == nil, let owner {
            owner.addChild(host)
            host.didMove(toParent: owner)
        }
    }
}

private final class ConversationTableView: UITableView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private final class ConversationFooterScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keyboard transitions can resize this viewport after the parent's
        // layout callback. Apply its pending bottom scroll at the final size.
        onLayout?()
    }
}

/// Measure at the actual available width. A hosting controller's unspecified-width
/// intrinsic size can under-measure a multiline text field and clip its controls.
private struct MeasuredConversationFooter<Content: View>: View {
    let content: Content
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                onHeightChange(height)
            }
    }
}
