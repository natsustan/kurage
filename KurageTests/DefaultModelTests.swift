import Foundation
import Testing
@testable import Kurage

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

    @Test func newSessionShortcutSelectsBothProviderAndModelWithoutReasoningPreset() async throws {
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

    @Test func tabWireIdentityIsOptionalForLegacyCachesAndDistinctFromAgentName() throws {
        let json = #"{"id":"tab","title":"Tab","agentName":"claude","activity":"idle","preview":"","agentConfigID":"custom-config-123"}"#
        let tab = try JSONDecoder().decode(SessionSummary.self, from: Data(json.utf8))
        #expect(tab.agentConfigID == "custom-config-123")
        let legacy = #"{"id":"root","title":"Root","agentName":"claude","activity":"idle","preview":""}"#
        #expect(try JSONDecoder().decode(SessionSummary.self, from: Data(legacy.utf8)).agentConfigID == nil)
    }
}
