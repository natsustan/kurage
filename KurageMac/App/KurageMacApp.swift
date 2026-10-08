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
        let records = arguments.contains("--fixture-questions")
            ? [SessionRecord.questionSample] + SessionRecord.samples
            : arguments.contains("--fixture-slow-images") ? SessionRecord.samplesWithTrailingImage : SessionRecord.samples
        _model = State(initialValue: AppModel(
            client: fixture ? FixtureLodyClient(startsSignedIn: true,
                supportsSessionCreation: !arguments.contains("--fixture-no-session-creation"),
                readReceiptFailures: arguments.contains("--fixture-read-retry") ? 2 : 0,
                records: records,
                failStartAndArchiveProjectOnce: arguments.contains("--fixture-start-unconfirmed"),
                rejectStartOnce: arguments.contains("--fixture-start-rejected"),
                removeSelectedAgentOnStartOnce: arguments.contains("--fixture-agent-removed"),
                rejectMissingHistoryOnce: arguments.contains("--fixture-send-not-delivered"),
                streamsConversationUpdates: true,
                failOriginalImageOnce: arguments.contains("--fixture-image-failure"),
                imageLoadDelay: arguments.contains("--fixture-slow-images") ? .seconds(8) : nil) : HTTPLodyClient(),
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
