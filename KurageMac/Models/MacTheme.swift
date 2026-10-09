import SwiftUI

/// Mac appearance preference. The raw values match the iOS theme, and each app keeps its own defaults.
enum MacTheme: String, CaseIterable {
    case light
    case dark
    case system

    static let storageKey = "appTheme"

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }

    var symbolName: String {
        switch self {
        case .light: "sun.max"
        case .dark: "moon"
        case .system: "circle.lefthalf.filled"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

/// Where session tabs sit. Compact moves them into the toolbar beside the title,
/// like Safari's compact tabs; Separate keeps them on their own row.
enum MacTabLayout: String, CaseIterable {
    case separate
    case compact

    static let storageKey = "tabLayout"

    var title: String {
        switch self {
        case .separate: "Separate"
        case .compact: "Compact"
        }
    }

    var symbolName: String {
        switch self {
        case .separate: "rectangle.split.1x2"
        case .compact: "menubar.rectangle"
        }
    }
}

enum MacSettingsWindow {
    static let id = "settings"
}

/// Applies the saved theme. A fixture override wins so `--fixture-dark` stays dark during screenshot tests.
struct MacStoredScene<Content: View>: View {
    var preferences: UserDefaults
    var fixtureOverride: ColorScheme?
    @ViewBuilder var content: () -> Content

    var body: some View {
        MacThemedContent(fixtureOverride: fixtureOverride, content: content)
            .defaultAppStorage(preferences)
    }
}

private struct MacThemedContent<Content: View>: View {
    @AppStorage(MacTheme.storageKey) private var theme: MacTheme = .system
    var fixtureOverride: ColorScheme?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .preferredColorScheme(fixtureOverride ?? theme.colorScheme)
    }
}
