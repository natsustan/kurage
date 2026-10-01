import SwiftUI

typealias FilePreviewLoader = @MainActor (ConversationFileChangeGroup, ConversationFileChange) async throws -> ConversationFilePreview

struct ConversationChangesHUD: View {
    let summary: FileChangeSummary
    var compact = false
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    fileCount
                    FileChangeCounts(additions: summary.additions, deletions: summary.deletions)
                }
                fileCount
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("conversation-changes-hud")
        .accessibilityHint("View file changes recorded in this conversation")
    }

    @ViewBuilder
    private var fileCount: some View {
        FileChangeCountText(count: summary.count, compact: compact)
    }
}

private struct FileChangeCountText: View {
    let count: Int
    var compact = false

    var body: some View {
        if compact {
            if count == 1 { Text("1 file") }
            else { Text("\(count) files") }
        } else {
            if count == 1 { Text("1 file changed") }
            else { Text("\(count) files changed") }
        }
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
    let loadPreview: FilePreviewLoader?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var detent: PresentationDetent = .large
    @State private var showsAllTurns: Bool

    init(groups: [ConversationFileChangeGroup], latestTurnNumber: Int, initialTurnNumber: Int? = nil,
         loadPreview: FilePreviewLoader? = nil) {
        self.groups = groups
        self.latestTurnNumber = latestTurnNumber
        self.initialTurnNumber = initialTurnNumber
        self.loadPreview = loadPreview
        _showsAllTurns = State(initialValue: initialTurnNumber == nil)
    }

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
                        FileChangeTurnSection(group: group, showsHeading: showsAllTurns, loadPreview: loadPreview)
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
    let loadPreview: FilePreviewLoader?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeading {
                Text("Turn \(group.turnNumber)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ForEach(group.files) { file in
                FileChangeCard(group: group, file: file, loadPreview: loadPreview)
            }
        }
    }
}

private struct FileChangeCard: View {
    let group: ConversationFileChangeGroup
    let file: ConversationFileChange
    let loadPreview: FilePreviewLoader?
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
                FileChangeCardDetails(group: group, file: file, loadPreview: loadPreview)
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

struct FileChangeCardDetails: View {
    let group: ConversationFileChangeGroup
    let file: ConversationFileChange
    let loadPreview: FilePreviewLoader?
    @Environment(\.scenePhase) private var scenePhase
    @State private var preview: ConversationFilePreview?
    @State private var loadedFile: ConversationFileChange?
    @State private var failed = false
    @State private var attempt = 0
    @State private var completedAttempt: Int?

    private struct LoadKey: Equatable {
        let file: ConversationFileChange
        let active: Bool
        let attempt: Int
    }

    var body: some View {
        let currentPreview = loadedFile == file ? preview : nil
        VStack(alignment: .leading, spacing: 0) {
            if let edit = currentPreview?.edit, currentPreview?.status == .ready {
                RecordedFileDiffView(edit: edit, fallbackEdits: file.edits, fallbackLimited: file.previewLimited == true)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("historical-file-diff-\(file.path)")
            } else {
                if loadPreview != nil {
                    if let currentPreview {
                        FilePreviewNotice(message: currentPreview.explanation,
                                          onRetry: currentPreview.canRetry ? { attempt += 1 } : nil)
                    } else if failed && loadedFile == file {
                        FilePreviewNotice(message: "Could not load the code preview. Check the session machine and connection, then retry.") {
                            attempt += 1
                        }
                    } else {
                        ProgressView("Loading code preview…")
                            .font(.footnote)
                            .padding(12)
                            .accessibilityIdentifier("file-preview-loading")
                    }
                } else if file.edits.isEmpty && file.previewLimited != true {
                    Text("Code preview unavailable for this file.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
                RecordedFileExcerptsView(edits: file.edits, limited: file.previewLimited == true)
            }
        }
        .task(id: LoadKey(file: file, active: scenePhase == .active, attempt: attempt)) {
            guard scenePhase == .active, let loadPreview else { return }
            // A completed preview survives backgrounding. In-flight loads are
            // cancelled by the task identity and resumed when the scene activates.
            if loadedFile == file && preview != nil && completedAttempt == attempt { return }
            loadedFile = file
            preview = nil
            failed = false
            do {
                let result = try await loadPreview(group, file)
                try Task.checkCancellation()
                preview = result
                completedAttempt = attempt
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                failed = true
            }
        }
    }
}

private struct RecordedFileExcerptsView: View {
    let edits: [ConversationFileEdit]
    let limited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !edits.isEmpty {
                Text("Recorded excerpt · relative line numbers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            ForEach(edits) { edit in
                RecordedFileDiffView(edit: edit)
            }
            if limited {
                Text("Some code differences are omitted from this preview.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
    }
}

private struct FilePreviewNotice: View {
    let message: LocalizedStringResource
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.footnote).foregroundStyle(.secondary)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .font(.footnote.weight(.medium))
                    .accessibilityIdentifier("retry-file-preview")
            }
        }
        .padding(12)
    }
}

private struct RecordedFileDiffView: View {
    let edit: ConversationFileEdit
    var fallbackEdits: [ConversationFileEdit] = []
    var fallbackLimited = false
    @State private var preview: RecordedFileDiff.Preview?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch preview {
            case nil:
                ProgressView()
            case .ready(let hunks, let truncated):
                if hunks.isEmpty {
                    Text("No text differences").font(.footnote).foregroundStyle(.secondary).padding(12)
                } else {
                    ForEach(hunks) { hunk in
                        FileDiffHunkView(hunk: hunk)
                    }
                }
                if truncated {
                    Text("Showing part of the code difference. File totals include all changes.")
                        .font(.footnote).foregroundStyle(.secondary).padding(12)
                        .accessibilityIdentifier("file-preview-truncated")
                }
            case .unavailable(let reason):
                FilePreviewNotice(message: ConversationFilePreview(status: .unavailable, reason: reason).explanation)
                RecordedFileExcerptsView(edits: fallbackEdits, limited: fallbackLimited)
            }
        }
        .task(id: edit) {
            preview = nil
            let task = Task.detached(priority: .userInitiated) { RecordedFileDiff.preview(for: edit) }
            let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled else { return }
            preview = result
        }
    }
}

private struct FileDiffHunkView: View {
    let hunk: FileDiffHunk
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .caption) private var chevronSize = 16
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: chevronSize, height: chevronSize)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { image in
                            image.rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                        .transaction { $0.disablesAnimations = false }
                    Text("Lines \(hunk.firstNumber)–\(hunk.lastNumber)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    FileChangeCounts(additions: hunk.additions, deletions: hunk.deletions).font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("file-diff-hunk-\(hunk.id)")
            if expanded {
                Divider()
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(hunk.lines) { line in
                        FileDiffLineView(line: line)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay {
            Rectangle()
                .strokeBorder(Color(uiColor: .separator), lineWidth: 1 / displayScale)
                .allowsHitTesting(false)
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
            Text(line.newNumber.map(String.init) ?? (line.kind == .deletion ? "−" : ""))
                .foregroundStyle(.secondary)
                .frame(width: lineNumberWidth, alignment: .trailing)
                .padding(.trailing, 6)
                .background(tint.opacity(line.kind == .context ? 0 : 0.12))
                .accessibilityLabel(line.oldNumber.map { "Original line \($0)" } ?? "")
            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Spacer(minLength: 8)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.vertical, 3)
        .background(tint.opacity(0.16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(line.kind == .addition ? "Added line \(line.newNumber ?? 0), \(line.text)" :
                                line.kind == .deletion ? "Removed line \(line.oldNumber ?? 0), \(line.text)" :
                                "Line \(line.newNumber ?? 0), \(line.text)")
    }
}

struct TurnFileChangesCard: View {
    let group: ConversationFileChangeGroup
    let onOpen: () -> Void
    var onToggle: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                onToggle()
                expanded.toggle()
            } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        FileChangeCountText(count: group.files.count).fontWeight(.medium)
                        counts
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { image in
                                image.rotationEffect(.degrees(expanded ? 90 : 0))
                            }
                            .transaction { $0.disablesAnimations = false }
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            FileChangeCountText(count: group.files.count).fontWeight(.medium)
                            counts
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { image in
                                image.rotationEffect(.degrees(expanded ? 90 : 0))
                            }
                            .transaction { $0.disablesAnimations = false }
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("turn-changes-toggle-\(group.id)")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            TopAnchoredDisclosure(expanded: expanded) {
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
