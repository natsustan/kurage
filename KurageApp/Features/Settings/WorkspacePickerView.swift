import SwiftUI

struct WorkspacePickerView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var refreshAttempt = 0
    @State private var selectingWorkspaceID: WorkspaceSummary.ID?
    @State private var isPullRefreshing = false

    var body: some View {
        List {
            ForEach(model.workspaces) { workspace in
                WorkspaceOptionRow(workspace: workspace, isSelected: workspace.id == model.selectedWorkspaceID) {
                    select(workspace.id)
                }
                .disabled(selectingWorkspaceID != nil)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(SettingsPalette.background)
            }

            if model.workspaceLoadStatusNote != nil || model.workspaces.isEmpty && !model.isRefreshingWorkspaces {
                WorkspaceLoadStatus(isEmpty: model.workspaces.isEmpty,
                                    error: model.workspaceLoadStatusNote?.text,
                                    onRetry: { refreshAttempt += 1 })
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(SettingsPalette.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.vertical, 18, for: .scrollContent)
        .scrollBounceBehavior(.always, axes: .vertical)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(SettingsPalette.background)
        .overlay {
            if model.workspaces.isEmpty && model.isRefreshingWorkspaces && !isPullRefreshing {
                ProgressView()
                    .accessibilityLabel("Loading workspaces")
                    .accessibilityIdentifier("workspace-loading")
            }
        }
        .navigationTitle("Workspace")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("workspace-picker")
        .task(id: refreshAttempt) { await model.refreshWorkspaces() }
        .refreshable { await refreshFromGesture() }
        .onChange(of: model.selectedWorkspaceID) { _, selected in
            if let selectingWorkspaceID, selected == selectingWorkspaceID { dismiss() }
        }
    }

    private func refreshFromGesture() async {
        isPullRefreshing = true
        defer { isPullRefreshing = false }
        await model.refreshWorkspaces()
    }

    private func select(_ id: WorkspaceSummary.ID) {
        guard selectingWorkspaceID == nil else { return }
        guard id != model.selectedWorkspaceID else {
            dismiss()
            return
        }
        selectingWorkspaceID = id
        // The model owns its session refresh. Dismissing this picker must not cancel the committed selection.
        Task {
            await model.selectWorkspace(id)
            selectingWorkspaceID = nil
        }
    }
}

private struct WorkspaceOptionRow: View {
    let workspace: WorkspaceSummary
    let isSelected: Bool
    let onSelect: () -> Void
    @ScaledMetric(relativeTo: .body) private var avatarSize = 40.0

    private var address: String? {
        guard !workspace.slug.isEmpty, let host = URL(string: LodyEndpoints.webOrigin)?.host else { return nil }
        return "\(host)/\(workspace.slug)"
    }

    private var avatarColor: Color {
        let hash = workspace.id.utf8.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1) }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.45, brightness: 0.5)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Text(String(workspace.name.prefix(1)).uppercased())
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: min(avatarSize, 64), height: min(avatarSize, 64))
                    .background(avatarColor, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workspace.name).font(.body.weight(.medium))
                    if let address {
                        Text(address).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(workspace.name)
        .accessibilityValue(address ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("workspace-option-\(workspace.id)")
    }
}

private struct WorkspaceLoadStatus: View {
    let isEmpty: Bool
    let error: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("workspace-error")
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("workspace-retry")
            } else if isEmpty {
                Text("No workspaces").font(.body.weight(.medium))
                Text("There are no workspaces available for this account.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Refresh", action: onRetry).buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }
}
