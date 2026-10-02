import Foundation
import Testing
@testable import Kurage

@MainActor
struct OutgoingMessageTests {
    @Test func consecutiveRejectionsSurviveRefreshRelaunchAndStaleConfirmation() async throws {
        let client = ControlledMessageClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        var first = ConversationTurn(id: "first", author: .user, text: "First")
        first.isDeliveryRejected = true
        let second = ConversationTurn(id: "second", author: .user, text: "Second")
        client.setHistory([first, second], workspaceID: "a")
        #expect(try await model.conversation(sessionID: "chat").turns.first?.delivery == .notDelivered)

        first.isDeliveryRejected = false
        first.isDeliveryConfirmed = true
        var rejectedSecond = second
        rejectedSecond.isDeliveryRejected = true
        client.setHistory([first, rejectedSecond], workspaceID: "a")
        let refreshed = try await model.conversation(sessionID: "chat")
        #expect(refreshed.turns.allSatisfy { $0.isDeliveryRejected && !$0.isDeliveryConfirmed && $0.delivery == .notDelivered })

        let cache = try #require(client.cachedSession)
        let relaunchedClient = ControlledMessageClient()
        relaunchedClient.cachedSession = try JSONDecoder().decode(SessionCache.self, from: JSONEncoder().encode(cache))
        var confirmedSecond = second
        confirmedSecond.isDeliveryConfirmed = true
        relaunchedClient.setHistory([first, confirmedSecond], workspaceID: "a")
        let relaunched = AppModel(client: relaunchedClient)
        await relaunched.adoptExistingAccount()
        let history = try await relaunched.conversation(sessionID: "chat")
        #expect(history.turns.allSatisfy { $0.isDeliveryRejected && !$0.isDeliveryConfirmed && $0.delivery == .notDelivered })
        let stale = relaunched.displayedTurns([first, confirmedSecond], sessionID: "chat")
        #expect(stale.allSatisfy { $0.isDeliveryRejected && !$0.isDeliveryConfirmed && $0.delivery == .notDelivered })
    }

    @Test func permanentRPCRejectionSurvivesEditingBeforeHistoryReportsIt() async throws {
        let client = ControlledMessageClient()
        client.rejection = .sendNotDelivered
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        try model.stageOutgoingMessage("Guide", composerText: "Guide", mentions: .init(), attachments: [],
                                       runConfig: nil, sessionID: "chat")
        let id = try #require(model.outgoingMessage(sessionID: "chat")?.id)
        await #expect(throws: LodyClientError.sendNotDelivered) {
            try await model.deliverOutgoingMessage(sessionID: "chat")
        }
        #expect(model.takeFailedOutgoingMessage(sessionID: "chat") != nil)
        client.confirmHistory(workspaceID: "a")
        let history = try await model.conversation(sessionID: "chat")
        #expect(history.turns.first?.id == id)
        #expect(history.turns.first?.isDeliveryRejected == true)
        #expect(history.turns.first?.isDeliveryConfirmed == false)
        #expect(history.turns.first?.delivery == .notDelivered)
    }

    @Test func rememberedRejectionsStayWithinTheirWorkspaceSessionAndAccount() async throws {
        let client = ControlledMessageClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        var rejected = ConversationTurn(id: "shared-id", author: .user, text: "Guide")
        rejected.isDeliveryRejected = true
        client.setHistory([rejected], workspaceID: "a")
        _ = try await model.conversation(sessionID: "chat")
        let cache = try #require(client.cachedSession)
        rejected.isDeliveryRejected = false
        rejected.isDeliveryConfirmed = true
        client.setHistory([rejected], workspaceID: "a")
        client.setHistory([rejected], workspaceID: "b")
        #expect(try await model.conversation(sessionID: "other-chat").turns.first?.isDeliveryRejected == false)
        await model.selectWorkspace("b")
        #expect(try await model.conversation(sessionID: "chat").turns.first?.isDeliveryRejected == false)
        await model.selectWorkspace("a")
        #expect(try await model.conversation(sessionID: "chat").turns.first?.isDeliveryRejected == true)

        let otherClient = ControlledMessageClient()
        otherClient.account = Account(email: "other@example.com", id: "other")
        otherClient.cachedSession = cache
        otherClient.setHistory([rejected], workspaceID: "a")
        let otherModel = AppModel(client: otherClient)
        await otherModel.adoptExistingAccount()
        #expect(try await otherModel.conversation(sessionID: "chat").turns.first?.isDeliveryRejected == false)

        model.signOut()
        #expect(client.cachedSession == nil)
        client.account = Account(email: "fixture@example.com", id: "fixture")
        client.setHistory([rejected], workspaceID: "a")
        await model.adoptExistingAccount()
        #expect(try await model.conversation(sessionID: "chat").turns.first?.isDeliveryRejected == false)
    }

    @Test func missingHistoryRejectionDisablesOldIDRetryAndEditingCreatesANewTurn() async throws {
        let client = ControlledMessageClient()
        client.unconfirmed = true
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        try model.stageOutgoingMessage("Guide", composerText: "Guide", mentions: .init(), attachments: [],
                                       runConfig: nil, sessionID: "chat")
        let id = try #require(model.outgoingMessage(sessionID: "chat")?.id)
        await #expect(throws: LodyClientError.deliveryUnconfirmed) {
            try await model.deliverOutgoingMessage(sessionID: "chat")
        }
        client.rejectHistory(workspaceID: "b")
        _ = try await model.conversation(sessionID: "chat")
        #expect(model.outgoingMessage(sessionID: "chat")?.delivery == .unconfirmed)
        client.rejectHistory(workspaceID: "a")
        let rejected = try await model.conversation(sessionID: "chat")
        #expect(model.outgoingMessage(sessionID: "chat")?.isDeliveryRejected == true)
        #expect(!model.retryOutgoingMessage(sessionID: "chat"))
        #expect(model.pendingTextSend(sessionID: "chat") == nil)
        #expect(rejected.turns.first?.delivery == .notDelivered)
        let decoded = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(rejected))
        #expect(decoded.turns.first?.isDeliveryRejected == true)
        let draft = try #require(model.takeFailedOutgoingMessage(sessionID: "chat"))
        #expect(draft.composerText == "Guide")
        client.unconfirmed = false
        try model.stageOutgoingMessage(draft.text, composerText: draft.composerText, mentions: draft.mentions,
            attachments: draft.attachments, runConfig: nil, sessionID: "chat")
        #expect(model.outgoingMessage(sessionID: "chat")?.id != id)
        try await model.deliverOutgoingMessage(sessionID: "chat")
        let history = try await model.conversation(sessionID: "chat")
        #expect(history.turns.count == 2)
        #expect(history.turns.first?.delivery == .notDelivered)
    }

    @Test(arguments: [false, true])
    func synchronizedRejectionWinsOverAnInFlightRPCResult(timesOut: Bool) async throws {
        let client = ControlledMessageClient()
        client.unconfirmed = timesOut
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        try model.stageOutgoingMessage("Guide", composerText: "Guide", mentions: .init(), attachments: [],
                                       runConfig: nil, sessionID: "chat")
        client.afterAuthored = {
            client.rejectHistory(workspaceID: "a")
            _ = try? await model.conversation(sessionID: "chat")
        }
        await #expect(throws: LodyClientError.sendNotDelivered) {
            try await model.deliverOutgoingMessage(sessionID: "chat")
        }
        #expect(model.outgoingMessage(sessionID: "chat")?.isDeliveryRejected == true)
        #expect(model.pendingTextSend(sessionID: "chat") == nil)
        #expect(!model.retryOutgoingMessage(sessionID: "chat"))
    }

    @Test func machineConfirmationBeforeRPCUnwindsWinsOverTheTimeout() async throws {
        let client = ControlledMessageClient()
        client.unconfirmed = true
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        try model.stageOutgoingMessage("Guide", composerText: "Guide", mentions: .init(), attachments: [],
                                       runConfig: nil, sessionID: "chat")
        client.afterAuthored = {
            client.confirmHistory(workspaceID: "a")
            _ = try? await model.conversation(sessionID: "chat")
            #expect(model.outgoingMessage(sessionID: "chat")?.delivery == .sending)
        }
        try await model.deliverOutgoingMessage(sessionID: "chat")
        #expect(model.outgoingMessage(sessionID: "chat") == nil)
        #expect(model.pendingTextSend(sessionID: "chat") == nil)
    }

    @Test func synchronizedConfirmationSurvivesNativePatchReconstruction() throws {
        let original = Conversation(sessionID: "chat", turns: [ConversationTurn(id: "guide", author: .user, text: "Guide")])
        let json = #"{"sessionID":"chat","order":["guide"],"changed":[{"id":"guide","author":"user","text":"Guide","isDeliveryConfirmed":true}],"activity":"running","syncState":"live"}"#
        let patch = try JSONDecoder().decode(ConversationPatch.self, from: Data(json.utf8))
        let confirmed = try patch.applying(to: original).conversation
        #expect(confirmed.turns.first?.isDeliveryConfirmed == true)
        let unchangedJSON = #"{"sessionID":"chat","order":["guide"],"changed":[],"activity":"running","syncState":"live"}"#
        let unchanged = try JSONDecoder().decode(ConversationPatch.self, from: Data(unchangedJSON.utf8))
        #expect(try unchanged.applying(to: confirmed).conversation == confirmed)
    }

    @Test func lateMachineConfirmationRetiresRetryWithoutResendingOrAcceptingHistoryAlone() async throws {
        let client = ControlledMessageClient()
        client.unconfirmed = true
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        try model.stageOutgoingMessage("Guide", composerText: "Guide", mentions: .init(), attachments: [],
                                       runConfig: nil, sessionID: "chat")
        let id = try #require(model.outgoingMessage(sessionID: "chat")?.id)
        await #expect(throws: LodyClientError.deliveryUnconfirmed) {
            try await model.deliverOutgoingMessage(sessionID: "chat")
        }
        let echo = try await model.conversation(sessionID: "chat")
        #expect(echo.turns.first?.id == id)
        #expect(model.outgoingMessage(sessionID: "chat")?.delivery == .unconfirmed)
        client.confirmHistory(workspaceID: "b")
        _ = try await model.conversation(sessionID: "chat")
        #expect(model.outgoingMessage(sessionID: "chat")?.delivery == .unconfirmed)
        client.confirmHistory(workspaceID: "a")
        let received = try await model.conversation(sessionID: "chat")
        #expect(received.turns.map(\.id) == [id])
        #expect(model.outgoingMessage(sessionID: "chat") == nil)
        #expect(model.pendingTextSend(sessionID: "chat") == nil)
        #expect(model.displayedTurns(received.turns, sessionID: "chat").first?.delivery == nil)
        let decoded = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(received))
        #expect(decoded.turns.first?.isDeliveryConfirmed == true)
        try model.stageOutgoingMessage("Next", composerText: "Next", mentions: .init(), attachments: [],
                                       runConfig: nil, sessionID: "chat")
        #expect(model.outgoingMessage(sessionID: "chat")?.id != id)
    }

    @Test func confirmedPreviewsEvictBytesAcrossConversationsAndCannotReappearFromOldSnapshots() async throws {
        let model = AppModel(client: FixtureLodyClient(startsSignedIn: true))
        await model.adoptExistingAccount()
        var received: [Conversation] = []
        for sessionID in ["session-long", "session-pr", "session-tests"] {
            let image = try ComposerAttachment(fileName: "photo.png", mimeType: "image/png", data: FixtureImage.png,
                isImage: true, thumbnailData: Data(repeating: 1, count: 4 * 1024 * 1024))
            try model.stageOutgoingMessage("Photo", composerText: "Photo", mentions: .init(), attachments: [image],
                                           runConfig: nil, sessionID: sessionID)
            try await model.deliverOutgoingMessage(sessionID: sessionID)
            received.append(try #require(model.cachedConversation(sessionID: sessionID)))
        }
        func previews(_ turns: [ConversationTurn]) -> [Data] {
            turns.flatMap(\.parts).compactMap {
                guard case .image(let image) = $0 else { return nil }
                return image.localPreviewData
            }
        }
        #expect(previews(received[0].turns).count == 1)
        #expect(previews(try #require(model.cachedConversation(sessionID: "session-long")).turns).isEmpty)
        #expect(previews(model.displayedTurns(received[0].turns, sessionID: "session-long")).isEmpty)
        #expect(previews(try await model.conversation(sessionID: "session-long").turns).isEmpty)
        #expect(previews(try #require(model.cachedConversation(sessionID: "session-pr")).turns).count == 1)
        model.signOut()
        #expect(model.cachedConversation(sessionID: "session-pr") == nil)
    }

    @Test func previewCacheEnforcesCountBytesAndWorkspaceIsolation() {
        var cache = SessionImagePreviewCache(maxCount: 2, maxBytes: 6)
        func turn(_ id: String, count: Int = 2) -> ConversationTurn {
            ConversationTurn(id: id, author: .user, text: "", parts: [.image(ConversationImage(
                imageID: id, mimeType: "image/png", localPreviewData: Data(repeating: 1, count: count)))])
        }
        let turns = [turn("a"), turn("b"), turn("c")]
        let conversation = Conversation(sessionID: "s", turns: turns)
        func data(_ id: String, workspaceID: String = "w") -> Data? {
            let result = cache.applying(to: conversation, workspaceID: workspaceID)
            guard case .image(let image) = result.turns.first(where: { $0.id == id })?.parts.first else { return nil }
            return image.localPreviewData
        }
        for turn in turns { cache.store(turn, sessionID: "s", workspaceID: "w") }
        #expect(data("a") == nil)
        #expect(data("b")?.count == 2)
        #expect(data("b", workspaceID: "other") == nil)
        cache.store(turn("b", count: 5), sessionID: "s", workspaceID: "w")
        #expect(data("c") == nil)
        #expect(data("b")?.count == 5)
        cache.store(turn("b", count: 7), sessionID: "s", workspaceID: "w")
        #expect(data("b") == nil)
        cache.store(turn("a"), sessionID: "s", workspaceID: "w")
        cache.retainWorkspaces(["other"])
        #expect(data("a") == nil)
        cache.store(turn("c"), sessionID: "s", workspaceID: "w")
        cache.removeSessions(["s"], workspaceID: "w")
        #expect(data("c") == nil)
    }

    @Test(arguments: [false, true])
    func firstTurnIsVisibleBeforeCreationAndKeepsItsIdentityThroughTheEcho(isTab: Bool) async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let template = try #require(model.sessionSummary("session-long"))
        let options = try await model.newSessionOptions(templateSessionID: template.id, isTab: isTab)
        var config = try #require(options.runConfig)
        config.selectModel("gpt-5.4-mini")
        config.selectReasoning("low")
        let image = try ComposerAttachment(fileName: "photo.png", mimeType: "image/png", data: FixtureImage.png, isImage: true)
        let id = try model.stageSessionStart("  First turn  ", composerText: "  First turn  ", mentions: .init(),
            attachments: [image], agentConfigID: options.agentConfigID, selections: config.selections,
            projectID: try #require(template.projectID), projectName: template.projectName ?? "Project",
            templateSessionID: template.id, parentSessionID: isTab ? template.id : nil)
        let message = try #require(model.outgoingMessage(sessionID: id))
        #expect(model.displayedTurns([], sessionID: id).map(\.id) == [message.id])
        #expect(message.delivery == .sending)
        #expect(model.isSessionStartPending(sessionID: id))
        #expect(model.cachedConversation(sessionID: id) == nil)
        #expect(!model.sessions.contains { $0.id == id })
        if isTab {
            model.setActiveSessionTab(id, rootID: template.id)
            // A root projection from before the write must not erase the new tab.
            try await model.observeConversation(sessionID: template.id) { _ in }
            #expect(model.activeSessionTab(rootID: template.id) == id)
            #expect(model.sessionTabs(rootID: template.id).last?.id == id)
        }
        try await model.deliverOutgoingMessage(sessionID: id)
        #expect(!model.isSessionStartPending(sessionID: id))
        #expect(model.outgoingMessage(sessionID: id)?.delivery == .sent)
        #expect(model.displayedTurns([], sessionID: id).map(\.id) == [message.id])
        try await model.observeConversation(sessionID: id, rootSessionID: isTab ? template.id : id) { update in
            #expect(update.runConfig?.model?.value == "gpt-5.4-mini")
            #expect(update.runConfig?.reasoning?.value == "low")
        }
        let received = try #require(model.cachedConversation(sessionID: id))
        #expect(model.outgoingMessage(sessionID: id) == nil)
        #expect(received.turns.map(\.id) == [message.id])
        guard case .image(let preview) = received.turns[0].content.first(where: {
            if case .image = $0 { return true }; return false
        }) else { Issue.record("Missing first-turn image"); return }
        #expect(preview.localPreviewData == image.data)
    }

    @Test(arguments: [false, true])
    func unconfirmedFirstTurnRetriesTheOriginalSessionAndAttachments(isTab: Bool) async throws {
        let client = FixtureLodyClient(startsSignedIn: true, failStartAndArchiveProjectOnce: !isTab, failTabStartOnce: isTab)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let template = try #require(model.sessionSummary("session-long"))
        let file = try ComposerAttachment(fileName: "notes.txt", mimeType: "text/plain", data: Data("notes".utf8), isImage: false)
        let id = try model.stageSessionStart("Recover first turn", composerText: "Recover first turn", mentions: .init(),
            attachments: [file], agentConfigID: nil, selections: [], projectID: try #require(template.projectID),
            projectName: "Project", templateSessionID: template.id, parentSessionID: isTab ? template.id : nil)
        let turnID = try #require(model.outgoingMessage(sessionID: id)?.id)
        await #expect(throws: LodyClientError.deliveryUnconfirmed) { try await model.deliverOutgoingMessage(sessionID: id) }
        #expect(model.outgoingMessage(sessionID: id)?.delivery == .unconfirmed)
        #expect(model.takeFailedOutgoingMessage(sessionID: id) == nil)
        if !isTab {
            await model.refreshSessions()
            #expect(model.sessionSummary(template.id) == nil)
            let pending = try #require(model.pendingSessionStarts.first)
            #expect(try model.restoreSessionStart(pending, projectName: "Project") == id)
        }
        #expect(model.retryOutgoingMessage(sessionID: id))
        try await model.deliverOutgoingMessage(sessionID: id)
        let received = try await model.conversation(sessionID: id)
        #expect(received.turns.map(\.id) == [turnID])
        #expect(received.turns.first?.content.contains { if case .file = $0 { return true }; return false } == true)
        #expect(model.pendingSessionStarts.isEmpty)
        #expect(model.pendingSessionTab(rootID: template.id) == nil)
    }

    @Test func rejectedFirstTurnCanRestoreTheDraftWithoutCreatingASession() async throws {
        let client = FixtureLodyClient(startsSignedIn: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let id = try model.stageSessionStart("First", composerText: "First", mentions: .init(), attachments: [],
            agentConfigID: nil, selections: [.init(configOptionID: "invalid", value: "invalid")],
            projectID: "local:machine-1:kurage", projectName: "Kurage", templateSessionID: "session-long", parentSessionID: "session-long")
        await #expect(throws: LodyClientError.sessionCreationRejected) { try await model.deliverOutgoingMessage(sessionID: id) }
        #expect(model.takeFailedOutgoingMessage(sessionID: id)?.composerText == "First")
        #expect(model.sessionSummary(id) == nil)
        #expect(model.sessionTabs(rootID: "session-long").allSatisfy { $0.id != id })
        #expect(model.pendingSessionTab(rootID: "session-long") == nil)
    }

    @Test func editingAFailedFollowUpKeepsAConfirmedTabWhileMetadataCatchesUp() async throws {
        let client = FixtureLodyClient(startsSignedIn: true, rejectSendOnce: true)
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let id = try model.stageSessionStart("First", composerText: "First", mentions: .init(), attachments: [],
            agentConfigID: nil, selections: [], projectID: "local:machine-1:kurage", projectName: "Kurage",
            templateSessionID: "session-long", parentSessionID: "session-long")
        try await model.deliverOutgoingMessage(sessionID: id)
        _ = try await model.conversation(sessionID: id)
        #expect(model.outgoingMessage(sessionID: id) == nil)
        try model.stageOutgoingMessage("Follow-up", composerText: "Follow-up", mentions: .init(),
            attachments: [], runConfig: nil, sessionID: id)
        await #expect(throws: LodyClientError.sessionBusy) { try await model.deliverOutgoingMessage(sessionID: id) }
        #expect(model.takeFailedOutgoingMessage(sessionID: id)?.text == "Follow-up")
        #expect(model.sessionSummary(id)?.parentSessionID == "session-long")
        #expect(model.sessionTabs(rootID: "session-long").contains { $0.id == id })
    }

    @Test(arguments: [false, true])
    func lateFirstTurnCompletionPreservesWorkspaceAndAccountIsolation(signsOut: Bool) async throws {
        let client = ControlledSessionStartClient()
        let model = AppModel(client: client)
        await model.adoptExistingAccount()
        let id = try model.stageSessionStart("Original workspace", composerText: "Original workspace", mentions: .init(),
            attachments: [], agentConfigID: nil, selections: [], projectID: "local:machine:project",
            projectName: "Project", templateSessionID: "root")
        var started = client.started.makeAsyncIterator()
        let send = Task { try await model.deliverOutgoingMessage(sessionID: id, workspaceID: "a") }
        _ = await started.next()
        if signsOut { model.signOut() } else { await model.selectWorkspace("b") }
        #expect(model.outgoingMessage(sessionID: id) == nil)
        #expect(model.sessionSummary(id) == nil)
        client.finish()
        if signsOut {
            await #expect(throws: CancellationError.self) { try await send.value }
            #expect(model.sessionSummary(id) == nil)
        } else {
            try await send.value
            #expect(!model.sessions.contains { $0.id == id })
            await model.selectWorkspace("a")
            #expect(model.outgoingMessage(sessionID: id)?.delivery == .sent)
            #expect(model.sessionSummary(id)?.title == "Original workspace")
            let received = try await model.conversation(sessionID: id)
            #expect(received.turns.count == 1)
            #expect(model.outgoingMessage(sessionID: id) == nil)
        }
    }

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
private final class ControlledSessionStartClient: LodyClient {
    var account: Account? = Account(email: "fixture@example.com", id: "fixture")
    let supportsSessionCreation = true
    private var gate: CheckedContinuation<Void, Never>?
    private var records: [String: [(SessionSummary, Conversation)]] = [:]
    let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation

    init() { (started, signal) = AsyncStream.makeStream() }
    func finish() { gate?.resume(); gate = nil }
    func beginDeviceAuthorization() async throws -> DeviceAuthorization { throw LodyClientError.notConnected }
    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws {}
    func restoreSession() async -> Account? { account }
    func signOut() { account = nil }
    func workspaces() async throws -> [WorkspaceSummary] {
        [.init(id: "a", name: "A", slug: "a"), .init(id: "b", name: "B", slug: "b")]
    }
    func sessions(workspaceID: String) async throws -> [SessionSummary] {
        [SessionSummary(id: "root", title: "Root", agentName: "Agent", activity: .idle, preview: "",
                        projectID: "local:machine:project", projectName: "Project")] + (records[workspaceID] ?? []).map { $0.0 }
    }
    func startSession(_ text: String, attachments: [ComposerAttachment], agentConfigID: String?, selections: [RunConfigChoice],
                      projectID: String, templateSessionID: String, sessionID: String, turnID: String, workspaceID: String) async throws -> String {
        await withCheckedContinuation { gate = $0; signal.yield(()) }
        records[workspaceID, default: []].append((
            SessionSummary(id: sessionID, title: text, agentName: "Agent", activity: .idle, preview: text, projectID: projectID),
            Conversation(sessionID: sessionID, turns: [ConversationTurn(id: turnID, author: .user, text: text)])))
        return sessionID
    }
    func conversation(sessionID: String, workspaceID: String) async throws -> Conversation {
        guard let record = records[workspaceID]?.first(where: { $0.0.id == sessionID }) else { throw LodyClientError.sessionMissing }
        return record.1
    }
    func send(_ text: String, attachments: [ComposerAttachment], runConfig: RunConfigChoice?,
              turnID: String, sessionID: String, workspaceID: String) async throws -> RunConfigChoice? {
        throw LodyClientError.notConnected
    }
    func cancelSession(sessionID: String, workspaceID: String) async throws {}
    func respond(_ decision: PermissionDecision, requestID: String, sessionID: String, workspaceID: String) async throws {}
}

@MainActor
private final class ControlledMessageClient: LodyClient {
    var account: Account? = Account(email: "fixture@example.com", id: "fixture")
    var cachedSession: SessionCache?
    let supportsTextSending = true
    var unconfirmed = false
    var rejection: LodyClientError?
    var suspends = false
    var afterAuthored: (() async -> Void)?
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
    func signOut() { account = nil; pending = nil; turns = [:]; cachedSession = nil }
    func saveSessionCache(_ cache: SessionCache) {
        if cache.account == account { cachedSession = cache }
    }
    func setHistory(_ history: [ConversationTurn], workspaceID: String) { turns[workspaceID] = history }
    func workspaces() async throws -> [WorkspaceSummary] {
        [WorkspaceSummary(id: "a", name: "A", slug: "a"), WorkspaceSummary(id: "b", name: "B", slug: "b")]
    }
    func sessions(workspaceID: String) async throws -> [SessionSummary] { [] }
    func conversation(sessionID: String, workspaceID: String) async throws -> Conversation {
        Conversation(sessionID: sessionID, turns: turns[workspaceID] ?? [], permission: nil)
    }
    func pendingTextSend(sessionID: String, workspaceID: String) -> PendingTextSend? { pending }
    func confirmHistory(workspaceID: String) {
        for index in (turns[workspaceID] ?? []).indices {
            turns[workspaceID]?[index].isDeliveryConfirmed = true
        }
    }
    func rejectHistory(workspaceID: String) {
        for index in (turns[workspaceID] ?? []).indices {
            turns[workspaceID]?[index].isDeliveryRejected = true
        }
    }
    func finishTextSend(turnID: String, sessionID: String, workspaceID: String) {
        if pending?.turnID == turnID { pending = nil }
    }
    func send(_ text: String, attachments: [ComposerAttachment], runConfig: RunConfigChoice?,
              turnID: String, sessionID: String, workspaceID: String) async throws -> RunConfigChoice? {
        if suspends { await withCheckedContinuation { gate = $0; signal.yield(()) } }
        if !(turns[workspaceID] ?? []).contains(where: { $0.id == turnID }) {
            turns[workspaceID, default: []].append(ConversationTurn(id: turnID, author: .user, text: text))
        }
        await afterAuthored?()
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
