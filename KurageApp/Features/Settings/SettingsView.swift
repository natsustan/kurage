import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if let account = model.account {
                        SettingsAccountSection(model: model, account: account)
                    }
                    SettingsPreferencesSection()
                    if model.notifications.isConfigured {
                        NavigationLink {
                            NotificationSettingsView(model: model.notifications)
                        } label: {
                            SettingsNavigationRow(title: "Notifications")
                                .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings-notifications")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsNavigationRow(title: "About Kurage")
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
            .accessibilityIdentifier("settings-content")
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

private struct SettingsPreferencesSection: View {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @AppStorage(AppHaptics.storageKey) private var hapticsEnabled = true

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                SettingsNavigationRow(title: "Appearance", value: Text(theme.title))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Appearance")
            .accessibilityValue(Text(theme.title))
            .accessibilityIdentifier("settings-theme")

            Divider().overlay(SettingsPalette.separator).padding(.leading, 18)

            NavigationLink {
                HapticsSettingsView()
            } label: {
                SettingsNavigationRow(title: "Haptics", value: Text(hapticsEnabled ? "On" : "Off"))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Haptics")
            .accessibilityValue(hapticsEnabled ? "On" : "Off")
            .accessibilityIdentifier("settings-haptics")
        }
        .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
    }
}

private struct SettingsAccountSection: View {
    let model: AppModel
    let account: Account

    var body: some View {
        VStack(spacing: 0) {
            SettingsAccountSummary(account: account)
            Divider().overlay(SettingsPalette.separator).padding(.leading, 18)
            NavigationLink {
                WorkspacePickerView(model: model)
            } label: {
                SettingsNavigationRow(title: "Workspace", value: Text(model.selectedWorkspace?.name ?? "None selected"))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Workspace")
            .accessibilityValue(model.selectedWorkspace?.name ?? "None selected")
            .accessibilityIdentifier("settings-workspace")
        }
        .background(SettingsPalette.groupBackground, in: .rect(cornerRadius: 20))
    }
}

private struct SettingsNavigationRow: View {
    let title: LocalizedStringResource
    var value: Text? = nil

    var body: some View {
        HStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(title)
                    Spacer(minLength: 12)
                    value.foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                    value.foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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

    static let selectionBackground = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.tertiarySystemBackground.resolvedColor(with: traits)
        }
        return UIColor(white: 236.0 / 255, alpha: 1)
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
