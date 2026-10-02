import SwiftUI

struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasFinishedAccountRestoration = false
    @State private var hasFinishedMinimumLaunchDuration = false

    var body: some View {
        let showsLaunchCover = !hasFinishedMinimumLaunchDuration
            || (!model.isSignedIn && !hasFinishedAccountRestoration)

        Group {
            if model.isSignedIn {
                SessionListView(model: model)
                    .id(model.workspaceGeneration)
            } else if hasFinishedAccountRestoration {
                SignInView(model: model)
            } else {
                Color("LaunchBackground").ignoresSafeArea()
            }
        }
        .allowsHitTesting(!showsLaunchCover)
        .accessibilityHidden(showsLaunchCover)
        .overlay {
            if showsLaunchCover {
                LaunchCoverView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showsLaunchCover)
        .task {
            await model.adoptExistingAccount()
            guard !Task.isCancelled else { return }
            hasFinishedAccountRestoration = true
        }
        .task {
            guard !hasFinishedMinimumLaunchDuration else { return }
            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch is CancellationError {
                return
            } catch {
                return
            }
            hasFinishedMinimumLaunchDuration = true
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
