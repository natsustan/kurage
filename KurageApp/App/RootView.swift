import SwiftUI

struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.isSignedIn {
                SessionListView(model: model)
            } else {
                SignInView(model: model)
            }
        }
        .task {
            await model.adoptExistingAccount()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.setApplicationActive(phase == .active)
        }
    }
}

#Preview("Signed out") {
    RootView(model: AppModel(client: FixtureLodyClient()))
}

#Preview("Sessions") {
    RootView(model: AppModel(client: FixtureLodyClient(startsSignedIn: true)))
}
