import SwiftUI
import KurageCore

/// Read the branch of the shared project directory without changing it.
struct ProjectBranchRow: View {
    let model: AppModel
    let projectID: String
    let templateSessionID: String
    let workspaceGeneration: Int
    let isDisabled: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var result = ProjectGitResult()
    @State private var isLoading = true
    @State private var attempt = 0
    @State private var loadID = UUID()

    private var isCurrent: Bool { model.workspaceGeneration == workspaceGeneration }
    private var title: String {
        if isLoading { return String(localized: "Loading branch…", locale: locale) }
        if let failure = result.failure {
            var message = failure.message
            message.locale = locale
            return String(localized: message)
        }
        guard let state = result.state else { return String(localized: "Branch unavailable", locale: locale) }
        return state.git ? state.branchName : String(localized: "Not a Git repository", locale: locale)
    }

    var body: some View {
        Button {
            attempt += 1
        } label: {
            HStack(spacing: 8) {
                NewSessionIcon(imageName: "git-branch")
                Text(title).lineLimit(3)
                if isLoading { ProgressView() }
                else { Image(systemName: "arrow.clockwise").font(.caption) }
            }
            .font(.body)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(isDisabled || isLoading || !isCurrent || scenePhase != .active)
        .accessibilityLabel("Branch, \(title)")
        .accessibilityHint("Refresh the project's current branch")
        .accessibilityIdentifier("new-session-branch")
        .task(id: "\(projectID):\(templateSessionID):\(workspaceGeneration):\(attempt):\(scenePhase)") {
            guard scenePhase == .active, isCurrent else { return }
            await load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { loadID = UUID() }
        }
        .onDisappear { loadID = UUID() }
    }

    private func load() async {
        let id = UUID()
        loadID = id
        isLoading = true
        defer { if loadID == id { isLoading = false } }
        do {
            let loaded = try await model.projectGit(templateSessionID: templateSessionID, projectID: projectID)
            try Task.checkCancellation()
            guard isCurrent, loadID == id else { return }
            result = loaded
        } catch {
            guard !Task.isCancelled, isCurrent, loadID == id else { return }
            result = ProjectGitResult(failure: .unavailable)
        }
    }
}
