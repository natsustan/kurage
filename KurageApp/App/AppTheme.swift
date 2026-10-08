import SwiftUI
import KurageCore

enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark

    static let storageKey = "appTheme"

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Day"
        case .dark: "Night"
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    var symbolName: String {
        switch self {
        case .system: "circle.righthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

enum AppAccent: String, CaseIterable {
    case black
    case blue

    static let storageKey = "appAccent"

    var title: LocalizedStringResource {
        switch self {
        case .black: "Black"
        case .blue: "Blue"
        }
    }

    var color: Color {
        switch self {
        case .black: Color(uiColor: .label)
        case .blue: .blue
        }
    }

    var foregroundColor: Color {
        switch self {
        case .black: Color(uiColor: .systemBackground)
        case .blue: .white
        }
    }

    var userMessageBackgroundColor: UIColor {
        UIColor { traits in
            switch self {
            case .black:
                if traits.userInterfaceStyle == .dark {
                    return UIColor.systemGray5.resolvedColor(with: traits)
                }
                return UIColor.label.resolvedColor(with: traits).withAlphaComponent(0.06)
            case .blue:
                return UIColor(red: 0, green: 108.0 / 255, blue: 235.0 / 255, alpha: 1)
            }
        }
    }

    var userMessageForegroundColor: UIColor {
        switch self {
        case .black: .label
        case .blue: .white
        }
    }
}

enum AppHaptics {
    static let storageKey = "hapticsEnabled"
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
