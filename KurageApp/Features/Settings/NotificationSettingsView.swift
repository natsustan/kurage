import SwiftUI

struct NotificationSettingsView: View {
    let model: NotificationModel
    @AppStorage(AppAccent.storageKey) private var accent: AppAccent = .black
    @Environment(\.openURL) private var openURL
    @State private var isEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Push notifications", isOn: $isEnabled)
                    .tint(accent.color)
                    .disabled(!model.isConfigured || model.userID == nil || model.isUpdating)
                    .accessibilityIdentifier("notifications-toggle")
                if model.isUpdating {
                    ProgressView("Updating…")
                }
            } footer: {
                Text("Receive notifications when an agent finishes or needs your response.")
            }
            if !model.isConfigured {
                Section { Text("Notifications are not available in this build.") }
            } else if model.userID == nil {
                Section { Text("Sign in to enable notifications.") }
            } else if model.status.authorization == .denied {
                Section {
                    Text("Notifications are turned off in iOS Settings.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .accessibilityIdentifier("notifications-open-settings")
                }
            } else if isEnabled && (!model.status.isRegistered || !model.status.isSubscribed) {
                Section { Text("Registering this device…") }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.refresh()
            isEnabled = model.isEnabled
        }
        .onChange(of: isEnabled) { _, enabled in
            guard enabled != model.isEnabled, !model.isUpdating else { return }
            Task {
                await model.setEnabled(enabled)
                isEnabled = model.isEnabled
            }
        }
        .onChange(of: model.isEnabled) { _, enabled in isEnabled = enabled }
        .accessibilityIdentifier("notification-settings")
    }
}
