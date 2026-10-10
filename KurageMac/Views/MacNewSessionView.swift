import AppKit
import SwiftUI
import KurageCore

struct MacNewSessionView: View {
    let model: AppModel
    let destination: NewSessionDestination
    let isAwake: Bool
    let onStarted: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MacWindowState.Draft()
    @State private var options: NewSessionOptions?
    @State private var providerID: String?
    @State private var loading = true
    @State private var error: String?
    @State private var refresh = 0
    @State private var selectedTemplate: SessionSummary?
    @State private var projects: [SessionSummary] = []
    @State private var importing = false
    @State private var restoredConfiguration = false
    @State private var measuredHeight: CGFloat = 64

    private var canStart: Bool {
        pendingStart == nil && !loading && !draft.isLoadingAttachments && options != nil &&
            (!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.attachments.isEmpty)
    }

    init(model: AppModel, destination: NewSessionDestination, isAwake: Bool, onStarted: @escaping (String) -> Void) {
        self.model = model
        self.destination = destination
        self.isAwake = isAwake
        self.onStarted = onStarted
        var draft = MacWindowState.Draft()
        draft.text = destination.restoredMessage?.composerText ?? ""
        draft.attachments = destination.restoredMessage?.attachments ?? []
        _draft = State(initialValue: draft)
        _providerID = State(initialValue: destination.restoredStart?.request.agentConfigID)
    }

    private var pendingStart: PendingSessionStart? {
        guard !destination.isTab else { return nil }
        return model.pendingSessionStarts.first { $0.projectID == template.projectID }
    }

    private var template: SessionSummary { selectedTemplate ?? destination.template }

    private struct LoadKey: Equatable {
        let templateID: String
        let providerID: String?
        let refresh: Int
        let awake: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                if destination.isTab {
                    Label(template.projectName ?? "Project", systemImage: "folder")
                    Text("New tab").foregroundStyle(.secondary)
                } else {
                    Menu {
                        ForEach(projects) { project in
                            Button {
                                guard project.projectID != template.projectID else { return }
                                selectedTemplate = project
                                providerID = nil
                                options = nil
                                loading = true
                            } label: {
                                if project.projectID == template.projectID {
                                    Label(project.projectName ?? "Project", systemImage: "checkmark")
                                } else {
                                    Text(project.projectName ?? "Project")
                                }
                            }
                        }
                    } label: {
                        Label(template.projectName ?? "Project", systemImage: "folder")
                    }
                    .fixedSize().accessibilityIdentifier("new-project")
                }
                Spacer()
                if let options, !options.providers.isEmpty {
                    Picker("Agent", selection: Binding(get: { providerID ?? options.agentConfigID }, set: {
                        guard $0 != (providerID ?? options.agentConfigID) else { return }
                        providerID = $0
                        self.options = nil
                        loading = true
                    })) {
                        ForEach(options.providers) { Text($0.label).tag($0.value) }
                    }
                    .labelsHidden().fixedSize().accessibilityIdentifier("new-agent")
                }
            }
            .padding(20)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if let pendingStart {
                    Button("Resume pending session") {
                        do {
                            let id = try model.restoreSessionStart(pendingStart, projectName: template.projectName ?? "Project")
                            onStarted(id)
                            dismiss()
                        } catch { self.error = "Could not reopen the pending session." }
                    }
                    .accessibilityIdentifier("resume-pending-session")
                }
                if let error {
                    HStack {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { refresh += 1 }
                        if options == nil, providerID != nil {
                            Button("Use default agent") {
                                providerID = nil
                                restoredConfiguration = true
                                loading = true
                                self.error = nil
                                refresh += 1
                            }
                            .accessibilityIdentifier("use-default-agent")
                        }
                    }
                }
                MacComposerCard {
                    VStack(alignment: .leading, spacing: 0) {
                        MacMessageEditor(text: $draft.text, accessibilityLabel: "First message",
                            accessibilityIdentifier: "new-message", initiallyFocused: true,
                            onContentHeight: { measuredHeight = $0 }) {
                            draft.pendingAttachments.append(contentsOf: $0)
                        }
                        .frame(height: min(200, max(64, measuredHeight)))
                        .overlay(alignment: .topLeading) {
                            if draft.text.isEmpty {
                                Text("What do you want to work on?")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 1)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        MacAttachmentPicker(attachments: $draft.attachments, pending: $draft.pendingAttachments,
                            importing: $importing, showsButton: false)
                            .padding(.horizontal, 10)
                        HStack(spacing: 8) {
                            Button { importing = true } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Attach images or files, or paste with ⌘V")
                            .disabled(draft.isLoadingAttachments)
                            .accessibilityLabel("Attach files")
                            .accessibilityIdentifier("attach-images")
                            if loading {
                                ProgressView().controlSize(.small).accessibilityLabel("Loading configuration")
                            } else {
                                MacNewSessionConfiguration(options: $options)
                            }
                            Spacer(minLength: 8)
                            Button(action: start) {
                                MacComposerSendMark(enabled: canStart)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(!canStart)
                            .accessibilityLabel("Create")
                            .help("Create session (⌘Return)")
                            .accessibilityIdentifier("start-session")
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 720)
        .onExitCommand { dismiss() }
        .background { SheetScrimDismiss() }
        .onChange(of: model.sessions, initial: true) { _, sessions in
            projects = NewSessionDestination.projectTemplates(in: sessions)
        }
        .task(id: LoadKey(templateID: template.id, providerID: providerID, refresh: refresh, awake: isAwake)) {
            loading = true
            guard isAwake else { return }
            error = nil
            do {
                var result = try await model.newSessionOptions(templateSessionID: template.id,
                    agentConfigID: providerID, projectID: template.projectID,
                    isTab: destination.isTab, refresh: refresh > 0)
                if result.needsRefresh == true {
                    result = try await model.newSessionOptions(templateSessionID: template.id,
                        agentConfigID: providerID, projectID: template.projectID,
                        isTab: destination.isTab, refresh: true)
                }
                try Task.checkCancellation()
                if !restoredConfiguration {
                    if template.id == destination.template.id,
                       let start = destination.restoredStart,
                       start.request.agentConfigID == nil || result.agentConfigID == start.request.agentConfigID {
                        for choice in start.request.selections {
                            if let model = result.runConfig?.model, choice.configOptionID == model.configOptionID {
                                result.runConfig?.selectModel(choice.value)
                            } else if choice.configOptionID == result.runConfig?.reasoning?.configOptionID {
                                result.runConfig?.selectReasoning(choice.value)
                            }
                        }
                    }
                    restoredConfiguration = true
                }
                options = result
                loading = false
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                options = nil
                loading = false
                self.error = "Could not load configuration."
            }
        }
    }

    private func start() {
        guard !loading, !draft.isLoadingAttachments, let options, let projectID = template.projectID,
              let workspaceID = model.selectedWorkspaceID else { return }
        do {
            let id = try model.stageSessionStart(draft.text, composerText: draft.text, mentions: .init(),
                attachments: draft.attachments, agentConfigID: options.agentConfigID,
                selections: options.runConfig?.selections ?? [], projectID: projectID,
                projectName: template.projectName ?? "Project", templateSessionID: template.id,
                parentSessionID: destination.isTab ? template.id : nil)
            let turnID = model.outgoingMessage(sessionID: id)?.id
            Task {
                do { try await model.deliverOutgoingMessage(sessionID: id, workspaceID: workspaceID, turnID: turnID) }
                catch { /* Keep the outbox's reserved IDs for retry in the conversation. */ }
            }
            onStarted(id)
            dismiss()
        } catch { self.error = "Could not start the session. Check for a pending first message in this project." }
    }
}

private struct MacNewSessionConfiguration: View {
    @Binding var options: NewSessionOptions?

    var body: some View {
        HStack(spacing: 12) {
            if let config = options?.runConfig {
                if let model = config.model {
                    Picker("Model", selection: Binding(get: { model.value }, set: { options?.runConfig?.selectModel($0) })) {
                        ForEach(model.options) { Text($0.label).tag($0.value) }
                    }.accessibilityIdentifier("new-model")
                }
                if !config.reasoningOptions.isEmpty {
                    Picker("Reasoning", selection: Binding(get: { config.selectedReasoning?.value ?? "" },
                        set: { options?.runConfig?.selectReasoning($0) })) {
                        ForEach(config.reasoningOptions) { Text($0.label).tag($0.value) }
                    }.accessibilityIdentifier("new-reasoning")
                }
            } else {
                Text("This agent's configuration is read-only.").foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
        .labelsHidden()
        .fixedSize()
    }
}

/// macOS sheets ignore clicks on the dimmed parent window. This consumes those clicks.
private struct SheetScrimDismiss: NSViewRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeNSView(context: Context) -> SheetScrimMonitor {
        let view = SheetScrimMonitor()
        view.onDismiss = { dismiss() }
        return view
    }

    func updateNSView(_ view: SheetScrimMonitor, context: Context) {
        view.onDismiss = { dismiss() }
    }
}

private final class SheetScrimMonitor: NSView {
    var onDismiss: (() -> Void)?
    private var monitor: Any?
    private let box = SheetScrimBox()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        box.owner = self
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        let box = box
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            let consume = MainActor.assumeIsolated { box.owner?.consumeScrimClick(event) ?? false }
            return consume ? nil : event
        }
    }

    override func removeFromSuperview() {
        removeMonitor()
        super.removeFromSuperview()
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit { removeMonitor() }

    fileprivate func consumeScrimClick(_ event: NSEvent) -> Bool {
        guard event.buttonNumber == 0, let sheet = window, let source = event.window else { return false }
        if let modal = NSApp.modalWindow, modal !== sheet, modal !== (sheet.sheetParent ?? sheet.parent) { return false }
        if sheet.attachedSheet != nil || source is NSOpenPanel || source is NSSavePanel { return false }
        if source.level >= .popUpMenu || source === sheet { return false }

        guard let parent = sheet.sheetParent ?? sheet.parent else { return false }
        if source === parent, isTrafficLight(parent, windowPoint: event.locationInWindow) { return false }
        let screenPoint = source.convertPoint(toScreen: event.locationInWindow)
        guard parent.frame.contains(screenPoint), !sheet.frame.contains(screenPoint) else { return false }
        let scrim = source === parent || isScrimWindow(source, parent: parent)
        guard scrim else { return false }
        scheduleDismiss()
        return true
    }

    private func scheduleDismiss() {
        let action = onDismiss
        DispatchQueue.main.async { action?() }
    }

    private func isScrimWindow(_ window: NSWindow, parent: NSWindow) -> Bool {
        guard window !== parent, !window.styleMask.contains(.titled), !window.styleMask.contains(.utilityWindow) else { return false }
        return window.frame.width >= parent.frame.width * 0.8 && window.frame.height >= parent.frame.height * 0.8
    }

    private func isTrafficLight(_ window: NSWindow, windowPoint: NSPoint) -> Bool {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        return buttons.contains { type in
            guard let button = window.standardWindowButton(type) else { return false }
            return button.convert(button.bounds, to: nil).contains(windowPoint)
        }
    }
}

private final class SheetScrimBox: @unchecked Sendable {
    weak var owner: SheetScrimMonitor?
}
