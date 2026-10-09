import AppKit
import SwiftUI
import KurageCore

enum MacSessionAction {
    case pin, rename, copyURL, archive
}

struct MacSessionActionRequest: Identifiable {
    let id = UUID()
    let session: SessionSummary
    let action: MacSessionAction
}

/// Sidebar session actions. Alerts and the pasteboard stay on the Mac side;
/// the writes go through the same `AppModel` entry points as iOS.
struct MacSessionActionPresenter: ViewModifier {
    let model: AppModel
    @Binding var request: MacSessionActionRequest?
    var onArchived: (String) -> Void = { _ in }
    @State private var title = ""
    @State private var showsPrompt = false
    @State private var failed = false
    @State private var task: Task<Void, Never>?
    @State private var generation = 0

    private var canSaveTitle: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.utf16.count <= 200
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: request?.id) { _, _ in
                guard let request else { return }
                generation = model.workspaceGeneration
                switch request.action {
                case .copyURL:
                    if let url = model.sessionURL(sessionID: request.session.id) {
                        copy(url)
                    }
                case .pin:
                    execute(request)
                case .rename:
                    title = request.session.title
                    showsPrompt = true
                case .archive:
                    showsPrompt = true
                }
            }
            .alert(request?.action == .rename ? "Rename session" : "Archive session?", isPresented: $showsPrompt) {
                if request?.action == .rename {
                    TextField("Session title", text: $title)
                        .accessibilityIdentifier("session-title-field")
                    Button("Save") {
                        guard canSaveTitle, let request else { return }
                        execute(request)
                    }
                    .disabled(!canSaveTitle)
                } else {
                    Button("Archive", role: .destructive) {
                        if let request { execute(request) }
                    }
                    .accessibilityIdentifier("archive-confirm")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(request?.action == .rename
                    ? "Enter a title (up to 200 characters)."
                    : "This archives the session and its child sessions.")
            }
            .alert("Could not update this session. Please try again.", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
            .onChange(of: model.workspaceGeneration) { _, _ in
                task?.cancel()
                showsPrompt = false
                failed = false
                request = nil
            }
            .onDisappear { task?.cancel() }
    }

    private func copy(_ url: URL) {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .string)
        item.setString(url.absoluteString, forType: .URL)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private func execute(_ request: MacSessionActionRequest) {
        guard generation == model.workspaceGeneration else { return }
        task?.cancel()
        let generation = generation
        let title = title
        task = Task { @MainActor in
            do {
                switch request.action {
                case .pin:
                    try await model.updateSessionMetadata(.pin(request.session.isPinned != true), sessionID: request.session.id)
                case .rename:
                    try await model.updateSessionMetadata(.rename(title), sessionID: request.session.id)
                case .archive:
                    try await model.archiveSession(sessionID: request.session.id)
                    if !Task.isCancelled, generation == model.workspaceGeneration {
                        onArchived(request.session.id)
                    }
                case .copyURL:
                    break
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled, generation == model.workspaceGeneration { failed = true }
            }
        }
    }
}
