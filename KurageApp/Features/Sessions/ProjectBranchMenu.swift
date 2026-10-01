import SwiftUI

/// Branches belong to the shared project directory, not the new session's metadata.
struct ProjectBranchMenu: View {
    let model: AppModel
    let projectID: String
    let templateSessionID: String
    let workspaceGeneration: Int
    let isDisabled: Bool
    let onSwitchFinished: () -> Void
    @Binding var isSwitching: Bool
    @Binding var requiresBranchRefresh: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var result = ProjectGitResult()
    @State private var isLoading = true
    @State private var attempt = 0
    @State private var selectedBranch: String?
    @State private var loadID = UUID()
    @State private var errorMessage = ""
    @State private var isErrorPresented = false
    @ScaledMetric(relativeTo: .body) private var iconWidth = 28

    private var isCurrent: Bool { model.workspaceGeneration == workspaceGeneration }
    private var canSwitch: Bool {
        isCurrent && !isDisabled && !isLoading && !isSwitching && !requiresBranchRefresh
    }
    private var title: String {
        if isSwitching { return "Switching branch…" }
        if isLoading { return "Loading branches…" }
        guard let state = result.state else { return "Branches unavailable" }
        return state.git ? state.branchName : "Not a Git repository"
    }

    var body: some View {
        Menu {
            if let state = result.state, state.git {
                Section("Branches") {
                    ForEach(state.choices) { branch in
                        Button {
                            guard canSwitch, branch.id != state.currentBranch else { return }
                            // Revalidate at the model/bridge boundary so stale
                            // dirty or busy snapshots do not block a new attempt.
                            isSwitching = true
                            requiresBranchRefresh = true
                            selectedBranch = branch.id
                            attempt += 1
                        } label: {
                            Label(branch.isRemote ? "\(branch.name) (remote)" : branch.name,
                                  systemImage: branch.id == state.currentBranch ? "checkmark" : "arrow.triangle.branch")
                        }
                        .disabled(!canSwitch || branch.id == state.currentBranch)
                        .accessibilityIdentifier("choose-branch-\(branch.id)")
                    }
                }
            }
            if result.failure != nil || requiresBranchRefresh {
                Button("Retry loading branches", systemImage: "arrow.clockwise") {
                    selectedBranch = nil
                    attempt += 1
                }
                .accessibilityIdentifier("refresh-project-branches")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").frame(width: iconWidth)
                Text(title).lineLimit(2)
                if isLoading || isSwitching { ProgressView() }
                else { Image(systemName: "chevron.up.chevron.down").font(.caption) }
            }
            .font(.body)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuOrder(.fixed)
        .foregroundStyle(.secondary)
        .disabled(isDisabled || isSwitching || !isCurrent || scenePhase != .active)
        .accessibilityLabel("Branch, \(title)")
        .accessibilityIdentifier("new-session-branch")
        .alert("Error", isPresented: $isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
                .accessibilityIdentifier("project-branch-error")
        }
        .task(id: "\(projectID):\(templateSessionID):\(workspaceGeneration):\(attempt):\(scenePhase)") {
            guard scenePhase == .active, isCurrent else { return }
            await load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cancel() }
        }
        .onDisappear { cancel() }
    }

    private func cancel() {
        loadID = UUID()
        if isSwitching {
            result = ProjectGitResult(failure: .switchUnconfirmed)
            onSwitchFinished()
        }
        selectedBranch = nil
        isSwitching = false
    }

    private func load() async {
        let id = UUID()
        loadID = id
        let branch = selectedBranch
        // Consume a switch once; subsequent appearance/background refreshes read only.
        selectedBranch = nil
        isLoading = true
        defer {
            if loadID == id {
                isLoading = false
                isSwitching = false
                if branch != nil { onSwitchFinished() }
            }
        }
        do {
            let loaded = try await model.projectGit(templateSessionID: templateSessionID, projectID: projectID, branch: branch)
            try Task.checkCancellation()
            guard isCurrent, loadID == id else { return }
            // A local guard can reject a switch without returning a snapshot.
            // Preserve the last confirmed branch; no mutation was sent for busy.
            result = ProjectGitResult(state: loaded.state ?? result.state, failure: loaded.failure)
            if loaded.state != nil || loaded.failure == .busy { requiresBranchRefresh = false }
            if branch != nil, let failure = loaded.failure { presentError(failure.message) }
        } catch {
            guard !Task.isCancelled, isCurrent, loadID == id else { return }
            let failure: ProjectGitFailure = branch == nil ? .unavailable : .switchUnconfirmed
            result = ProjectGitResult(state: result.state, failure: failure)
            if branch != nil { presentError(failure.message) }
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        isErrorPresented = true
    }
}
