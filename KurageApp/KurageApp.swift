import SwiftUI

@main
struct KurageApp: App {
    @State private var model: AppModel

    init() {
        let client: any LodyClient = ProcessInfo.processInfo.arguments.contains("--fixture")
            ? FixtureLodyClient(records: ProcessInfo.processInfo.arguments.contains("--fixture-subtasks")
                ? SessionRecord.samplesWithSubtasks : SessionRecord.samples,
                failingConversationIDsOnce:
                ProcessInfo.processInfo.arguments.contains("--fixture-search-failure") ? ["session-long"] : [],
                failStartAndArchiveProjectOnce: ProcessInfo.processInfo.arguments.contains("--fixture-start-unconfirmed"),
                sendDelay: ProcessInfo.processInfo.arguments.contains("--fixture-slow-send") ? .seconds(3) : nil,
                failSendOnce: ProcessInfo.processInfo.arguments.contains("--fixture-send-unconfirmed"))
            : HTTPLodyClient()
        _model = State(initialValue: AppModel(client: client))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
