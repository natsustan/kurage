import SwiftUI

struct RootView: View {
    let model: AppModel
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasFinishedAccountRestoration = false
    @State private var hasFinishedMinimumLaunchDuration = false
    @State private var showsSettings = false

    var body: some View {
        @Bindable var notifications = model.notifications
        let showsLaunchCover = !hasFinishedMinimumLaunchDuration
            || (!model.isSignedIn && !hasFinishedAccountRestoration)

        Group {
            if model.isSignedIn {
                SessionListView(model: model, isReading: !showsSettings,
                                onOpenSettings: { showsSettings = true })
                    .id(model.workspaceGeneration)
            } else if hasFinishedAccountRestoration {
                SignInView(model: model)
            } else {
                Color("LaunchBackground").ignoresSafeArea()
            }
        }
        .allowsHitTesting(!showsLaunchCover)
        .accessibilityHidden(showsLaunchCover)
        .sheet(isPresented: $showsSettings) {
            SettingsView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(36)
        }
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
        .onChange(of: model.isSignedIn) { _, signedIn in
            if !signedIn { showsSettings = false }
        }
        .task(id: NotificationRoutingTask(clickID: notifications.pendingClick?.id,
                                         userID: notifications.userID, isActive: scenePhase == .active)) {
            if notifications.pendingClick != nil, notifications.userID == model.account?.id { showsSettings = false }
            await model.openPendingNotification()
        }
        .onChange(of: model.notificationNavigation) { _, navigation in
            if navigation != nil { showsSettings = false }
        }
        .alert("Could not open conversation", isPresented: $notifications.routingErrorPresented) {
            if notifications.pendingClick != nil {
                Button("Retry") { Task { await model.openPendingNotification() } }
            }
            Button("OK", role: .cancel) {}
        } message: { Text(notifications.routingError ?? "") }
        .background {
            WindowThemeView(theme: theme)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

private struct NotificationRoutingTask: Equatable {
    let clickID: String?
    let userID: String?
    let isActive: Bool
}

#Preview("Signed out") {
    RootView(model: AppModel(client: FixtureLodyClient()))
}

#Preview("Sessions") {
    RootView(model: AppModel(client: FixtureLodyClient(startsSignedIn: true)))
}
