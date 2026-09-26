import SwiftUI

struct NewSessionRoute: Hashable {
    let projectID: String
    let projectName: String
    /// The project's most recent session; the new session reuses its machine and, by default, its agent.
    let templateSessionID: SessionSummary.ID
    let workspaceGeneration: Int
}

extension NewSessionOptions {
    /// Provider, model and reasoning for the first turn, in the composer's run-config menu.
    func menu(_ runConfig: NewSessionRunConfig?) -> RunConfigMenu {
        var sections: [RunConfigMenu.Section] = []
        if providers.count > 1 {
            sections.append(.init(kind: .provider, options: providers, selection: agentConfigID))
        }
        if let model = runConfig?.model {
            sections.append(.init(
                kind: .model,
                options: model.options.map { SessionRunConfig.Value(value: $0.value, label: $0.label) },
                selection: model.value
            ))
        }
        if let runConfig, !runConfig.reasoningOptions.isEmpty {
            sections.append(.init(kind: .reasoning, options: runConfig.reasoningOptions,
                                  selection: runConfig.selectedReasoning?.value ?? ""))
        }
        let provider = provider?.label
        let model = runConfig?.selectedModel?.label
        let reasoning = runConfig?.selectedReasoning?.label
        return RunConfigMenu(
            modelLabel: model, reasoningLabel: reasoning, providerLabel: provider,
            accessibilitySummary: [provider.map { "Provider \($0)" }, model.map { "model \($0)" },
                                   reasoning.map { "reasoning \($0)" }]
                .compactMap { $0 }.joined(separator: ", "),
            sections: sections
        )
    }
}

/// Starts a session in a local project from its first message.
struct NewSessionView: View {
    let route: NewSessionRoute
    let model: AppModel
    let onStarted: (SessionSummary.ID) -> Void

    private struct LoadRequest: Equatable {
        var agentConfigID: String?
        var attempt = 0
    }

    @State private var configuration = NewSessionConfiguration()
    @State private var request = LoadRequest()
    @State private var draft = ""
    @State private var isStarting = false
    @State private var banner: String?
    @Environment(\.scenePhase) private var scenePhase

    private var options: NewSessionOptions? { configuration.options }
    private var runConfig: NewSessionRunConfig? { configuration.runConfig }
    private var isLoading: Bool { configuration.isLoading }
    private var loadFailed: Bool { configuration.loadFailed }

    private var isCurrentWorkspace: Bool { model.workspaceGeneration == route.workspaceGeneration }

    var body: some View {
        // Short details sit just above the composer; large text scrolls instead of
        // pushing the composer under the keyboard.
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                details
                if let banner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            SessionComposer(
                draft: $draft, isSending: isStarting, isCancelling: false, isSessionRunning: false,
                supportsTextSending: true, supportsTextSendingWhileRunning: false,
                supportsSessionCancellation: false,
                runConfig: configuration.menu,
                placeholder: "Describe a task",
                identifiers: .init(container: "new-session-composer", field: "new-session-field",
                                   send: "new-session-send"),
                canSubmit: isCurrentWorkspace && options != nil && !isLoading && !loadFailed,
                focusesOnAppear: true,
                onSend: start, onCancel: {}, onChooseRunConfig: choose
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
        .navigationTitle("New Session")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request) { await load() }
        .onDisappear { configuration.cancelLoads() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { request.attempt += 1 }
            else { configuration.cancelLoads() }
        }
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let options {
                detailRow(options.machineName, systemImage: "laptopcomputer")
            }
            detailRow(route.projectName, systemImage: "folder")
            if isLoading {
                ProgressView()
                    .accessibilityLabel("Loading agent")
            } else if loadFailed {
                Button("Could not load the agent. Retry", systemImage: "arrow.clockwise") {
                    request.attempt += 1
                }
                .font(.subheadline)
                .accessibilityIdentifier("new-session-retry")
            }
        }
        .foregroundStyle(.secondary)
    }

    private func detailRow(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title).lineLimit(1)
        } icon: {
            NewSessionIcon(systemImage: systemImage)
        }
        .font(.body)
    }

    private func load() async {
        guard isCurrentWorkspace else { return }
        await configuration.load(providerID: request.agentConfigID) { providerID in
            guard isCurrentWorkspace else { throw CancellationError() }
            let loaded = try await model.newSessionOptions(
                templateSessionID: route.templateSessionID, agentConfigID: providerID
            )
            guard isCurrentWorkspace else { throw CancellationError() }
            return loaded
        }
    }

    private func choose(_ kind: RunConfigMenu.Section.Kind, _ value: String) {
        guard isCurrentWorkspace, !isStarting else { return }
        switch kind {
        case .provider:
            guard configuration.selectProvider(value) else { return }
            request = LoadRequest(agentConfigID: value, attempt: request.attempt + 1)
        case .model:
            configuration.selectModel(value)
        case .reasoning:
            configuration.selectReasoning(value)
        }
    }

    private func start() {
        guard isCurrentWorkspace, let options, !isLoading, !loadFailed, !isStarting,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = draft
        let selections = runConfig?.selections ?? []
        isStarting = true
        banner = nil
        Task {
            defer { isStarting = false }
            do {
                let sessionID = try await model.startSession(
                    text, agentConfigID: options.agentConfigID.isEmpty ? nil : options.agentConfigID,
                    selections: selections, projectID: route.projectID,
                    templateSessionID: route.templateSessionID
                )
                guard isCurrentWorkspace else { return }
                onStarted(sessionID)
            } catch LodyClientError.previousSendPending(let previousText) {
                draft = previousText
                banner = "An earlier start is unconfirmed. Send it again to resume it."
            } catch is CancellationError {
                return
            } catch {
                banner = "Could not confirm the new session. Send again to resume it."
            }
        }
    }
}

/// Keeps the detail titles aligned across symbols of different widths.
private struct NewSessionIcon: View {
    let systemImage: String
    @ScaledMetric(relativeTo: .body) private var width = 28

    var body: some View {
        Image(systemName: systemImage)
            .frame(width: width)
    }
}


/// Page-scoped options and selections. Prefetching never changes the active
/// provider, and cancelled/older requests cannot overwrite a newer selection.
@MainActor @Observable
final class NewSessionConfiguration {
    private(set) var options: NewSessionOptions?
    private(set) var runConfig: NewSessionRunConfig?
    private(set) var isLoading = true
    private(set) var loadFailed = false
    @ObservationIgnored private var cached: [String: NewSessionOptions] = [:]
    @ObservationIgnored private var selections: [String: NewSessionRunConfig] = [:]
    @ObservationIgnored private var generation = 0
    private struct PendingLoad {
        let id = UUID()
        let task: Task<NewSessionOptions, Error>
    }
    @ObservationIgnored private var inFlight: [String: PendingLoad] = [:]

    var menu: RunConfigMenu? {
        guard let options else { return nil }
        var menu = options.menu(runConfig)
        menu.isLoading = isLoading
        menu.loadFailed = loadFailed
        return menu
    }

    @discardableResult
    func selectProvider(_ id: String) -> Bool {
        guard let current = options, current.providers.contains(where: { $0.value == id }),
              id != current.agentConfigID || loadFailed else { return false }
        if let runConfig, !isLoading, !loadFailed { selections[current.agentConfigID] = runConfig }
        generation += 1
        loadFailed = false
        if let cached = cached[id] {
            activate(cached)
        } else {
            // Reflect the new provider immediately, without exposing the old
            // provider's model/reasoning while its options load.
            options = NewSessionOptions(machineName: current.machineName, agentConfigID: id,
                                        providers: current.providers, runConfig: nil)
            runConfig = nil
            isLoading = true
        }
        return true
    }

    func selectModel(_ value: String) {
        guard !isLoading, !loadFailed else { return }
        runConfig?.selectModel(value)
        rememberSelection()
    }

    func selectReasoning(_ value: String) {
        guard !isLoading, !loadFailed else { return }
        runConfig?.selectReasoning(value)
        rememberSelection()
    }

    private func rememberSelection() {
        if let id = options?.agentConfigID, let runConfig { selections[id] = runConfig }
    }

    func load(providerID: String?, using fetch: @escaping @MainActor (String?) async throws -> NewSessionOptions) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let request = generation
        loadFailed = false
        if let providerID, let existing = cached[providerID] {
            activate(existing)
        } else {
            isLoading = true
            do {
                let loaded = try await fetchOptions(providerID, using: fetch)
                try Task.checkCancellation()
                guard request == generation else { return }
                cached[loaded.agentConfigID] = loaded
                activate(loaded)
            } catch is CancellationError {
                return
            } catch {
                guard request == generation, !Task.isCancelled else { return }
                isLoading = false
                loadFailed = true
                return
            }
        }
        // Resolve other providers during the time spent composing. Their most
        // recent run configuration still comes from the service, not a guess.
        let providers = options?.providers ?? []
        for provider in providers where cached[provider.value] == nil {
            guard request == generation, !Task.isCancelled else { return }
            do {
                let loaded = try await fetchOptions(provider.value, using: fetch)
                try Task.checkCancellation()
                guard request == generation else { return }
                cached[loaded.agentConfigID] = loaded
            } catch {
                // A failed prefetch is retried only if this provider is chosen.
                if Task.isCancelled || request != generation { return }
            }
        }
    }

    func cancelLoads() {
        generation += 1
        for pending in inFlight.values { pending.task.cancel() }
        inFlight.removeAll()
    }

    private func fetchOptions(
        _ providerID: String?,
        using fetch: @escaping @MainActor (String?) async throws -> NewSessionOptions
    ) async throws -> NewSessionOptions {
        let key = providerID ?? ""
        let pending: PendingLoad
        if let existing = inFlight[key] {
            pending = existing
        } else {
            pending = PendingLoad(task: Task {
                let loaded = try await fetch(providerID)
                try Task.checkCancellation()
                return loaded
            })
            inFlight[key] = pending
        }
        defer {
            if inFlight[key]?.id == pending.id { inFlight.removeValue(forKey: key) }
        }
        return try await pending.task.value
    }

    private func activate(_ loaded: NewSessionOptions) {
        options = loaded
        runConfig = selections[loaded.agentConfigID] ?? loaded.runConfig
        isLoading = false
        loadFailed = false
    }
}
