import SwiftUI

enum AppTheme: String {
    case system
    case light
    case dark

    static let storageKey = "appTheme"

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

struct WindowThemeView: UIViewRepresentable {
    let theme: AppTheme

    func makeUIView(context: Context) -> ThemeView {
        let view = ThemeView()
        view.isUserInteractionEnabled = false
        view.style = theme.userInterfaceStyle
        return view
    }

    func updateUIView(_ uiView: ThemeView, context: Context) {
        uiView.style = theme.userInterfaceStyle
    }

    final class ThemeView: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { window?.overrideUserInterfaceStyle = style }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Reset the window to the system style explicitly; a nil SwiftUI presentation preference can retain its last override.
            window?.overrideUserInterfaceStyle = style
        }
    }
}
