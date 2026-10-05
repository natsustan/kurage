import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @Environment(\.dismiss) private var dismiss
    @State private var showsWorkspaces = false
    @State private var confirmsSignOut = false
    @State private var availableHeight: CGFloat = 700

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if let account = model.account {
                        SettingsAccountSection(account: account, workspaceName: model.selectedWorkspace?.name,
                                               onWorkspace: { showsWorkspaces = true })
                    }
                    SettingsThemeRow(theme: $theme)
                    if model.notifications.isConfigured {
                        NavigationLink {
                            NotificationSettingsView(model: model.notifications)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bell")
                                    .frame(width: 28, height: 28)
                                Text("Notifications")
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings-notifications")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack(spacing: 12) {
                            SettingsRowIcon(name: "settings-about-icon")
                            Text("About Kurage")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-about")

                    Button("Sign out", role: .destructive) { confirmsSignOut = true }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
                        .accessibilityIdentifier("sign-out-button")
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .background(SettingsPalette.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("settings-close")
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { availableHeight = $0 }
            .sheet(isPresented: $showsWorkspaces) {
                WorkspacePickerView(model: model, maximumInitialHeight: max(180, availableHeight * 0.65))
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(36)
            }
            .confirmationDialog("Sign out of Kurage?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { model.signOut() }
                    .accessibilityIdentifier("sign-out-confirm")
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationBackground(SettingsPalette.background)
        .accessibilityIdentifier("settings-screen")
    }
}

private struct SettingsAccountSection: View {
    let account: Account
    let workspaceName: String?
    let onWorkspace: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsAccountSummary(account: account)
            Divider().overlay(SettingsPalette.separator).padding(.leading, 18)
            Button(action: onWorkspace) {
                HStack(spacing: 12) {
                    SettingsRowIcon(name: "settings-workspace-icon")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            Text("Workspace")
                            Spacer(minLength: 12)
                            Text(workspaceName ?? "None selected").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Workspace")
                            HStack {
                                Text(workspaceName ?? "None selected").foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Workspace")
            .accessibilityValue(workspaceName ?? "None selected")
            .accessibilityIdentifier("settings-workspace")
        }
        .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
    }
}

private struct SettingsThemeRow: View {
    @Binding var theme: AppTheme

    var body: some View {
        Menu {
            Picker("Theme", selection: $theme) {
                Text("System").tag(AppTheme.system)
                Text("Light").tag(AppTheme.light)
                Text("Dark").tag(AppTheme.dark)
            }
        } label: {
            HStack(spacing: 12) {
                SettingsRowIcon(name: "settings-theme-icon")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text("Theme")
                        Spacer(minLength: 12)
                        Text(theme.title).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Theme")
                        Text(theme.title).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Theme")
        .accessibilityValue(Text(theme.title))
        .accessibilityIdentifier("settings-theme")
    }
}

private struct SettingsRowIcon: View {
    let name: String
    @ScaledMetric(relativeTo: .body) private var size = 24.0

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: min(size, 40), height: min(size, 40))
            .accessibilityHidden(true)
    }
}

private struct SettingsAccountSummary: View {
    let account: Account
    @ScaledMetric(relativeTo: .body) private var avatarSize = 44.0

    private var displayName: String {
        let name = account.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return String(account.email.split(separator: "@", maxSplits: 1).first ?? "")
    }

    var body: some View {
        HStack(spacing: 14) {
            AccountAvatar(account: account, size: min(avatarSize, 64))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName).font(.body.weight(.medium))
                Text(account.email).font(.subheadline).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings-account")
    }
}

enum SettingsPalette {
    static let background = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.systemBackground.resolvedColor(with: traits)
        }
        return UIColor(white: 252.0 / 255, alpha: 1)
    })

    static let groupBackground = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.secondarySystemBackground.resolvedColor(with: traits)
        }
        return UIColor(white: 242.0 / 255, alpha: 1)
    })

    static let separator = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.separator.resolvedColor(with: traits)
        }
        return UIColor(white: 224.0 / 255, alpha: 1)
    })
}

#Preview {
    SettingsView(model: AppModel(client: FixtureLodyClient(startsSignedIn: true)))
}
