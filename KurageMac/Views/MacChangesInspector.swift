import SwiftUI
import KurageCore

struct MacChangesInspector: View {
    let model: AppModel
    let sessionID: String
    let conversation: Conversation?
    let isAwake: Bool

    @State private var scope = Scope.branch
    @State private var selectedTurnID: String?
    @State private var branch: BranchFileChanges?
    @State private var branchError: String?
    @State private var refresh = 0

    fileprivate enum Scope: String, Hashable {
        case branch
        case history
    }

    private struct LoadKey: Hashable {
        let sessionID: String
        let workspaceGeneration: Int
        let scope: Scope
        let awake: Bool
        let refresh: Int
    }

    private var groups: [ConversationFileChangeGroup] {
        conversation?.fileChanges ?? []
    }

    private var selectedGroup: ConversationFileChangeGroup? {
        if let selectedTurnID, let group = groups.first(where: { $0.id == selectedTurnID }) {
            return group
        }
        return groups.last
    }

    var body: some View {
        VStack(spacing: 0) {
            MacChangesHeader(
                scope: $scope,
                selectedTurnID: $selectedTurnID,
                groups: groups,
                isReloading: scope == .branch && branch == nil && branchError == nil,
                reload: reload
            )
            Divider()
            MacChangesContent(
                model: model,
                sessionID: sessionID,
                scope: scope,
                branch: branch,
                branchError: branchError,
                group: selectedGroup,
                isAwake: isAwake,
                workspaceID: model.selectedWorkspaceID,
                workspaceGeneration: model.workspaceGeneration,
                refresh: refresh,
                retryBranch: reload
            )
        }
        .frame(minWidth: 300, idealWidth: 400)
        .task(id: LoadKey(sessionID: sessionID, workspaceGeneration: model.workspaceGeneration,
                          scope: scope, awake: isAwake, refresh: refresh)) {
            guard scope == .branch, isAwake, let workspaceID = model.selectedWorkspaceID else { return }
            branch = nil
            branchError = nil
            do {
                let result = try await model.branchChanges(sessionID: sessionID, workspaceID: workspaceID)
                try Task.checkCancellation()
                branch = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                branchError = "Could not load branch changes."
            }
        }
        .onChange(of: groups, initial: true) { oldGroups, newGroups in
            if selectedTurnID == nil || !newGroups.contains(where: { $0.id == selectedTurnID }) {
                selectedTurnID = newGroups.last?.id
            }
            if oldGroups != newGroups, scope == .branch { reload() }
        }
        .onChange(of: scope) { _, _ in refresh += 1 }
        .onChange(of: isAwake) { _, awake in
            if !awake {
                branch = nil
                branchError = nil
                refresh += 1
            }
        }
    }

    private func reload() {
        branch = nil
        branchError = nil
        refresh += 1
    }
}

private struct MacChangesHeader: View {
    @Binding var scope: MacChangesInspector.Scope
    @Binding var selectedTurnID: String?
    let groups: [ConversationFileChangeGroup]
    let isReloading: Bool
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Changes").font(.headline)
                Spacer()
                Button("Reload", systemImage: "arrow.clockwise", action: reload)
                    .labelStyle(.iconOnly)
                    .help("Reload changes")
                    .disabled(isReloading)
            }
            Picker("Scope", selection: $scope) {
                Text("Branch").tag(MacChangesInspector.Scope.branch)
                Text("History").tag(MacChangesInspector.Scope.history)
            }
            .pickerStyle(.segmented)
            if scope == .history {
                Picker("Turn", selection: $selectedTurnID) {
                    ForEach(groups) { group in
                        Text("Turn \(group.turnNumber)").tag(Optional(group.id))
                    }
                }
                .disabled(groups.isEmpty)
            }
        }
        .padding(12)
    }
}

private struct MacChangesContent: View {
    let model: AppModel
    let sessionID: String
    let scope: MacChangesInspector.Scope
    let branch: BranchFileChanges?
    let branchError: String?
    let group: ConversationFileChangeGroup?
    let isAwake: Bool
    let workspaceID: String?
    let workspaceGeneration: Int
    let refresh: Int
    let retryBranch: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if !isAwake {
                    ContentUnavailableView("Changes paused", systemImage: "moon.zzz",
                                           description: Text("Changes will reload after this Mac wakes."))
                } else if scope == .branch {
                    branchContent
                } else if let group {
                    ForEach(group.files) { file in
                        MacFileChangeDisclosure(model: model, sessionID: sessionID, file: file,
                                                source: .history(group.id), workspaceID: workspaceID,
                                                workspaceGeneration: workspaceGeneration, refresh: refresh)
                    }
                } else {
                    ContentUnavailableView("No recorded changes", systemImage: "doc.text")
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder private var branchContent: some View {
        if let branchError {
            MacChangesNotice(message: branchError, retry: retryBranch)
        } else if let branch {
            if branch.status == .unavailable {
                MacChangesNotice(message: String(localized: branch.explanation),
                                 retry: branch.reason == "unsupported" ? nil : retryBranch)
            } else if branch.files.isEmpty {
                ContentUnavailableView("No branch changes", systemImage: "doc.text")
            } else {
                ForEach(branch.files) { file in
                    MacFileChangeDisclosure(model: model, sessionID: sessionID, file: file,
                                            source: .branch, workspaceID: workspaceID,
                                            workspaceGeneration: workspaceGeneration, refresh: refresh)
                }
            }
        } else {
            ProgressView("Loading branch changes…").frame(maxWidth: .infinity)
        }
    }
}

private struct MacChangesNotice: View {
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            if let retry { Button("Retry", action: retry) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacFileChangeDisclosure: View {
    enum Source: Hashable { case branch, history(String) }

    let model: AppModel
    let sessionID: String
    let file: ConversationFileChange
    let source: Source
    let workspaceID: String?
    let workspaceGeneration: Int
    let refresh: Int

    @State private var expanded = false
    @State private var preview: RecordedFileDiff.Preview?
    @State private var unavailable: ConversationFilePreview?
    @State private var loadError: String?
    @State private var attempt = 0

    private struct PreviewKey: Equatable {
        let expanded: Bool
        let source: Source
        let file: ConversationFileChange
        let workspaceGeneration: Int
        let refresh: Int
        let attempt: Int
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            MacFilePreviewContent(preview: preview, unavailable: unavailable, loadError: loadError,
                                  retry: { attempt += 1 })
                .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).lineLimit(1)
                    if !file.directory.isEmpty {
                        Text(file.directory).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                MacChangeCounts(additions: file.additions, deletions: file.deletions)
            }
            .contentShape(Rectangle())
            .onTapGesture { expanded.toggle() }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .task(id: PreviewKey(expanded: expanded, source: source, file: file,
                             workspaceGeneration: workspaceGeneration,
                             refresh: refresh, attempt: attempt)) {
            preview = nil
            unavailable = nil
            loadError = nil
            guard expanded, let workspaceID else { return }
            do {
                let result: ConversationFilePreview
                switch source {
                case .branch:
                    result = try await model.branchFilePreview(sessionID: sessionID, path: file.path,
                                                               workspaceID: workspaceID)
                case .history(let turnID):
                    result = try await model.filePreview(sessionID: sessionID, turnID: turnID,
                                                         file: file, workspaceID: workspaceID)
                }
                try Task.checkCancellation()
                guard result.status == .ready, let edit = result.edit else {
                    unavailable = result
                    return
                }
                let diff = await RecordedFileDiff.previewInBackground(for: edit)
                try Task.checkCancellation()
                preview = diff
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                loadError = "Could not load this file preview."
            }
        }
    }
}

private struct MacFilePreviewContent: View {
    let preview: RecordedFileDiff.Preview?
    let unavailable: ConversationFilePreview?
    let loadError: String?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let loadError {
                MacChangesNotice(message: loadError, retry: retry)
            } else if let unavailable {
                MacChangesNotice(message: String(localized: unavailable.explanation),
                                 retry: unavailable.canRetry ? retry : nil)
            } else if let preview {
                switch preview {
                case .ready(let hunks, let truncated):
                    if hunks.isEmpty { Text("No text differences.").foregroundStyle(.secondary) }
                    ForEach(hunks) { hunk in MacDiffHunkView(hunk: hunk) }
                    if truncated { Text("Preview truncated.").font(.caption).foregroundStyle(.secondary) }
                case .unavailable(let reason):
                    Text(diffUnavailableMessage(reason)).foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Loading preview…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diffUnavailableMessage(_ reason: String) -> LocalizedStringResource {
        switch reason {
        case "snapshot_limit": "This file exceeds the preview limit of 10 MiB per snapshot."
        case "line_limit": "This file has too many lines to compare on this device."
        default: "This file has too many changes to compare on this device."
        }
    }
}

private struct MacDiffHunkView: View {
    let hunk: FileDiffHunk

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(hunk.lines) { line in MacDiffLineView(line: line) }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct MacDiffLineView: View {
    let line: FileDiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldNumber.map(String.init) ?? "").frame(width: 38, alignment: .trailing)
            Text(line.newNumber.map(String.init) ?? "").frame(width: 38, alignment: .trailing)
            Text(marker).frame(width: 22)
            Text(line.text.isEmpty ? " " : line.text).padding(.trailing, 8)
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(foreground)
        .background(background)
    }

    private var marker: String {
        switch line.kind { case .addition: "+"; case .deletion: "−"; default: " " }
    }

    private var foreground: Color {
        switch line.kind { case .addition: .green; case .deletion: .red; default: .primary }
    }

    private var background: Color {
        switch line.kind {
        case .addition: Color.green.opacity(0.1)
        case .deletion: Color.red.opacity(0.1)
        default: .clear
        }
    }
}

private struct MacChangeCounts: View {
    let additions: Int?
    let deletions: Int?

    var body: some View {
        HStack(spacing: 6) {
            if let additions { Text("+\(additions)").foregroundStyle(.green) }
            if let deletions { Text("−\(deletions)").foregroundStyle(.red) }
        }
        .font(.caption.monospacedDigit())
    }
}
