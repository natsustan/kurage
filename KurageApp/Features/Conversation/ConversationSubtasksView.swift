import SwiftUI
import KurageCore

struct ConversationSubtasksButton: View {
    let subtasks: [ConversationSubtask]
    let onOpen: (ConversationSubtask) -> Void
    @State private var showsTasks = false
    @State private var pendingSelection: ConversationSubtask?
    @State private var colorsByID: [ConversationSubtask.ID: Color] = [:]
    @Environment(\.scenePhase) private var scenePhase
    private static let agentColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .cyan]

    var body: some View {
        Button { showsTasks.toggle() } label: {
            Label {
                Text(subtasks.count == 1 ? "1 agent" : "\(subtasks.count) agents")
            } icon: {
                Image("robot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassEffect(.regular.tint(showsTasks ? .primary : .clear), in: .capsule)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .foregroundStyle(showsTasks ? Color(uiColor: .systemBackground) : .primary)
        .buttonStyle(.plain)
        .accessibilityIdentifier("conversation-subtasks")
        .accessibilityHint("View the subagents this conversation spawned")
        .popover(isPresented: $showsTasks, arrowEdge: .bottom) {
            ConversationSubtasksPopover(subtasks: subtasks, colorsByID: colorsByID) { subtask in
                pendingSelection = subtask
                showsTasks = false
            }
            .presentationCompactAdaptation(.popover)
            .onDisappear {
                // Present the task details after the task picker has dismissed.
                if let selection = pendingSelection {
                    pendingSelection = nil
                    onOpen(selection)
                }
            }
        }
        .onChange(of: subtasks.map(\.id), initial: true) { _, ids in
            // Allocate once per identity; status regrouping and deleted rows
            // must not change the colors of the agents still being followed.
            var updatedColors = colorsByID
            for id in ids where updatedColors[id] == nil {
                updatedColors[id] = Self.agentColors[updatedColors.count % Self.agentColors.count]
            }
            colorsByID = updatedColors
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                pendingSelection = nil
                showsTasks = false
            }
        }
    }
}

private struct ConversationSubtasksPopover: View {
    let subtasks: [ConversationSubtask]
    let colorsByID: [ConversationSubtask.ID: Color]
    let onSelect: (ConversationSubtask) -> Void
    @State private var contentHeight: CGFloat = 240
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var statusLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
    }

    private var groups: [(status: ConversationSubtask.Status, tasks: [ConversationSubtask])] {
        [ConversationSubtask.Status.running, .pending, .failed, .unknown, .cancelled, .completed].compactMap { status in
            let tasks = subtasks.filter { $0.status == status }
            return tasks.isEmpty ? nil : (status, tasks)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.status) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.status.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                        ForEach(group.tasks) { subtask in
                            Button { onSelect(subtask) } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(colorsByID[subtask.id] ?? .blue)
                                        .frame(width: 10, height: 10)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(subtask.title)
                                            .font(.subheadline.weight(.medium))
                                            .multilineTextAlignment(.leading)
                                        statusLayout {
                                            Text(subtask.status.rowLabel)
                                                .foregroundStyle(subtask.status == .failed ? Color.red : .secondary)
                                                .fixedSize(horizontal: true, vertical: false)
                                            if subtask.status == .running,
                                               let detail = subtask.progressSummary ?? subtask.lastToolName {
                                                Text(dynamicTypeSize.isAccessibilitySize ? detail : "· \(detail)")
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        .font(.caption)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("subtask-\(subtask.id)")
                            .accessibilityValue(Text(subtask.status.rowLabel))
                        }
                    }
                }
                if subtasks.isEmpty {
                    Text("No subtasks")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subtask-list")
        .frame(width: 320, height: min(420, max(44, contentHeight)))
    }
}

struct ConversationSubtaskSheet: View {
    let subtask: ConversationSubtask?
    var projectName: String? = nil
    var machineName: String? = nil
    var onRefresh: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var detent: PresentationDetent = .medium
    @State private var showsInfo = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityIdentifier("close-subtask")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(subtask?.title ?? "Agent task")
                            .font(.headline)
                            .lineLimit(2)
                            .accessibilityIdentifier("subtask-title")
                        if subtask?.status == .running || subtask?.status == .pending {
                            Circle()
                                .fill(subtask?.status.color ?? .secondary)
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                        }
                    }
                    let subtitle = [projectName, machineName].compactMap { value in
                        value?.isEmpty == false ? value : nil
                    }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("subtask-context")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let subtask, subtask.run != nil {
                    Button { showsInfo.toggle() } label: {
                        Label("Agent info", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityIdentifier("subtask-info")
                    .accessibilityValue(subtask.status.label)
                    .popover(isPresented: $showsInfo) {
                        ConversationSubtaskMetadata(subtask: subtask)
                            .padding(16)
                            .frame(width: 280, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            Group {
                if let subtask, let run = subtask.run {
                    ConversationSubtaskTranscript(subtask: subtask, run: run, onRefresh: onRefresh)
                } else {
                    ConversationSubtaskLegacyDetails(subtask: subtask)
                }
            }
        }
        .presentationBackground(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subtask-transcript")
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }
}

private struct ConversationSubtaskTranscript: View {
    let subtask: ConversationSubtask
    let run: ConversationSubtask.Run
    let onRefresh: () -> Void

    var body: some View {
        Group {
            if run.turns.isEmpty {
                ScrollView {
                    ConversationSubtaskRunNotes(subtask: subtask, run: run)
                }
            } else {
                ConversationLayout(
                    turns: run.turns,
                    isLoading: false,
                    isRunning: subtask.status == .running || subtask.status == .pending,
                    startsAtTop: true,
                    scrollRequestID: 0,
                    loadImage: { _, _ in throw LodyClientError.notConnected },
                    onPreviewImage: { _ in },
                    onRefresh: onRefresh
                ) {
                    ConversationSubtaskRunNotes(subtask: subtask, run: run)
                }
            }
        }
    }
}

private struct ConversationSubtaskMetadata: View {
    let subtask: ConversationSubtask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(subtask.status.label, systemImage: "circle.fill")
                .foregroundStyle(subtask.status.color)
            if let model = subtask.modelID { Text("Model: \(model)") }
            if let tokens = subtask.totalTokens { Text("\(tokens) tokens") }
            if let tools = subtask.toolUses { Text("\(tools) tool uses") }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

private struct ConversationSubtaskRunNotes: View {
    let subtask: ConversationSubtask
    let run: ConversationSubtask.Run

    private var hasOutput: Bool {
        run.turns.contains { $0.author == .agent && (!$0.parts.isEmpty || $0.displayedWork != nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !run.plan.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plan").font(.subheadline.weight(.semibold))
                    ForEach(Array(run.plan.enumerated()), id: \.offset) { _, entry in
                        Label(entry.content, systemImage: entry.status == .completed ? "checkmark.circle" :
                            entry.status == .inProgress ? "circle.dotted" : "circle")
                    }
                }
            }
            if !hasOutput {
                if !run.streamsOutput {
                    Text("This agent reports its status and result, not its individual steps.")
                } else if subtask.status == .running || subtask.status == .pending {
                    Text("Waiting for the first step…")
                } else {
                    Text("No steps were received.")
                }
            }
            if let progress = subtask.progressSummary, subtask.status == .running {
                Text(progress)
            }
            if run.outputIncomplete { Text("Some steps of this run were not received.") }
            if subtask.status == .unknown {
                Text("Lody lost track of this run. It may still be running, or may have stopped.")
            }
            if let error = subtask.error { Text(error).foregroundStyle(.red) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}

private struct ConversationSubtaskLegacyDetails: View {
    let subtask: ConversationSubtask?
    private var steps: [ConversationSubtask.Step] { subtask?.steps ?? [] }

    var body: some View {
        ScrollView {
            if let subtask {
                VStack(alignment: .leading, spacing: 16) {
                    Label(subtask.status.label, systemImage: "circle.fill")
                        .foregroundStyle(subtask.status.color)
                    if subtask.agentName != subtask.title {
                        Text(subtask.agentName).foregroundStyle(.secondary)
                    }
                    if let summary = subtask.summary { Text(summary).textSelection(.enabled) }
                    if let error = subtask.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    if let tool = subtask.lastToolName { Text("Latest tool: \(tool)") }
                    if let model = subtask.modelID { Text("Model: \(model)") }
                    if let tokens = subtask.totalTokens { Text("\(tokens) tokens") }
                    if let tools = subtask.toolUses { Text("\(tools) tool uses") }
                    if steps.count > 1 { stepsList(steps) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            } else {
                ContentUnavailableView("Task unavailable", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
    }

    /// What the subagent ran through, oldest first. A single-step subagent has
    /// nothing beyond what the header already shows.
    private func stepsList(_ steps: [ConversationSubtask.Step]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steps")
                .font(.subheadline.weight(.semibold))
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(step.status.color)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                        if let summary = step.summary {
                            Text(summary).font(.footnote).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let error = step.error {
                            Text(error).font(.footnote).foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private extension ConversationSubtask.Status {
    var rowLabel: LocalizedStringResource {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .completed: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .unknown: "Status unknown"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .unknown: "Status unknown"
        }
    }

    var color: Color {
        switch self {
        case .pending, .cancelled, .unknown: .secondary
        case .running, .completed: .green
        case .failed: .red
        }
    }
}
