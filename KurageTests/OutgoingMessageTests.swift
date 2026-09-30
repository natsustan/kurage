import Foundation
import Testing
@testable import Kurage

@MainActor
struct OutgoingMessageTests {
    @Test func stageImmediatelyIncludesTextImagesFilesAndOriginalPreview() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()
        let image = try ComposerAttachment(fileName: "photo.png", mimeType: "image/png", data: FixtureImage.png,
                                          isImage: true, thumbnailData: FixtureImage.png)
        let file = try ComposerAttachment(fileName: "notes.txt", mimeType: "text/plain", data: Data("notes".utf8), isImage: false)
        try model.stageOutgoingMessage("  Look at this  ", composerText: "  Look at this  ", mentions: .init(),
                                       attachments: [image, file], runConfig: nil, sessionID: "session-long")
        let turn = try #require(model.displayedTurns([], sessionID: "session-long").first)
        #expect(turn.text == "Look at this")
        #expect(turn.delivery == .sending)
        #expect(turn.content.count == 3)
        guard case .image(let preview) = turn.content[0] else { Issue.record("Missing immediate image"); return }
        #expect(preview.localPreviewData == image.thumbnailData)
        #expect(try await model.loadSessionImage(preview, conversationSessionID: "session-long", variant: .original) == image.data)
        let decoded = try JSONDecoder().decode(ConversationTurn.self, from: JSONEncoder().encode(turn))
        #expect(decoded.delivery == nil)
        guard case .image(let wireImage) = decoded.content[0] else { Issue.record("Missing encoded image"); return }
        #expect(wireImage.localPreviewData == nil)
        #expect(wireImage.localOriginalData == nil)
    }

    @Test func unconfirmedMessageStaysVisibleAndRetryKeepsItsIdentityAndAttachments() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, failSendOnce: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        var updates = try await client.observeConversation(sessionID: "session-long", workspaceID: "ws-demo").makeAsyncIterator()
        let config = try #require(await updates.next()?.runConfig)
        let choice = try #require(config.choosing("low"))
        let image = try ComposerAttachment(fileName: "photo.png", mimeType: "image/png", data: FixtureImage.png, isImage: true)
        try model.stageOutgoingMessage("Retry photo", composerText: "Retry photo", mentions: .init(),
                                       attachments: [image], runConfig: choice, sessionID: "session-long")
        let original = try #require(model.outgoingMessage(sessionID: "session-long"))
        await #expect(throws: LodyClientError.deliveryUnconfirmed) { try await model.deliverOutgoingMessage(sessionID: "session-long") }
        #expect(model.outgoingMessage(sessionID: "session-long")?.delivery == .unconfirmed)
        #expect(model.displayedTurns([], sessionID: "session-long").map(\.id) == [original.id])
        #expect(model.takeFailedOutgoingMessage(sessionID: "session-long") == nil)
        #expect(model.retryOutgoingMessage(sessionID: "session-long"))
        #expect(try await model.deliverOutgoingMessage(sessionID: "session-long") == choice)
        #expect(model.outgoingMessage(sessionID: "session-long") == nil)
        let received = try #require(model.cachedConversation(sessionID: "session-long"))
        #expect(received.turns.filter { $0.text == "Retry photo" }.map(\.id) == [original.id])
        let preview = try #require(received.turns.last?.content.compactMap { part -> ConversationImage? in
            if case .image(let image) = part { return image }
            return nil
        }.first)
        #expect(preview.localPreviewData == image.data)
        #expect(preview.localOriginalData == nil)
        let refreshed = try await model.conversation(sessionID: "session-long")
        #expect(refreshed == received)
    }

    @Test func rejectedMessageRetainsTheEditableDraftAndSelectedMentions() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true, rejectSendOnce: true))
        await model.adoptExistingAccount()
        var mentions = ComposerMentionState()
        let text = "$review"
        let (draft, _) = mentions.insert("$review", kind: .skill(token: "$review", path: "/skills/review"),
                                        replacing: text.startIndex..<text.endIndex, in: text)
        let file = try ComposerAttachment(fileName: "notes.txt", mimeType: "text/plain", data: Data("notes".utf8), isImage: false)
        try model.stageOutgoingMessage(mentions.expanded(draft), composerText: draft, mentions: mentions,
                                       attachments: [file], runConfig: nil, sessionID: "session-long")
        await #expect(throws: LodyClientError.sessionBusy) { try await model.deliverOutgoingMessage(sessionID: "session-long") }
        let message = try #require(model.takeFailedOutgoingMessage(sessionID: "session-long"))
        #expect(message.composerText == draft)
        #expect(message.mentions == mentions)
        #expect(message.attachments == [file])
        #expect(model.outgoingMessage(sessionID: "session-long") == nil)
    }

    @Test func historyEchoDoesNotTurnAnUnconfirmedDispatchIntoSuccess() async throws {
        let client = ControlledMessageClient()
        client.unconfirmed = true
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        try model.stageOutgoingMessage("Echoed", composerText: "Echoed", mentions: .init(),
                                       attachments: [], runConfig: nil, sessionID: "same-session")
        await #expect(throws: LodyClientError.deliveryUnconfirmed) { try await model.deliverOutgoingMessage(sessionID: "same-session") }
        let received = try await model.conversation(sessionID: "same-session")
        #expect(received.turns.count == 1)
        #expect(model.displayedTurns(received.turns, sessionID: "same-session").count == 1)
        #expect(model.outgoingMessage(sessionID: "same-session")?.delivery == .unconfirmed)
        client.unconfirmed = false
        #expect(model.retryOutgoingMessage(sessionID: "same-session"))
        try await model.deliverOutgoingMessage(sessionID: "same-session")
        #expect(model.outgoingMessage(sessionID: "same-session") == nil)
        #expect(model.cachedConversation(sessionID: "same-session")?.turns.count == 1)
    }

    @Test func workspaceSwitchAndLateCompletionKeepSameSessionIDsIsolated() async throws {
        let client = ControlledMessageClient()
        client.suspends = true
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        try model.stageOutgoingMessage("Workspace A", composerText: "Workspace A", mentions: .init(),
                                       attachments: [], runConfig: nil, sessionID: "same-session")
        var started = client.started.makeAsyncIterator()
        let send = Task { try await model.deliverOutgoingMessage(sessionID: "same-session", workspaceID: "a") }
        _ = await started.next()
        await model.selectWorkspace("b")
        #expect(model.outgoingMessage(sessionID: "same-session") == nil)
        #expect(model.displayedTurns([], sessionID: "same-session").isEmpty)
        client.finish()
        _ = try await send.value
        #expect(model.cachedConversation(sessionID: "same-session") == nil)
        await model.selectWorkspace("a")
        #expect(model.cachedConversation(sessionID: "same-session")?.turns.map(\.text) == ["Workspace A"])
    }

    @Test func editingASupersededTurnPreservesItsRejectedStatusInHistory() async throws {
        let client = ControlledMessageClient()
        client.rejection = .sendSuperseded
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        try model.stageOutgoingMessage("Superseded", composerText: "Superseded", mentions: .init(),
                                       attachments: [], runConfig: nil, sessionID: "same-session")
        await #expect(throws: LodyClientError.sendSuperseded) {
            try await model.deliverOutgoingMessage(sessionID: "same-session")
        }
        #expect(!model.retryOutgoingMessage(sessionID: "same-session"))
        let message = try #require(model.takeFailedOutgoingMessage(sessionID: "same-session"))
        let history = try await model.conversation(sessionID: "same-session")
        #expect(history.turns.first?.id == message.id)
        #expect(history.turns.first?.delivery == .superseded)
        #expect(try await model.conversation(sessionID: "same-session") == history)
    }

    @Test func localPreviewCannotBypassWorkspaceOrNewAccountIsolation() async throws {
        let client = ControlledMessageClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let image = try ComposerAttachment(fileName: "photo.png", mimeType: "image/png", data: FixtureImage.png, isImage: true)
        try model.stageOutgoingMessage("Photo", composerText: "Photo", mentions: .init(),
                                       attachments: [image], runConfig: nil, sessionID: "same-session")
        guard case .image(let preview) = try #require(model.displayedTurns([], sessionID: "same-session").first).content[0] else {
            Issue.record("Missing local image"); return
        }
        await model.selectWorkspace("b")
        await #expect(throws: LodyClientError.notConnected) {
            try await model.loadSessionImage(preview, conversationSessionID: "same-session", variant: .original)
        }
        model.signOut()
        client.account = Account(email: "new-fixture@example.com", id: "new-fixture")
        await model.adoptExistingAccount()
        await #expect(throws: LodyClientError.notConnected) {
            try await model.loadSessionImage(preview, conversationSessionID: "same-session", variant: .original)
        }
    }

    @Test func signOutDiscardsAttachmentsAndIgnoresLateSendCompletion() async throws {
        let client = ControlledMessageClient()
        client.suspends = true
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        try model.stageOutgoingMessage("Old account", composerText: "Old account", mentions: .init(),
                                       attachments: [], runConfig: nil, sessionID: "same-session")
        var started = client.started.makeAsyncIterator()
        let send = Task { try await model.deliverOutgoingMessage(sessionID: "same-session") }
        _ = await started.next()
        model.signOut()
        client.finish()
        await #expect(throws: CancellationError.self) { try await send.value }
        #expect(model.outgoingMessage(sessionID: "same-session") == nil)
        #expect(model.cachedConversation(sessionID: "same-session") == nil)
    }
}

@MainActor
private final class ControlledMessageClient: LodyClient {
    var account: Account? = Account(email: "fixture@example.com", id: "fixture")
    let supportsTextSending = true
    var unconfirmed = false
    var rejection: LodyClientError?
    var suspends = false
    private var gate: CheckedContinuation<Void, Never>?
    private var pending: PendingTextSend?
    private var turns: [String: [ConversationTurn]] = [:]
    let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation

    init() { (started, signal) = AsyncStream.makeStream() }
    func finish() { gate?.resume(); gate = nil }
    func beginDeviceAuthorization() async throws -> DeviceAuthorization { throw LodyClientError.notConnected }
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws {}
    func restoreSession() async -> Account? { account }
    func signOut() { account = nil; pending = nil; turns = [:] }
    func workspaces() async throws -> [WorkspaceSummary] {
        [WorkspaceSummary(id: "a", name: "A", slug: "a"), WorkspaceSummary(id: "b", name: "B", slug: "b")]
    }
    func sessions(workspaceID: String) async throws -> [SessionSummary] { [] }
    func conversation(sessionID: String, workspaceID: String) async throws -> Conversation {
        Conversation(sessionID: sessionID, turns: turns[workspaceID] ?? [], permission: nil)
    }
    func pendingTextSend(sessionID: String, workspaceID: String) -> PendingTextSend? { pending }
    func send(_ text: String, attachments: [ComposerAttachment], runConfig: RunConfigChoice?,
              turnID: String, sessionID: String, workspaceID: String) async throws -> RunConfigChoice? {
        if suspends { await withCheckedContinuation { gate = $0; signal.yield(()) } }
        if !(turns[workspaceID] ?? []).contains(where: { $0.id == turnID }) {
            turns[workspaceID, default: []].append(ConversationTurn(id: turnID, author: .user, text: text))
        }
        if let rejection { throw rejection }
        if unconfirmed {
            pending = PendingTextSend(text: text, turnID: turnID, attachments: attachments)
            throw LodyClientError.deliveryUnconfirmed
        }
        pending = nil
        return runConfig
    }
    func cancelSession(sessionID: String, workspaceID: String) async throws {}
    func respond(_ decision: PermissionDecision, requestID: String, sessionID: String, workspaceID: String) async throws {}
    func newSessionOptions(templateSessionID: String, agentConfigID: String?, projectID: String?, isTab: Bool,
                           workspaceID: String) async throws -> NewSessionOptions { throw LodyClientError.notConnected }
}
