import SwiftUI

struct WorkspacePickerView: View {
    let model: AppModel
    let maximumInitialHeight: CGFloat
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 220
    @State private var refreshAttempt = 0
    @State private var selectingWorkspaceID: WorkspaceSummary.ID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Workspaces").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .frame(width: 44, height: 44)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("workspace-picker-close")
                }
                .padding(.horizontal, 18)

                ForEach(model.workspaces) { workspace in
                    WorkspaceOptionRow(workspace: workspace, isSelected: workspace.id == model.selectedWorkspaceID) {
                        select(workspace.id)
                    }
                    .disabled(selectingWorkspaceID != nil)
                }

                WorkspaceLoadStatus(isLoading: model.isRefreshingWorkspaces,
                                    isEmpty: model.workspaces.isEmpty,
                                    error: model.workspaceLoadStatusNote?.text,
                                    onRetry: { refreshAttempt += 1 })
            }
            .padding(.top, 18)
            .padding(.bottom, 20)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SettingsPalette.background)
        .presentationBackground(SettingsPalette.background)
        .presentationDetents([.height(min(max(180, contentHeight), maximumInitialHeight)), .large])
        .accessibilityIdentifier("workspace-picker")
        .task(id: refreshAttempt) { await model.refreshWorkspaces() }
        .onChange(of: model.selectedWorkspaceID) { _, selected in
            if let selectingWorkspaceID, selected == selectingWorkspaceID { dismiss() }
        }
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
    let isLoading: Bool
    let isEmpty: Bool
    let error: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                ProgressView("Refreshing workspaces…")
                    .accessibilityIdentifier("workspace-loading")
            } else if let error {
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
