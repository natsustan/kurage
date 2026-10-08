import SafariServices
import SwiftUI
import KurageCore

/// Lody owns the web sign-in UI; the native device flow confirms authorization.
struct AuthorizationBrowser: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.delegate = context.coordinator
        controller.view.accessibilityIdentifier = "authorization-browser"
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: { dismiss() })
    }

    @MainActor
    final class Coordinator: NSObject, @MainActor SFSafariViewControllerDelegate {
        private let onClose: () -> Void

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onClose()
        }
    }
}
