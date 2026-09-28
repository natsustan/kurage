import SwiftUI

struct ConversationSubtasksButton: View {
    let subtasks: [ConversationSubtask]
    let onOpen: (ConversationSubtask) -> Void
    @State private var showsTasks = false
    @State private var pendingSelection: ConversationSubtask?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button { showsTasks.toggle() } label: {
            Label("\(subtasks.count) agents", systemImage: "person.2")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .foregroundStyle(showsTasks ? Color(uiColor: .systemBackground) : .primary)
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(showsTasks ? .primary : .clear), in: .capsule)
        .accessibilityIdentifier("conversation-subtasks")
        .accessibilityHint("View subtasks created from this conversation")
        .popover(isPresented: $showsTasks, arrowEdge: .bottom) {
            ConversationSubtasksPopover(subtasks: subtasks) { subtask in
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
    let onSelect: (ConversationSubtask) -> Void
    @State private var contentHeight: CGFloat = 240

    private var groups: [(status: ConversationSubtask.Status, tasks: [ConversationSubtask])] {
        [ConversationSubtask.Status.running, .pending, .failed, .completed].compactMap { status in
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
                                        .fill(subtask.status.color)
                                        .frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(subtask.title)
                                            .font(.subheadline.weight(.medium))
                                            .multilineTextAlignment(.leading)
                                        Text(subtask.agentName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
                            .accessibilityValue(Text(subtask.status.label))
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
        .frame(width: 320, height: min(420, max(44, contentHeight)))
    }
}

struct ConversationSubtaskSheet: View {
    let subtask: ConversationSubtask?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let subtask {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(subtask.title).font(.headline)
                        Label(subtask.status.label, systemImage: "circle.fill")
                            .foregroundStyle(subtask.status.color)
                        Text(subtask.agentName).foregroundStyle(.secondary)
                        if let summary = subtask.summary { Text(summary).textSelection(.enabled) }
                        if let error = subtask.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                        if let tool = subtask.lastToolName { Text("Latest tool: \(tool)") }
                        if let model = subtask.modelID { Text("Model: \(model)") }
                        if let tokens = subtask.totalTokens { Text("\(tokens) tokens") }
                        if let tools = subtask.toolUses { Text("\(tools) tool uses") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                } else {
                    ContentUnavailableView("Task unavailable", systemImage: "person.crop.circle.badge.questionmark")
                }
            }
                .navigationTitle("Agent task")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("close-subtask")
                    }
                }
        }
        .presentationBackground(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("subtask-transcript")
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private extension ConversationSubtask.Status {
    var label: LocalizedStringKey {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }

    var color: Color {
        switch self {
        case .pending: .secondary
        case .running, .completed: .green
        case .failed: .red
        }
    }
}
