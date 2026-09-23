import SwiftUI

@main
struct KurageApp: App {
    @State private var model: AppModel

    init() {
        let client: any LodyClient = ProcessInfo.processInfo.arguments.contains("--fixture")
            ? FixtureLodyClient()
            : HTTPLodyClient()
        _model = State(initialValue: AppModel(client: client))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
