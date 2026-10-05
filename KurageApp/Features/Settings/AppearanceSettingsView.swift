import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @AppStorage(AppAccent.storageKey) private var accent: AppAccent = .black

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                AppearanceThemeOptions(theme: $theme)
                AppearanceAccentOptions(accent: $accent)
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
        }
        .background(SettingsPalette.background)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("appearance-settings")
    }
}

private struct AppearanceThemeOptions: View {
    @Binding var theme: AppTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 20))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))

        layout {
            ForEach(AppTheme.allCases, id: \.self) { option in
                AppearanceOption(title: option.title, isSelected: theme == option,
                                 identifier: "appearance-theme-\(option.rawValue)",
                                 onSelect: { theme = option }) {
                    Image(systemName: option.symbolName)
                        .font(.system(size: 26))
                        .foregroundStyle(theme == option ? Color.primary : Color.secondary)
                }
            }
        }
    }
}

private struct AppearanceAccentOptions: View {
    @Binding var accent: AppAccent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 20))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))

        layout {
            ForEach(AppAccent.allCases, id: \.self) { option in
                AppearanceOption(title: option.title, isSelected: accent == option,
                                 identifier: "appearance-accent-\(option.rawValue)",
                                 onSelect: { accent = option }) {
                    Circle()
                        .fill(option.color)
                        .frame(width: 26, height: 26)
                }
            }
        }
    }
}

private struct AppearanceOption<Symbol: View>: View {
    let title: LocalizedStringResource
    let isSelected: Bool
    let identifier: String
    let onSelect: () -> Void
    @ViewBuilder let symbol: Symbol

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                symbol
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(isSelected ? SettingsPalette.selectionBackground : SettingsPalette.background,
                                in: .rect(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isSelected ? .clear : SettingsPalette.separator.opacity(0.6), lineWidth: 1)
                    }
                Text(title)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
