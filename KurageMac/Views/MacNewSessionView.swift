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
                Button("Cancel", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                MacMessageEditor(text: $draft.text, accessibilityLabel: "First message",
                    accessibilityIdentifier: "new-message", initiallyFocused: true) {
                    draft.pendingAttachments.append(contentsOf: $0)
                }
                .frame(height: 150)
                .overlay(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text("What do you want to work on?").foregroundStyle(.tertiary)
                            .padding(.horizontal, 9).padding(.top, 6)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                MacAttachmentPicker(attachments: $draft.attachments, pending: $draft.pendingAttachments,
                    importing: $importing, showsButton: false)
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
                HStack(spacing: 12) {
                    if loading {
                        ProgressView().controlSize(.small).accessibilityLabel("Loading configuration")
                    } else {
                        MacNewSessionConfiguration(options: $options)
                    }
                    Spacer(minLength: 12)
                    Button("Attach files", systemImage: "plus") { importing = true }
                        .labelStyle(.iconOnly).buttonStyle(.plain)
                        .help("Attach images or files, or paste with ⌘V")
                        .disabled(draft.isLoadingAttachments).accessibilityIdentifier("attach-images")
                    Button("Create", systemImage: "return", action: start)
                        .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                        .disabled(pendingStart != nil || loading || draft.isLoadingAttachments || options == nil || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.attachments.isEmpty)
                        .accessibilityIdentifier("start-session")
                }
            }
            .padding(20)
        }
        .frame(width: 720)
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
        .labelsHidden()
        .fixedSize()
    }
}
