import Foundation
import Testing
@testable import Kurage
@testable import KurageCore

@MainActor
struct DefaultModelTests {
    private func entry(_ provider: String, _ model: String) -> DefaultModel {
        DefaultModel(agentConfigID: provider, modelID: model, providerName: provider, modelName: model)
    }

    @Test func orderLimitDeduplicationAndScopePersist() async throws {
        let suite = "DefaultModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await model.adoptExistingAccount()
        let entries = [entry("claude", "opus"), entry("codex", "same"), entry("claude", "same"),
                       entry("codex", "gpt-5.5"), entry("codex", "gpt-5.4-mini")]
        model.saveDefaultModels(entries, sessionID: "session-pr", workspaceGeneration: model.workspaceGeneration)
        #expect(model.defaultModels(sessionID: "session-pr") == entries)
        model.saveDefaultModels(entries + [entry("claude", "sixth")], sessionID: "session-pr", workspaceGeneration: model.workspaceGeneration)
        model.saveDefaultModels([entries[0], entries[0]], sessionID: "session-pr", workspaceGeneration: model.workspaceGeneration)
        #expect(model.defaultModels(sessionID: "session-pr") == entries)

        let reordered = [entries[4], entries[1], entries[0]]
        model.saveDefaultModels(reordered, sessionID: "session-pr", workspaceGeneration: model.workspaceGeneration)
        let restored = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await restored.adoptExistingAccount()
        #expect(restored.defaultModels(sessionID: "session-pr") == reordered)
        restored.saveDefaultModels([], sessionID: "session-pr", workspaceGeneration: restored.workspaceGeneration - 1)
        #expect(restored.defaultModels(sessionID: "session-pr") == reordered)
        let account = try #require(model.account)
        let key = DefaultModel.storageKey(account: account, workspaceID: "ws-demo", machineID: "machine-1")
        #expect(key != DefaultModel.storageKey(account: account, workspaceID: "other", machineID: "machine-1"))
        #expect(key != DefaultModel.storageKey(account: account, workspaceID: "ws-demo", machineID: "other"))
        #expect(key != DefaultModel.storageKey(account: Account(email: "other@example.test"), workspaceID: "ws-demo", machineID: "machine-1"))
        model.signOut()
        #expect(model.defaultModels(sessionID: "session-pr").isEmpty)
        #expect(restored.defaultModels(sessionID: "session-pr") == reordered)
    }

    @Test func recentShortcutSelectsBothProviderAndModelWithoutReasoningMemory() async throws {
        let fixture = FixtureLodyClient(startsSignedIn: true)
        let configuration = NewSessionConfiguration()
        await configuration.load(providerID: "codex") { id in
            try await fixture.newSessionOptions(templateSessionID: "session-pr", agentConfigID: id, workspaceID: "ws-demo")
        }
        let mini = entry("codex", "gpt-5.4-mini")
        let opus = entry("claude", "opus")
        let missing = entry("removed", "opus")
        let saved = [mini, missing, opus]
        let rows = try #require(configuration.shortcutMenu(saved: saved)?.modelShortcuts)
        #expect(rows.filter { !$0.isSelected }.map(\.model) == saved)
        #expect(rows.first { $0.id == missing.id }?.isEnabled == false)
        #expect(!configuration.selectDefaultModel(entry("codex", "opus")))
        #expect(configuration.options?.agentConfigID == "codex")
        configuration.selectReasoning("low")
        #expect(configuration.selectDefaultModel(mini))
        #expect(configuration.runConfig?.model?.value == "gpt-5.4-mini")
        #expect(configuration.runConfig?.selectedReasoning?.value == "low")
        #expect(configuration.selectDefaultModel(opus))
        #expect(configuration.options?.agentConfigID == "claude")
        #expect(configuration.runConfig?.model?.value == "opus")
        #expect(configuration.runConfig?.selectedReasoning == nil)
        #expect(configuration.selectDefaultModel(mini))
        #expect(configuration.runConfig?.selectedReasoning?.value == "low")
        #expect(!configuration.selectDefaultModel(missing))
        #expect(configuration.options?.agentConfigID == "codex")
    }

    @Test func favoriteReasoningIsIndependentPersistentAndOnlyWritesChanges() async throws {
        let suite = "DefaultModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await model.adoptExistingAccount()
        let entries = [entry("codex", "gpt-5.5"), entry("codex", "gpt-5.4-mini"), entry("other", "gpt-5.5")]
        let generation = model.workspaceGeneration
        model.saveDefaultModels(entries, sessionID: "session-pr", workspaceGeneration: generation)
        let high = DefaultModel.Reasoning(configOptionID: "reasoning_effort", value: "high")
        let low = DefaultModel.Reasoning(configOptionID: "reasoning_effort", value: "low")
        func remember(_ modelID: String, _ reasoning: DefaultModel.Reasoning, generation: Int) {
            model.rememberDefaultModelReasoning(agentConfigID: "codex", modelID: modelID,
                reasoning: reasoning, sessionID: "session-pr", workspaceGeneration: generation)
        }
        remember("gpt-5.5", high, generation: generation)
        remember("gpt-5.4-mini", low, generation: generation)
        let revision = model.defaultModelsRevision
        model.rememberDefaultModelReasoning(agentConfigID: "codex", modelID: "gpt-5.5", reasoning: low,
            sessionID: "session-pr", workspaceGeneration: generation, onlyIfMissing: true)
        remember("gpt-5.5", high, generation: generation)
        remember("not-favorited", low, generation: generation)
        remember("gpt-5.5", low, generation: generation - 1)
        #expect(model.defaultModelsRevision == revision)
        let restored = AppModel(client: FixtureLodyClient(startsSignedIn: true), quickActionDefaults: defaults)
        await restored.adoptExistingAccount()
        let saved = restored.defaultModels(sessionID: "session-pr")
        #expect(saved.map(\.lastReasoning) == [high, low, nil])
        model.saveDefaultModels([saved[1], saved[0]], sessionID: "session-pr", workspaceGeneration: generation)
        #expect(model.defaultModels(sessionID: "session-pr").map(\.lastReasoning) == [low, high])
        model.saveDefaultModels([entries[0]], sessionID: "session-pr", workspaceGeneration: generation)
        #expect(model.defaultModels(sessionID: "session-pr").first?.lastReasoning == nil)
    }

    @Test func shortcutsAndAdvancedRestoreEachFavoritesReasoningAndValidateCapabilities() async throws {
        let fixture = FixtureLodyClient(startsSignedIn: true)
        let configuration = NewSessionConfiguration()
        await configuration.load(providerID: "codex") { id in
            try await fixture.newSessionOptions(templateSessionID: "session-pr", agentConfigID: id, workspaceID: "ws-demo")
        }
        var full = entry("codex", "gpt-5.5")
        full.lastReasoning = .init(configOptionID: "reasoning_effort", value: "high")
        var mini = entry("codex", "gpt-5.4-mini")
        mini.lastReasoning = .init(configOptionID: "reasoning_effort", value: "low")
        let saved = [full, mini]
        #expect(configuration.selectDefaultModel(full, saved: saved))
        #expect(configuration.runConfig?.selectedReasoning?.value == "high")
        #expect(configuration.selectDefaultModel(mini, saved: saved))
        #expect(configuration.runConfig?.selectedReasoning?.value == "low")
        configuration.selectModel(full.modelID, saved: saved)
        #expect(configuration.runConfig?.selectedReasoning?.value == "high")
        configuration.selectModel(mini.modelID, saved: saved)
        #expect(configuration.runConfig?.selectedReasoning?.value == "low")
        // An unavailable effort or a changed option identity must not reuse the previous model's value.
        mini.lastReasoning = .init(configOptionID: "reasoning_effort", value: "retired")
        #expect(configuration.selectDefaultModel(mini, saved: [mini]))
        #expect(configuration.runConfig?.selectedReasoning?.value == "low")
        mini.lastReasoning = .init(configOptionID: "thought_level", value: "low")
        #expect(configuration.selectDefaultModel(mini, saved: [mini]))
        #expect(configuration.runConfig?.selectedReasoning?.value == "low")
        mini.lastReasoning = nil
        #expect(configuration.selectDefaultModel(mini, saved: [mini]))
        await configuration.load(providerID: "codex") { id in
            try await fixture.newSessionOptions(templateSessionID: "session-pr", agentConfigID: id, workspaceID: "ws-demo")
        }
        #expect(configuration.runConfig?.selectedReasoning?.value == "low")
        #expect(configuration.runConfig?.selections.count == 2)
        #expect(configuration.selectDefaultModel(full, saved: saved))
        #expect(configuration.runConfig?.selectedReasoning?.value == "high")
    }

    @Test func missingOrInvalidFavoriteMemoryDisplaysAndSendsAnExplicitCapabilityValue() throws {
        var config = NewSessionRunConfig.fixture
        let favorite = entry("codex", "gpt-5.5")
        for memory in [nil, DefaultModel.Reasoning(configOptionID: "old-option", value: "high"),
                       DefaultModel.Reasoning(configOptionID: "reasoning_effort", value: "retired")] {
            config.selectReasoning("high")
            var saved = favorite
            saved.lastReasoning = memory
            saved.restoreReasoning(in: &config)
            #expect(config.reasoning?.value == "medium")
            #expect(config.selections.last == RunConfigChoice(configOptionID: "reasoning_effort", value: "medium"))
            let options = NewSessionOptions(machineName: "Machine", agentConfigID: "codex", providers: [], runConfig: config)
            #expect(options.menu(config).reasoningLabel == "Medium")
            let roundTrip = try JSONDecoder().decode(NewSessionRunConfig.self, from: JSONEncoder().encode(config))
            #expect(roundTrip.reasoning?.defaultValue == "medium")
            #expect(roundTrip.selections == config.selections)
        }
        // A capability preference that this model cannot use resolves to its offered value.
        config.selectModel("gpt-5.4-mini")
        #expect(config.selectedReasoning?.value == "low")
        #expect(config.selections.last?.value == "low")
        // Legacy capability projections without a preferred value still send what they display.
        config.reasoning?.defaultValue = nil
        config.reasoning?.value = nil
        #expect(config.selectedReasoning?.value == "low")
        #expect(config.selections.last?.value == "low")
    }

    @Test func existingSessionNeverMatchesAnotherProvidersModelOrByDisplayName() throws {
        let saved = [entry("other", "opus"), entry("claude", "opus"), entry("claude", "retired")]
        let menu = try #require(SessionRunConfig.fixtureModel.shortcutMenu(saved: saved, agentConfigID: "claude", agentName: "Same Name"))
        #expect(menu.modelShortcuts.map(\.model.modelID) == ["sonnet", "opus", "retired"])
        #expect(menu.modelShortcuts.map(\.isEnabled) == [false, true, false])
        #expect(menu.modelShortcuts.allSatisfy { $0.model.agentConfigID == "claude" })
        let unknown = try #require(SessionRunConfig.fixtureModel.shortcutMenu(saved: saved, agentConfigID: nil, agentName: "claude"))
        #expect(unknown.modelShortcuts.count == 1)
        #expect(!unknown.modelShortcuts[0].isEnabled)

        let locked = try #require(SessionRunConfig.fixtureReasoning.shortcutMenu(
            saved: [entry("codex", "gpt-5.4-mini")], agentConfigID: "codex", agentName: "Codex"))
        #expect(locked.modelShortcuts.allSatisfy { !$0.isEnabled })
        #expect(locked.sections.first?.kind == .reasoning)
    }

    @Test func emptyFavoritesUseOnlyRecentModelsAndKeepCurrentWithinFive() async throws {
        let configuration = NewSessionConfiguration()
        await configuration.load(providerID: "codex") { provider in
            NewSessionOptions(machineName: "Machine", agentConfigID: provider ?? "codex",
                providers: [.init(value: "codex", label: "Codex"), .init(value: "claude", label: "Claude")],
                runConfig: NewSessionRunConfig(model: .init(configOptionID: nil, value: "m0",
                    options: (0...6).map { .init(value: "m\($0)", label: "Model \($0)", reasoning: []) }), reasoning: nil))
        }
        let recent = [entry("claude", "m1"), entry("codex", "m5"), entry("codex", "m3"),
                      entry("codex", "m2"), entry("codex", "m1")]
        let rows = try #require(configuration.shortcutMenu(saved: [], recent: recent)?.modelShortcuts)
        #expect(rows.map(\.model.id) == [entry("codex", "m0").id] + recent.prefix(4).map(\.id))
        #expect(rows.count == 5)
        #expect(rows.first?.isSelected == true)
        #expect(configuration.options?.agentConfigID == "codex")
        #expect(configuration.runConfig?.selectedModel?.value == "m0")
        #expect(configuration.shortcutMenu(saved: [])?.modelShortcuts.map(\.model.modelID) == ["m0"])
        #expect(configuration.shortcutMenu(saved: [entry("codex", "m6")], recent: recent)?
            .modelShortcuts.map(\.model.modelID) == ["m0", "m6"])
        #expect(configuration.shortcutMenu(saved: [], recent: [entry("removed", "m1"), entry("codex", "retired")])?
            .modelShortcuts.map(\.model.modelID) == ["m0"])
    }

    @Test func noCurrentOrRecentModelsLeavesAnEmptyListWithAdvancedChoices() async throws {
        let fixture = FixtureLodyClient(startsSignedIn: true, hasModelHistory: false)
        let configuration = NewSessionConfiguration()
        await configuration.load(providerID: nil) { provider in
            try await fixture.newSessionOptions(templateSessionID: "session-pr", agentConfigID: provider, workspaceID: "ws-demo")
        }
        #expect(try await fixture.recentModels(sessionID: "session-pr", agentConfigID: nil, workspaceID: "ws-demo").isEmpty)
        let menu = try #require(configuration.shortcutMenu(saved: []))
        #expect(menu.modelShortcuts.isEmpty)
        #expect(menu.sections.contains { $0.kind == .model && !$0.options.isEmpty })
        configuration.selectModel("opus")
        #expect(configuration.shortcutMenu(saved: [])?.modelShortcuts.map(\.model.modelID) == ["opus"])
    }

    @Test func existingSessionRecentModelsRespectProviderAndEditableCapability() throws {
        let recent = [entry("other", "opus"), entry("claude", "retired"), entry("claude", "opus")]
        let menu = try #require(SessionRunConfig.fixtureModel.shortcutMenu(saved: [], recent: recent,
            agentConfigID: "claude", agentName: "Claude"))
        #expect(menu.modelShortcuts.map(\.model.modelID) == ["sonnet", "opus"])
        #expect(menu.modelShortcuts.map(\.isEnabled) == [false, true])
        #expect(SessionRunConfig.fixtureModel.shortcutMenu(saved: [], agentConfigID: "claude", agentName: "Claude")?
            .modelShortcuts.map(\.model.modelID) == ["sonnet"])
        let locked = try #require(SessionRunConfig.fixtureReasoning.shortcutMenu(saved: [],
            recent: [entry("codex", "gpt-5.4-mini")], agentConfigID: "codex", agentName: "Codex"))
        #expect(locked.modelShortcuts.map(\.model.modelID) == ["gpt-5.5"])
        #expect(locked.modelShortcuts.allSatisfy { !$0.isEnabled })
    }

    @Test func recentModelsWireContractAndFixtureHistoryExcludeUnusedOptions() async throws {
        let json = #"[{"agentConfigID":"custom-config","modelID":"same","providerName":"Provider","modelName":"Model","icon":null}]"#
        let decoded = try JSONDecoder().decode([DefaultModel].self, from: Data(json.utf8))
        #expect(decoded == [DefaultModel(agentConfigID: "custom-config", modelID: "same", providerName: "Provider", modelName: "Model")])
        let fixture = FixtureLodyClient(startsSignedIn: true)
        let models = try await fixture.recentModels(sessionID: "session-pr", agentConfigID: nil, workspaceID: "ws-demo")
        #expect(models.map(\.modelID) == ["gpt-5.5", "sonnet"])
        #expect(try await fixture.recentModels(sessionID: "session-pr", agentConfigID: "claude", workspaceID: "ws-demo")
            .map(\.modelID) == ["sonnet"])
        await #expect(throws: LodyClientError.self) {
            try await fixture.recentModels(sessionID: "session-pr", agentConfigID: nil, workspaceID: "other")
        }
    }

    @Test func tabWireIdentityIsOptionalForLegacyCachesAndDistinctFromAgentName() throws {
        let json = #"{"id":"tab","title":"Tab","agentName":"claude","activity":"idle","preview":"","agentConfigID":"custom-config-123"}"#
        let tab = try JSONDecoder().decode(SessionSummary.self, from: Data(json.utf8))
        #expect(tab.agentConfigID == "custom-config-123")
        let legacy = #"{"id":"root","title":"Root","agentName":"claude","activity":"idle","preview":""}"#
        #expect(try JSONDecoder().decode(SessionSummary.self, from: Data(legacy.utf8)).agentConfigID == nil)
    }
}
