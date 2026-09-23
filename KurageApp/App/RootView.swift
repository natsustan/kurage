import SwiftUI

struct RootView: View {
    let model: AppModel

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
    }
}

#Preview("Signed out") {
    RootView(model: AppModel(client: FixtureLodyClient()))
}

#Preview("Sessions") {
    RootView(model: AppModel(client: FixtureLodyClient(startsSignedIn: true)))
}
