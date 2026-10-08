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

    private struct LoadKey: Equatable {
        let providerID: String?
        let refresh: Int
        let awake: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(destination.isTab ? "New tab" : "New session").font(.title2.bold())
            Text(destination.template.projectName ?? "Project").foregroundStyle(.secondary)
            if let options {
                if !options.providers.isEmpty {
                    Picker("Agent", selection: Binding(get: { providerID ?? options.agentConfigID }, set: { providerID = $0 })) {
                        ForEach(options.providers) { Text($0.label).tag($0.value) }
                    }
                    .accessibilityIdentifier("new-agent")
                }
                MacNewSessionConfiguration(options: $options)
            }
            if loading { ProgressView("Loading configuration…") }
            if let error {
                HStack {
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { refresh += 1 }
                }
            }
            MacAttachmentPicker(attachments: $draft.attachments, loading: $draft.isLoadingAttachments)
            TextEditor(text: $draft.text).font(.body).frame(height: 160)
                .accessibilityLabel("First message").accessibilityIdentifier("new-message")
                .border(.separator)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start session", action: start)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(loading || draft.isLoadingAttachments || options == nil || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.attachments.isEmpty)
                    .accessibilityIdentifier("start-session")
            }
        }
        .padding(24).frame(width: 540)
        .task(id: LoadKey(providerID: providerID, refresh: refresh, awake: isAwake)) {
            loading = true
            guard isAwake else { return }
            error = nil
            do {
                var result = try await model.newSessionOptions(templateSessionID: destination.template.id,
                    agentConfigID: providerID, projectID: destination.template.projectID,
                    isTab: destination.isTab, refresh: refresh > 0)
                if result.needsRefresh == true {
                    result = try await model.newSessionOptions(templateSessionID: destination.template.id,
                        agentConfigID: providerID, projectID: destination.template.projectID,
                        isTab: destination.isTab, refresh: true)
                }
                try Task.checkCancellation()
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
        guard !loading, let options, let projectID = destination.template.projectID,
              let workspaceID = model.selectedWorkspaceID else { return }
        do {
            let id = try model.stageSessionStart(draft.text, composerText: draft.text, mentions: .init(),
                attachments: draft.attachments, agentConfigID: options.agentConfigID,
                selections: options.runConfig?.selections ?? [], projectID: projectID,
                projectName: destination.template.projectName ?? "Project", templateSessionID: destination.template.id,
                parentSessionID: destination.isTab ? destination.template.id : nil)
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
        VStack(alignment: .leading, spacing: 12) {
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
    }
}
