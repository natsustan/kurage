import SwiftUI

struct ConversationChangesHUD: View {
    let summary: FileChangeSummary
    var compact = false
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    fileCount
                    FileChangeCounts(additions: summary.additions, deletions: summary.deletions)
                }
                fileCount
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
        .accessibilityIdentifier("conversation-changes-hud")
        .accessibilityHint("View file changes recorded in this conversation")
    }

    @ViewBuilder
    private var fileCount: some View {
        if compact { Text("\(summary.count) files") }
        else { Label("\(summary.count) files changed", systemImage: "doc.text") }
    }
}

struct FileChangeCounts: View {
    let additions: Int?
    let deletions: Int?

    var body: some View {
        HStack(spacing: 6) {
            if let additions {
                Text("+\(additions)")
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(additions) added lines")
            }
            if let deletions {
                Text("−\(deletions)")
                    .foregroundStyle(.red)
                    .accessibilityLabel("\(deletions) removed lines")
            }
        }
        .monospacedDigit()
        .fixedSize()
    }
}

struct ConversationChangesView: View {
    let groups: [ConversationFileChangeGroup]
    let latestTurnNumber: Int
    var initialTurnNumber: Int? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var detent: PresentationDetent = .large
    @State private var showsAllTurns = false

    private var visibleGroups: [ConversationFileChangeGroup] {
        showsAllTurns ? groups : groups.filter { $0.turnNumber == (initialTurnNumber ?? latestTurnNumber) }
    }

    private var drawerBackground: Color {
        Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground)
    }

    var body: some View {
        VStack(spacing: 0) {
            FileChangesHeader(
                summary: FileChangeSummary(visibleGroups),
                showsAllTurns: $showsAllTurns,
                turnTitle: initialTurnNumber == nil ? "Last turn" : "This turn",
                expanded: detent == .large,
                onResize: { detent = detent == .large ? .medium : .large },
                onClose: { dismiss() }
            )
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if visibleGroups.isEmpty {
                        ContentUnavailableView("No recorded changes", systemImage: "doc.text")
                    }
                    ForEach(visibleGroups) { group in
                        FileChangeTurnSection(group: group, showsHeading: showsAllTurns)
                    }
                }
                .padding(16)
            }
            .accessibilityIdentifier("file-changes-list")
        }
        .background(drawerBackground)
        .presentationBackground(drawerBackground)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(40)
    }
}

private struct FileChangesHeader: View {
    let summary: FileChangeSummary
    @Binding var showsAllTurns: Bool
    let turnTitle: String
    let expanded: Bool
    let onResize: () -> Void
    let onClose: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Color.clear.frame(width: 96, height: 1)
                    .accessibilityHidden(true)
                FileChangesScopePicker(summary: summary, showsAllTurns: $showsAllTurns, turnTitle: turnTitle)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity)
                FileChangesWindowControls(expanded: expanded, onResize: onResize, onClose: onClose)
            }
            VStack(spacing: 12) {
                FileChangesScopePicker(summary: summary, showsAllTurns: $showsAllTurns, turnTitle: turnTitle)
                FileChangesWindowControls(expanded: expanded, onResize: onResize, onClose: onClose)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

private struct FileChangesScopePicker: View {
    let summary: FileChangeSummary
    @Binding var showsAllTurns: Bool
    let turnTitle: String

    var body: some View {
        VStack(spacing: 2) {
            Menu {
                Picker("Recorded changes", selection: $showsAllTurns) {
                    Text(turnTitle).tag(false)
                    Text("All turns").tag(true)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(showsAllTurns ? "All turns" : turnTitle)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
                .font(.headline)
                .foregroundStyle(.primary)
            }
            .tint(.primary)
            .accessibilityIdentifier("file-changes-title")
            .accessibilityHint("Choose which recorded turns to show")
            FileChangeCounts(additions: summary.additions, deletions: summary.deletions)
                .font(.caption.weight(.medium))
        }
    }
}

private struct FileChangesWindowControls: View {
    let expanded: Bool
    let onResize: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onResize) {
                Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(expanded ? "Collapse drawer" : "Expand drawer")
            .accessibilityIdentifier("resize-file-changes")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close file changes")
            .accessibilityIdentifier("close-file-changes")
        }
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

private struct FileChangeTurnSection: View {
    let group: ConversationFileChangeGroup
    let showsHeading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeading {
                Text("Turn \(group.turnNumber)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ForEach(group.files) { file in
                FileChangeCard(file: file)
            }
        }
    }
}

private struct FileChangeCard: View {
    let file: ConversationFileChange
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                FileChangeCardHeader(file: file)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("changed-file-\(file.path)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Show or hide recorded code differences")
            .background(Color.primary.opacity(0.09))
            if expanded {
                FileChangeCardDetails(file: file)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .systemBackground))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct FileChangeCardHeader: View {
    let file: ConversationFileChange

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: file.name).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    FileChangeCounts(additions: file.additions, deletions: file.deletions).font(.caption)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: file.name).font(.subheadline.weight(.semibold))
                    FileChangeCounts(additions: file.additions, deletions: file.deletions).font(.caption)
                }
            }
            if !file.directory.isEmpty {
                Text(verbatim: file.directory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .foregroundStyle(.primary)
    }
}

private struct FileChangeCardDetails: View {
    let file: ConversationFileChange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if file.edits.isEmpty && file.previewLimited != true {
                Text("Code preview unavailable for this file.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !file.edits.isEmpty {
                Text("Recorded excerpt · relative line numbers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(file.edits) { edit in
                    RecordedFileDiffView(edit: edit)
                }
            }
            if file.previewLimited == true {
                Text("Some code differences are omitted from this preview.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RecordedFileDiffView: View {
    let edit: ConversationFileEdit
    @State private var lines: [FileDiffLine]?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if loading {
                ProgressView()
            } else if let lines {
                if lines.isEmpty {
                    Text("No text differences").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(lines) { line in
                                FileDiffLineView(line: line)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Text("This code difference is too large to preview.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .task(id: edit) {
            loading = true
            let task = Task.detached(priority: .userInitiated) { RecordedFileDiff.lines(for: edit) }
            let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled else { return }
            lines = result
            loading = false
        }
    }
}

private struct FileDiffLineView: View {
    let line: FileDiffLine
    @ScaledMetric(relativeTo: .caption) private var lineNumberWidth = 36

    private var tint: Color {
        switch line.kind {
        case .addition: .green
        case .deletion: .red
        case .context, .gap: .clear
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text((line.newNumber ?? line.oldNumber).map(String.init) ?? "")
                .foregroundStyle(.secondary)
                .frame(width: lineNumberWidth, alignment: .trailing)
            Text(line.kind == .addition ? "+" : line.kind == .deletion ? "−" : " ")
                .fixedSize()
            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .fixedSize(horizontal: true, vertical: false)
                .textSelection(.enabled)
            Spacer(minLength: 8)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.vertical, 3)
        .background(tint.opacity(0.16))
        .accessibilityElement(children: .combine)
    }
}

struct TurnFileChangesCard: View {
    let group: ConversationFileChangeGroup
    let onOpen: () -> Void
    var onToggle: (TimeInterval) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                onToggle(reduceMotion ? 0 : 0.25)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    expanded.toggle()
                }
            } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Text("\(group.files.count) files changed").fontWeight(.medium)
                        counts
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(group.files.count) files changed").fontWeight(.medium)
                            counts
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("turn-changes-toggle-\(group.id)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(spacing: 0) {
                    ForEach(group.files.prefix(3)) { file in
                        VStack(spacing: 0) {
                            Divider()
                            Button(action: onOpen) {
                                HStack(spacing: 10) {
                                    Text(verbatim: file.path)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    FileChangeCounts(additions: file.additions, deletions: file.deletions)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("turn-changed-file-\(file.path)")
                        }
                    }
                    if group.files.count > 3 {
                        Divider()
                        Button(action: onOpen) {
                            HStack {
                                Text("View \(group.files.count - 3) more files")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("turn-changes-more-\(group.id)")
                    }
                }
                .transition(.opacity)
            }
        }
        .font(.footnote)
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var counts: some View {
        let summary = FileChangeSummary([group])
        return FileChangeCounts(additions: summary.additions, deletions: summary.deletions)
    }
}
