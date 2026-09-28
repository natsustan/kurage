import SwiftUI

/// Disclosure state owned by the transcript, so reconfigured or reused cells
/// restore what the reader opened.
struct TurnDisclosures {
    /// Read when a disclosure appears, including one nested in a reopened group.
    var isExpanded: @MainActor (String) -> Bool = { _ in false }
    /// Key, new expanded state, and the animation duration for the row resize.
    var onToggle: @MainActor (String, Bool, TimeInterval) -> Void = { _, _, _ in }
}

/// "Worked for …" above a finished reply. Expanding reveals the earlier work;
/// the divider separates it from the answer, as in Lody.
struct TurnWorkDisclosure<Content: View>: View {
    let turnID: ConversationTurn.ID
    let work: ConversationWork
    let disclosures: TurnDisclosures
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                disclosures.onToggle(Self.key(turnID), next, reduceMotion ? 0 : 0.25)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { expanded = next }
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
            .accessibilityIdentifier("turn-work-toggle-\(turnID)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides the work before this reply" : "Shows the work before this reply")
            if expanded {
                VStack(alignment: .leading, spacing: 8) { content() }
                    .padding(.bottom, 12)
                    .transition(.opacity)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    disclosures.onToggle("activity:\(turnID):\(activity.id)", next, reduceMotion ? 0 : 0.25)
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { expanded = next }
                } label: {
                    header(showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("turn-activity-\(activity.id)")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activity.steps) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: step.kind.symbolName)
                                .font(.caption)
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
                .transition(.opacity)
            }
        }
        .clipped()
    }

    private func header(showsChevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: activity.primaryKind.symbolName)
                .frame(width: 20)
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

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .imageScale(.small)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .accessibilityHidden(true)
    }
}

extension ConversationActivity.Kind {
    var symbolName: String {
        switch self {
        case .command: "apple.terminal"
        case .read: "doc.text"
        case .edit: "pencil"
        case .search: "magnifyingglass"
        case .fetch: "globe"
        case .tool: "wrench.and.screwdriver"
        }
    }
}
