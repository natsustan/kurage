import SwiftUI
import UIKit

/// UIKit owns keyboard avoidance and scrolling; SwiftUI owns message and composer content.
struct ConversationLayout<Footer: View>: UIViewControllerRepresentable {
    let turns: [ConversationTurn]
    let isLoading: Bool
    let scrollRequestID: Int
    let onRefresh: () -> Void
    @ViewBuilder let footer: () -> Footer

    func makeUIViewController(context: Context) -> ConversationLayoutController<Footer> {
        ConversationLayoutController(footer: footer())
    }

    func updateUIViewController(_ controller: ConversationLayoutController<Footer>, context: Context) {
        controller.update(turns: turns, isLoading: isLoading, scrollRequestID: scrollRequestID,
                          footer: footer(), onRefresh: onRefresh)
    }
}

final class ConversationLayoutController<Footer: View>: UIViewController, UITableViewDelegate {
    private let contentView = UIView()
    private let tableView = ConversationTableView(frame: .zero, style: .plain)
    private let footerHost: UIHostingController<MeasuredConversationFooter<Footer>>
    private var footerHeightConstraint: NSLayoutConstraint!
    private let emptyHost = UIHostingController(rootView: ConversationEmptyState(isLoading: true))
    private var dataSource: UITableViewDiffableDataSource<Int, ConversationTurn.ID>!
    private var turnsByID: [ConversationTurn.ID: ConversationTurn] = [:]
    private var turns: [ConversationTurn] = []
    private var scrollRequestID = 0
    private struct ReadingAnchor {
        let id: ConversationTurn.ID
        let viewportOffset: CGFloat
    }

    private var readingAnchor: ReadingAnchor?
    private var followsOutput = true
    private var isUserScrolling = false
    private var isAdjustingLayout = false
    private var onRefresh: (() -> Void)?

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
        // A single layout guide moves the list and composer with the system keyboard.
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
        tableView.estimatedRowHeight = 100
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.automaticallyAdjustsScrollIndicatorInsets = false
        tableView.keyboardDismissMode = .interactive
        tableView.alwaysBounceVertical = true
        tableView.accessibilityIdentifier = "conversation-transcript"
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "turn")
        contentView.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        dataSource = UITableViewDiffableDataSource<Int, ConversationTurn.ID>(tableView: tableView) {
            [weak self] table, indexPath, id in
            let cell = table.dequeueReusableCell(withIdentifier: "turn", for: indexPath)
            guard let turn = self?.turnsByID[id] else { return cell }
            cell.backgroundColor = .clear
            cell.contentConfiguration = UIHostingConfiguration {
                TurnRow(author: turn.author, text: turn.text)
            }
            .margins(.horizontal, 20)
            .margins(.vertical, 14)
            return cell
        }

        install(emptyHost)
        install(footerHost)
        footerHeightConstraint = footerHost.view.heightAnchor.constraint(equalToConstant: 78)
        NSLayoutConstraint.activate([
            footerHeightConstraint,
            footerHost.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerHost.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footerHost.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            emptyHost.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            emptyHost.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            emptyHost.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            emptyHost.view.bottomAnchor.constraint(equalTo: footerHost.view.topAnchor)
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
    }

    private func install<Content: View>(_ host: UIHostingController<Content>) {
        addChild(host)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(host.view)
        host.didMove(toParent: self)
    }

    func update(turns: [ConversationTurn], isLoading: Bool, scrollRequestID: Int,
                footer: Footer, onRefresh: @escaping () -> Void) {
        loadViewIfNeeded()
        self.onRefresh = onRefresh
        footerHost.rootView = MeasuredConversationFooter(content: footer) { [weak self] height in
            guard let self, height.isFinite, height > 0,
                  abs(footerHeightConstraint.constant - height) > 0.5 else { return }
            footerHeightConstraint.constant = ceil(height)
            view.setNeedsLayout()
        }
        emptyHost.rootView = ConversationEmptyState(isLoading: isLoading)
        emptyHost.view.isHidden = !turns.isEmpty
        if self.scrollRequestID != scrollRequestID {
            self.scrollRequestID = scrollRequestID
            followsOutput = true
            readingAnchor = nil
        }
        if self.turns != turns {
            let oldTurns = turnsByID
            self.turns = turns
            turnsByID = Dictionary(uniqueKeysWithValues: turns.map { ($0.id, $0) })
            var snapshot = NSDiffableDataSourceSnapshot<Int, ConversationTurn.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(turns.map(\.id))
            snapshot.reconfigureItems(turns.compactMap { turn in
                guard let old = oldTurns[turn.id], old != turn else { return nil }
                return turn.id
            })
            dataSource.apply(snapshot, animatingDifferences: false)
        }
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        adjustTranscriptLayout()
    }

    private var bottomOffset: CGFloat {
        max(-tableView.contentInset.top,
            tableView.contentSize.height + tableView.contentInset.bottom - tableView.bounds.height)
    }

    private func adjustTranscriptLayout() {
        guard !isAdjustingLayout, tableView.window != nil, tableView.bounds.height > 0 else { return }
        isAdjustingLayout = true
        defer { isAdjustingLayout = false }

        let bottomInset = max(0, contentView.bounds.height - footerHost.view.frame.minY) + 6
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
            tableView.contentOffset.y = target
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isUserScrolling { captureReadingAnchor() }
    }

    private func captureReadingAnchor() {
        guard let indexPath = tableView.indexPathsForVisibleRows?.first,
              let id = dataSource.itemIdentifier(for: indexPath) else { return }
        readingAnchor = ReadingAnchor(id: id,
                                      viewportOffset: tableView.rectForRow(at: indexPath).minY - tableView.contentOffset.y)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserScrolling = true
        followsOutput = false
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
    }
}

private final class ConversationTableView: UITableView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
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
