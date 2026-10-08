import SwiftUI
import KurageCore

@main
struct KurageMacApp: App {
    @State private var model: AppModel
    private let fixtureAppearance: ColorScheme?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let fixture = arguments.contains("--fixture")
        fixtureAppearance = fixture && arguments.contains("--fixture-dark") ? .dark : nil
        let defaults = fixture ? UserDefaults(suiteName: "com.spike.kurage.macos.fixture")! : .standard
        _model = State(initialValue: AppModel(
            client: fixture ? FixtureLodyClient(startsSignedIn: true, streamsConversationUpdates: true) : HTTPLodyClient(),
            quickActionDefaults: defaults
        ))
    }

    var body: some Scene {
        Window("Kurage", id: "main") {
            MacRootView(model: model)
                .frame(minWidth: 820, minHeight: 560)
                .preferredColorScheme(fixtureAppearance)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
