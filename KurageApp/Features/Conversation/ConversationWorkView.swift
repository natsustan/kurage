import SwiftUI
import KurageCore

/// Disclosure state owned by the transcript, so reconfigured or reused cells
/// restore what the reader opened.
struct TurnDisclosures {
    /// Read when a disclosure appears, including one nested in a reopened group.
    var isExpanded: @MainActor (String) -> Bool = { _ in false }
    /// Key and new expanded state, recorded before the row begins resizing.
    var onToggle: @MainActor (String, Bool) -> Void = { _, _ in }
}

/// "Worked for …" above a finished reply. Expanding reveals the earlier work;
/// the divider separates it from the answer, as in Lody.
struct TurnWorkDisclosure<Content: View>: View {
    let turnID: ConversationTurn.ID
    let work: ConversationWork
    let disclosures: TurnDisclosures
    @ViewBuilder let content: () -> Content
    @State private var expanded: Bool

    init(turnID: ConversationTurn.ID, work: ConversationWork, disclosures: TurnDisclosures,
         @ViewBuilder content: @escaping () -> Content) {
        self.turnID = turnID
        self.work = work
        self.disclosures = disclosures
        self.content = content
        _expanded = State(initialValue: disclosures.isExpanded(Self.key(turnID)))
    }

    static func key(_ turnID: ConversationTurn.ID) -> String { "work:\(turnID)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                let next = !expanded
                disclosures.onToggle(Self.key(turnID), next)
                expanded = next
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(work.title)
                    DisclosureChevron(expanded: expanded)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("turn-work-toggle-\(turnID)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides the work before this reply" : "Shows the work before this reply")
            TopAnchoredDisclosure(expanded: expanded) {
                VStack(alignment: .leading, spacing: 8) { content() }
                    .padding(.bottom, 12)
            }
            Divider()
        }
        .clipped()
        .padding(.bottom, 4)
    }
}

/// A group of tool calls, e.g. "Ran 3 commands · Read 2 files". Titles are
/// listed when the group is opened; tool output is not shown.
struct ConversationActivityRow: View {
    let turnID: ConversationTurn.ID
    let activity: ConversationActivity
    let disclosures: TurnDisclosures
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth = 20.0
    @ScaledMetric(relativeTo: .caption) private var stepIconWidth = 14.0
    @State private var expanded: Bool

    init(turnID: ConversationTurn.ID, activity: ConversationActivity, disclosures: TurnDisclosures) {
        self.turnID = turnID
        self.activity = activity
        self.disclosures = disclosures
        _expanded = State(initialValue: disclosures.isExpanded("activity:\(turnID):\(activity.id)"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if activity.steps.isEmpty {
                header(showsChevron: false)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("turn-activity-\(activity.id)")
            } else {
                Button {
                    let next = !expanded
                    disclosures.onToggle("activity:\(turnID):\(activity.id)", next)
                    expanded = next
                } label: {
                    header(showsChevron: true)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("turn-activity-\(activity.id)")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            }
            TopAnchoredDisclosure(expanded: expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activity.steps) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(step.kind.imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: stepIconWidth, height: stepIconWidth)
                                .alignmentGuide(.firstTextBaseline) { $0.height * 0.8 }
                                .accessibilityHidden(true)
                            Text(verbatim: step.title)
                                .font(.caption.monospaced())
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 28)
                .padding(.bottom, 8)
            }
        }
        .clipped()
    }

    private func header(showsChevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(activity.primaryKind.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: iconWidth, height: iconWidth)
                .alignmentGuide(.firstTextBaseline) { $0.height * 0.8 }
                .accessibilityHidden(true)
            Text(activity.summary)
            if showsChevron {
                DisclosureChevron(expanded: expanded)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct DisclosureChevron: View {
    let expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var iconWidth = 12.0

    var body: some View {
        Image("disclosure-right")
            .resizable()
            .scaledToFit()
            .frame(width: iconWidth, height: iconWidth)
            .alignmentGuide(.firstTextBaseline) { $0.height * 0.8 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { image in
                image.rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .transaction { $0.disablesAnimations = false }
            .accessibilityHidden(true)
    }
}

extension ConversationActivity.Kind {
    var imageName: String {
        switch self {
        case .command: "terminal"
        case .read: "activity-read"
        case .edit: "pencil"
        case .search: "activity-search"
        case .fetch: "activity-fetch"
        case .tool: "activity-tool"
        }
    }
}

/// Reveal the body from its top edge while its contents keep their full size.
/// The same layout serves work, activity groups, and file changes.
struct TopAnchoredDisclosure<Content: View>: View {
    let expanded: Bool
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                content()
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.modifier(active: TopDownReveal(progress: 0),
                                          identity: TopDownReveal(progress: 1)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: expanded)
        .transaction { $0.disablesAnimations = false }
    }
}

@Animatable
private struct TopDownReveal: ViewModifier {
    var progress: CGFloat

    func body(content: Content) -> some View {
        TopDownDisclosureLayout(progress: progress) {
            content
        }
        .clipped()
    }
}

@Animatable
private struct TopDownDisclosureLayout: Layout {
    var progress: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let fullSize = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: fullSize.width, height: fullSize.height * progress)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        content.place(at: bounds.origin, anchor: .topLeading,
                      proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

struct TurnWorkingLabel: View {
    let turnID: ConversationTurn.ID
    let timing: ConversationTiming
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.animation(minimumInterval: 1, paused: scenePhase != .active)) { context in
                Text(timing.title(at: context.date))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("turn-working-\(turnID)")
            }
            Divider()
        }
        .padding(.bottom, 4)
    }
}
