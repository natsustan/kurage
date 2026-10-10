import SwiftUI
import KurageCore

private enum MacSettingsSection: String, Hashable, CaseIterable {
    case general
    case account

    var title: String {
        switch self {
        case .general: "General"
        case .account: "Account"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .account: "person.crop.circle"
        }
    }

    var identifier: String {
        "settings-nav-\(rawValue)"
    }
}

struct MacSettingsView: View {
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var section: MacSettingsSection? = .general

    var body: some View {
        // A real split column, like Prism: the sidebar runs under the traffic
        // lights, and the pane title sits in the detail side of the toolbar.
        NavigationSplitView {
            List(selection: $section) {
                ForEach(MacSettingsSection.allCases, id: \.self) { item in
                    Label(item.title, systemImage: item.symbolName)
                        .tag(item)
                        .accessibilityIdentifier(item.identifier)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch section ?? .general {
                case .general:
                    MacGeneralSettings()
                case .account:
                    MacAccountSettings(model: model)
                }
            }
            .navigationTitle((section ?? .general).title)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 480)
        .onChange(of: model.account) { _, account in
            if account == nil { closeSettingsWindow(dismissWindow) }
        }
    }
}

/// Closing during the sign-out update is ignored, so dismiss on the next turn.
private func closeSettingsWindow(_ dismiss: DismissWindowAction) {
    Task { @MainActor in
        dismiss(id: MacSettingsWindow.id)
    }
}

private struct MacGeneralSettings: View {
    @AppStorage(MacTheme.storageKey) private var theme: MacTheme = .system
    @AppStorage(MacTabLayout.storageKey) private var tabLayout: MacTabLayout = .separate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Appearance")
                .font(.title3.weight(.semibold))
            MacSettingsCard {
                MacSettingsRow(symbolName: "circle.lefthalf.filled", title: "Theme",
                               detail: "Use light, dark, or match your system") {
                    MacSegmentedPicker(selection: $theme, title: \.title, symbolName: \.symbolName,
                                       identifier: { "appearance-theme-\($0.rawValue)" })
                }
            }
            .padding(.top, 12)
            Text("Tabs")
                .font(.title3.weight(.semibold))
                .padding(.top, 28)
            MacSettingsCard {
                MacSettingsRow(symbolName: "menubar.rectangle", title: "Tab layout",
                               detail: "Show tabs on their own row, or in the toolbar beside the title") {
                    MacSegmentedPicker(selection: $tabLayout, title: \.title, symbolName: \.symbolName,
                                       identifier: { "tab-layout-\($0.rawValue)" })
                }
            }
            .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MacSettingsRow<Control: View>: View {
    let symbolName: String
    let title: String
    let detail: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 160, alignment: .leading)
            Spacer(minLength: 12)
            control
                .fixedSize()
        }
    }
}

private struct MacSegmentedPicker<Option: CaseIterable & Hashable>: View where Option.AllCases: RandomAccessCollection {
    @Binding var selection: Option
    let title: (Option) -> String
    let symbolName: (Option) -> String
    let identifier: (Option) -> String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Option.allCases), id: \.self) { option in
                let selected = selection == option
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: symbolName(option))
                            .accessibilityHidden(true)
                        Text(title(option))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(MacSettingsPlainButtonStyle())
                .background {
                    if selected {
                        Capsule()
                            .fill(selectedFill)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 1, y: 0.5)
                            .overlay {
                                Capsule().strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
                            }
                    }
                }
                .contentShape(Capsule())
                .focusEffectDisabled()
                .accessibilityLabel(title(option))
                .accessibilityIdentifier(identifier(option))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(track, in: Capsule())
        .animation(.easeInOut(duration: 0.15), value: selection)
    }

    private var selectedFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white
    }

    private var track: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
}

private struct MacSettingsPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

private struct MacAccountSettings: View {
    let model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var confirmsSignOut = false

    private var settingsCardFill: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let account = model.account {
                MacSettingsCard {
                    MacAccountSummary(account: account)
                }
                Button {
                    confirmsSignOut = true
                } label: {
                    Text("Sign out")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .background(settingsCardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("sign-out-button")
            } else {
                Text("Not signed in")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("Sign out of Lody?", isPresented: $confirmsSignOut) {
            Button("Sign out", role: .destructive) {
                model.signOut()
                closeSettingsWindow(dismissWindow)
            }
        } message: {
            Text("Local drafts and cached conversations will be cleared.")
        }
    }
}

private struct MacAccountSummary: View {
    let account: Account

    private var displayName: String {
        let name = account.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return String(account.email.split(separator: "@", maxSplits: 1).first ?? "")
    }

    var body: some View {
        HStack(spacing: 12) {
            MacAccountAvatar(account: account)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body.weight(.medium))
                Text(account.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("settings-account-summary")
    }
}

private struct MacAccountAvatar: View {
    let account: Account

    private var initial: String {
        let name = account.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = account.email.split(separator: "@", maxSplits: 1).first.map(String.init)
        return String((name?.isEmpty == false ? name : fallback)?.prefix(1) ?? "?").uppercased()
    }

    var body: some View {
        Text(initial)
            .font(.subheadline.weight(.semibold))
            .frame(width: 36, height: 36)
            .background(.quaternary, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct MacSettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

#Preview {
    MacStoredScene(preferences: .standard, fixtureOverride: nil) {
        MacSettingsView(model: AppModel(client: FixtureLodyClient(startsSignedIn: true)))
    }
    .frame(width: 720, height: 480)
}
