import SwiftUI
import KurageCore

struct MacRootView: View {
    let model: AppModel
    @State private var restored = false
    @State private var awake = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.isSignedIn {
                MacWorkspaceView(model: model, isAwake: awake && scenePhase != .background)
                    .id(model.workspaceGeneration)
            } else if restored {
                MacSignInView(model: model)
            } else {
                ProgressView("Restoring account…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await model.adoptExistingAccount()
            restored = true
        }
        // Losing keyboard focus is not a mobile background transition.
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.setApplicationActive(awake && phase != .background)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            awake = false
            model.setApplicationActive(false)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            awake = true
            model.setApplicationActive(scenePhase != .background)
        }
    }
}

private struct MacSignInView: View {
    let model: AppModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Kurage").font(.largeTitle.bold())
            Text("Your Lody conversations, on Mac.").foregroundStyle(.secondary)
            Button(model.isSigningIn ? "Waiting for authorization…" : "Sign in with Lody") {
                model.connect { openURL($0) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isSigningIn)
            if let authorization = model.deviceAuthorization {
                Text(authorization.userCode).font(.title.monospaced()).textSelection(.enabled)
                Link("Open authorization page", destination: authorization.verificationURL)
            }
            if let note = model.statusNote { Text(note.text).foregroundStyle(.secondary) }
            if model.isSigningIn { Button("Cancel") { model.signOut() } }
            Text("Independent third-party Lody client").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MacWorkspaceView: View {
    let model: AppModel
    let isAwake: Bool
    @State private var window = MacWindowState()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var window = window
        NavigationSplitView {
            MacSidebar(model: model, window: window)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Menu {
                            ForEach(model.workspaces) { workspace in
                                Button(workspace.name) { Task { await model.selectWorkspace(workspace.id) } }
                            }
                        } label: {
                            Label(model.workspaceLabel, systemImage: "square.grid.2x2")
                                .lineLimit(1)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("workspace-menu")
                        Button("Settings", systemImage: "gearshape") { openWindow(id: MacSettingsWindow.id) }
                            .labelStyle(.iconOnly)
                            .help("Settings")
                            .accessibilityIdentifier("open-settings")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
        } detail: {
            if let rootID = window.selectedRootID, let root = model.sessionSummary(rootID) {
                MacSessionView(model: model, window: window, root: root, isAwake: isAwake)
                    .id(root.id)
            } else {
                ContentUnavailableView("Select a conversation", systemImage: "bubble.left.and.bubble.right",
                    description: Text("Choose a session from the sidebar, or start one in a project."))
            }
        }
        .overlay {
            if window.showsSessionSearch {
                MacSessionSearchOverlay(model: model, window: window)
            }
        }
        .sheet(item: $window.newSession) { destination in
            MacNewSessionView(model: model, destination: destination, isAwake: isAwake) { id in
                window.open(id, rootID: destination.isTab ? destination.template.id : nil)
            }
        }
        .task(id: isAwake) {
            guard isAwake else { return }
            while !Task.isCancelled {
                await model.refreshSessions()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
}
