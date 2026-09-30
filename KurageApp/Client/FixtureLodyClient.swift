import Foundation

/// In-memory stand-in so the shell can be tapped before a real Lody connection exists.
@MainActor
final class FixtureLodyClient: LodyClient {
    private(set) var account: Account?
    var requiresExternalAuthorization: Bool { authorizationDelay != nil }
    let supportsConversations = true
    let supportsTextSending = true
    let supportsTextSendingWhileRunning = true
    let supportsSessionCancellation = true
    let supportsSessionArchiving = true
    let supportsPermissionResponses = true
    let supportsSessionCreation = true

    private var records: [SessionRecord]
    private var archivedSessionIDs: Set<SessionSummary.ID>
    private var archivedActivity: [SessionSummary.ID: Date] = [
        "archived-newer": Date(timeIntervalSince1970: 1_700_000_000),
        "archived-older": Date(timeIntervalSince1970: 1_600_000_000),
    ]
    private var nextTurnNumber = 0
    private var failStartAndArchiveProjectOnce: Bool
    private var pendingStarts: [String: (pending: PendingSessionStart, record: SessionRecord)] = [:]
    private var failingConversationIDsOnce: Set<String>
    private let conversationDelay: Duration?
    private let sendDelay: Duration?
    private let startDelay: Duration?
    private var failTabStartOnce: Bool
    private let skillRefreshDelay: Duration?
    private let mentionDelay: Duration?
    private var failSkillRefreshOnce: Bool
    private var initialSkillSource: String?
    private var failSendOnce: Bool
    private var rejectSendOnce: Bool
    private let authorizationDelay: Duration?
    private var pendingSends: [String: (message: PendingTextSend, runConfig: RunConfigChoice?)] = [:]

    init(
        startsSignedIn: Bool = false,
        records: [SessionRecord] = SessionRecord.samples,
        archivedIDs: Set<SessionSummary.ID>? = nil,
        failingConversationIDsOnce: Set<String> = [],
        conversationDelay: Duration? = nil,
        failStartAndArchiveProjectOnce: Bool = false,
        sendDelay: Duration? = nil,
        startDelay: Duration? = nil,
        failSendOnce: Bool = false,
        rejectSendOnce: Bool = false,
        failTabStartOnce: Bool = false,
        skillRefreshDelay: Duration? = nil,
        mentionDelay: Duration? = nil,
        failSkillRefreshOnce: Bool = false,
        authorizationDelay: Duration? = nil
    ) {
        self.authorizationDelay = authorizationDelay
        self.records = records
        self.failStartAndArchiveProjectOnce = failStartAndArchiveProjectOnce
        self.failingConversationIDsOnce = failingConversationIDsOnce
        self.conversationDelay = conversationDelay
        self.sendDelay = sendDelay
        self.startDelay = startDelay
        self.failSendOnce = failSendOnce
        self.rejectSendOnce = rejectSendOnce
        self.failTabStartOnce = failTabStartOnce
        self.skillRefreshDelay = skillRefreshDelay
        self.mentionDelay = mentionDelay
        self.failSkillRefreshOnce = failSkillRefreshOnce
        if let archivedIDs {
            self.archivedSessionIDs = archivedIDs
        } else {
            let seeded: Set<SessionSummary.ID> = ["archived-newer", "archived-older"]
            self.archivedSessionIDs = Set(records.map(\.summary.id)).intersection(seeded)
        }
        if startsSignedIn {
            account = Account(email: "demo@kurage.app")
        }
    }

    func beginDeviceAuthorization() async throws -> DeviceAuthorization {
        DeviceAuthorization(
            userCode: "ABCD-EFGH",
            verificationURL: URL(string: "https://lody.ai/device")!,
            deviceCode: "device-1",
            expiresIn: 600,
            interval: 0.01
        )
    }

    func finishDeviceAuthorization(_ authorization: DeviceAuthorization) async throws {
        guard authorization.deviceCode == "device-1" else { throw LodyClientError.signInFailed }
        if let authorizationDelay { try await Task.sleep(for: authorizationDelay) }
        try Task.checkCancellation()
        account = Account(email: "demo@kurage.app")
    }

    func restoreSession() async -> Account? {
        account
    }

    func signOut() {
        addedProjects = [:]
        attachmentImages.removeAll()
        pendingStarts = [:]
        pendingSends = [:]
        account = nil
    }

    func workspaces() async throws -> [WorkspaceSummary] {
        try requireAccount()
        return [WorkspaceSummary(id: "ws-demo", name: "Demo", slug: "demo")]
    }

    func sessions(workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary] {
        try requireAccount()
        try requireWorkspace(workspaceID)
        return records
            .filter { !archivedSessionIDs.contains($0.summary.id) && $0.summary.parentSessionID == nil }
            .map(\.summary)
    }

    func mentionSessions(projectID: String, excluding sessionID: String?, workspaceID: WorkspaceSummary.ID) async throws -> [MentionSession] {
        if let mentionDelay { try await Task.sleep(for: mentionDelay) }
        try requireAccount()
        try requireWorkspace(workspaceID)
        return records.filter { $0.summary.projectID == projectID && $0.summary.id != sessionID &&
            !archivedSessionIDs.contains($0.summary.id) }
            .map { MentionSession(id: $0.summary.id, title: $0.summary.title,
                                  projectID: $0.summary.projectID,
                                  lastActivityAt: $0.summary.lastActivityAt ?? $0.summary.lastMessageAt ?? 0) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    func mentionSkills(templateSessionID: String, agentConfigID: String?, projectID: String? = nil, workspaceID: WorkspaceSummary.ID) async throws -> [MentionSkill] {
        if let mentionDelay { try await Task.sleep(for: mentionDelay) }
        try requireAccount()
        try requireWorkspace(workspaceID)
        let template = try record(templateSessionID)
        // A nil provider means the template's default, including a prefetch
        // that begins before the new-session options have resolved.
        let source = "\(projectID ?? template.summary.projectID ?? ""): \(agentConfigID ?? template.summary.agentName)"
        if initialSkillSource == nil { initialSkillSource = source }
        if source != initialSkillSource {
            if let skillRefreshDelay { try await Task.sleep(for: skillRefreshDelay) }
            if failSkillRefreshOnce {
                failSkillRefreshOnce = false
                throw LodyClientError.unreachable
            }
        }
        return [
            MentionSkill(token: "review-and-simplify-changes", name: "Review and Simplify Changes",
                         description: "Review code quality and simplify changes",
                         path: ".agents/skills/review-and-simplify-changes/SKILL.md"),
            MentionSkill(token: "swiftui-specialist", name: "SwiftUI Specialist",
                         description: "Apple SwiftUI best practices",
                         path: ".agents/skills/swiftui-specialist/SKILL.md"),
        ] + (1...12).map { number in
            MentionSkill(token: "sample-skill-\(number)", name: "Sample Skill \(number)",
                         description: "A project skill with a longer description for scrolling the suggestions list",
                         path: ".agents/skills/sample-skill-\(number)/SKILL.md")
        }
    }

    func conversation(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> Conversation {
        try requireAccount()
        try requireWorkspace(workspaceID)
        if let conversationDelay { try await Task.sleep(for: conversationDelay) }
        if failingConversationIDsOnce.remove(sessionID) != nil { throw LodyClientError.unreachable }
        let record = try record(sessionID)
        return Conversation(
            sessionID: record.summary.id,
            turns: record.turns,
            permission: record.permission,
            fileChanges: record.fileChanges,
            subtasks: record.subtasks,
            questions: record.questions
        )
    }

    func observeConversation(sessionID: String, rootSessionID: String?, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error> {
        try requireAccount()
        try requireWorkspace(workspaceID)
        if let rootSessionID, rootSessionID != sessionID,
           !archivedSessionIDs.contains(rootSessionID), records.contains(where: { $0.summary.id == rootSessionID }),
           !records.contains(where: { $0.summary.id == sessionID && $0.summary.isTabClosed != true && !archivedSessionIDs.contains(sessionID) }) {
            let update = ConversationUpdate(conversation: Conversation(sessionID: sessionID, turns: [], permission: nil),
                activity: .idle, syncState: .connecting, sessionTabs: fixtureTabs(sessionID: rootSessionID))
            return AsyncThrowingStream { continuation in
                continuation.yield(update)
                continuation.finish()
            }
        }
        return try await observeConversation(sessionID: sessionID, workspaceID: workspaceID)
    }

    func observeConversation(sessionID: String, workspaceID: String) async throws -> AsyncThrowingStream<ConversationUpdate, Error> {
        let snapshot = try await conversation(sessionID: sessionID, workspaceID: workspaceID)
        let update = ConversationUpdate(conversation: snapshot, activity: try record(sessionID).summary.activity, syncState: .live,
                                        runConfig: try record(sessionID).runConfig,
                                        contextWindowUsage: try record(sessionID).contextWindowUsage,
                                        lastMessageAt: try record(sessionID).summary.lastMessageAt,
                                        sessionTabs: fixtureTabs(sessionID: sessionID))
        return AsyncThrowingStream { continuation in
            continuation.yield(update)
            continuation.finish()
        }
    }

    var supportsSessionTabs: Bool { true }

    /// Applies requested choices the way the service does: model and reasoning
    /// only, and only when they match what the options offered.
    private func appliedRunConfig(_ options: NewSessionOptions, selections: [RunConfigChoice],
                                  mismatch: LodyClientError = .sessionCreationRejected) throws -> NewSessionRunConfig {
        var config = options.runConfig ?? NewSessionRunConfig()
        for choice in selections {
            if choice.configOptionID == config.model?.configOptionID { config.selectModel(choice.value) }
            else { config.selectReasoning(choice.value) }
        }
        guard selections.isEmpty || config.selections == selections else { throw mismatch }
        return config
    }

    private func fixtureTabs(sessionID: String) -> [SessionSummary] {
        let rootID = records.first { $0.summary.id == sessionID }?.summary.parentSessionID ?? sessionID
        // Creation order, like the live projection's `createdAt` sort. Tab ids are
        // random, so sorting by them would shuffle the bar between runs.
        let tabs = records.filter { ($0.summary.id == rootID || $0.summary.parentSessionID == rootID) &&
            !archivedSessionIDs.contains($0.summary.id) }
            .map(\.summary)
        return tabs.filter { $0.id == rootID } + tabs.filter { $0.id != rootID }
    }

    func startSessionTab(_ request: SessionTabStart, parentSessionID: String, workspaceID: String) async throws {
        if let startDelay { try await Task.sleep(for: startDelay) }
        try Task.checkCancellation()
        try requireAccount()
        try requireWorkspace(workspaceID)
        let parent = try record(parentSessionID)
        guard parent.summary.parentSessionID == nil, !archivedSessionIDs.contains(parentSessionID) else {
            throw LodyClientError.sessionMissing
        }
        if let existing = records.first(where: { $0.summary.id == request.sessionID }) {
            guard existing.summary.parentSessionID == parentSessionID,
                  existing.turns.first?.id == request.turnID, existing.turns.first?.text == request.text else {
                throw LodyClientError.sessionCreationRejected
            }
            return
        }
        let options = try await newSessionOptions(templateSessionID: parentSessionID,
                                                  agentConfigID: request.agentConfigID,
                                                  isTab: true, workspaceID: workspaceID)
        let config = try appliedRunConfig(options, selections: request.selections)
        let summary = SessionSummary(id: request.sessionID,
                                 title: String((request.text.isEmpty ? request.attachments.first?.fileName ?? "New session" : request.text).prefix(50)),
                                 agentName: options.agentConfigID, activity: .idle, preview: request.text,
                                 projectID: parent.summary.projectID, projectName: parent.summary.projectName,
                                 machineName: parent.summary.machineName, parentSessionID: parentSessionID)
        records.append(SessionRecord(summary: summary,
            turns: [ConversationTurn(id: request.turnID, author: .user, text: request.text,
                                     parts: attachmentParts(request.attachments, text: request.text))],
            runConfig: SessionRunConfig(model: config.selectedModel.map { .init(value: $0.value, label: $0.label) },
                                        reasoning: config.selectedReasoning, editable: nil)))
        if failTabStartOnce {
            failTabStartOnce = false
            throw LodyClientError.deliveryUnconfirmed
        }
    }

    func pendingTextSend(sessionID: String, workspaceID: String) -> PendingTextSend? {
        guard account != nil, workspaceID == "ws-demo" else { return nil }
        return pendingSends[sessionID]?.message
    }

    @discardableResult
    func send(
        _ text: String, attachments: [ComposerAttachment] = [],
        runConfig: RunConfigChoice?,
        turnID: ConversationTurn.ID,
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> RunConfigChoice? {
        try requireAccount()
        try requireWorkspace(workspaceID)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { throw LodyClientError.emptyMessage }
        let pending = pendingSends[sessionID]
        if let pending, (pending.message.text != trimmed || pending.message.attachments != attachments) {
            throw LodyClientError.previousSendPending(pending.message.text)
        }
        let effectiveTurnID = pending?.message.turnID ?? turnID
        let effectiveRunConfig = if let pending { pending.runConfig } else { runConfig }
        if let sendDelay { try await Task.sleep(for: sendDelay) }
        try requireAccount()
        try requireWorkspace(workspaceID)
        if rejectSendOnce {
            rejectSendOnce = false
            throw LodyClientError.sessionBusy
        }
        if failSendOnce {
            failSendOnce = false
            pendingSends[sessionID] = (PendingTextSend(text: trimmed, turnID: effectiveTurnID, attachments: attachments), effectiveRunConfig)
            throw LodyClientError.deliveryUnconfirmed
        }

        try update(sessionID) { record in
            if let runConfig = effectiveRunConfig {
                guard let current = record.runConfig,
                      current.choosing(runConfig.value) == runConfig else { throw LodyClientError.notConnected }
                record.runConfig = current.applying(runConfig)
            }
            let turn = ConversationTurn(id: effectiveTurnID, author: .user, text: trimmed, parts: attachmentParts(attachments, text: trimmed))
            record.turns.append(turn)
            record.summary.preview = trimmed
        }
        if let index = records.firstIndex(where: { $0.summary.id == sessionID }) {
            records.insert(records.remove(at: index), at: 0)
        }
        pendingSends.removeValue(forKey: sessionID)
        return effectiveRunConfig
    }

    func newSessionOptions(
        templateSessionID: SessionSummary.ID,
        agentConfigID: String?,
        projectID: String? = nil,
        isTab: Bool = false,
        refresh: Bool = false,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> NewSessionOptions {
        try requireAccount()
        try requireWorkspace(workspaceID)
        let template = try record(templateSessionID)
        if isTab {
            // A tab starts from a root session of this workspace.
            guard template.summary.parentSessionID == nil, !archivedSessionIDs.contains(templateSessionID) else {
                throw LodyClientError.sessionMissing
            }
        } else {
            guard !archivedSessionIDs.contains(templateSessionID),
                  template.summary.projectID?.hasPrefix("local:") == true else { throw LodyClientError.sessionMissing }
        }
        let providers = [
            SessionRunConfig.Value(value: "claude", label: "Claude Code"),
            SessionRunConfig.Value(value: "codex", label: "Codex"),
        ]
        let chosen = agentConfigID ?? template.summary.agentName
        guard providers.contains(where: { $0.value == chosen }) else { throw LodyClientError.notConnected }
        return NewSessionOptions(machineName: isTab ? template.summary.machineName ?? "Machine" : "spike@mac",
                                 agentConfigID: chosen, providers: providers,
                                 runConfig: chosen == "codex" ? .fixture : .fixtureModelOnly)
    }

    private var addedProjects: [String: SessionProject] = [:]

    func sessionProjects(templateSessionID: String, action: SessionProjectAction, path: String?, cursor: String?,
                         workspaceID: String) async throws -> SessionProjectResult {
        try requireAccount()
        try requireWorkspace(workspaceID)
        _ = try record(templateSessionID)
        switch action {
        case .catalog:
            var seen = Set<String>()
            let projects = records.compactMap { record -> SessionProject? in
                guard !archivedSessionIDs.contains(record.summary.id), record.summary.parentSessionID == nil,
                      let id = record.summary.projectID, id.hasPrefix("local:"), seen.insert(id).inserted else { return nil }
                return SessionProject(id: id, name: record.summary.projectName ?? "Project", rootPath: "",
                                      templateSessionID: record.summary.id)
            }
            return SessionProjectResult(projects: projects + Array(addedProjects.values))
        case .browse:
            let current = path ?? "/Users/demo"
            let entries: [MachineDirectory.Entry] = current == "/Users/demo"
                ? [.init(name: "projects", absolutePath: "/Users/demo/projects"), .init(name: "Documents", absolutePath: "/Users/demo/Documents")]
                : current == "/Users/demo/projects" ? [.init(name: "Current folder", absolutePath: current),
                   .init(name: "New App", absolutePath: "/Users/demo/projects/New App"),
                   .init(name: "New App alias", absolutePath: "/Users/demo/projects/New App")] : []
            return SessionProjectResult(directory: MachineDirectory(path: current,
                parentPath: current == "/" ? nil : (current as NSString).deletingLastPathComponent,
                entries: entries, truncated: false, nextCursor: nil))
        case .select:
            guard let path, path.hasPrefix("/") else { throw LodyClientError.notConnected }
            let project = SessionProject(id: "local:machine-1:folder-\(path)", name: (path as NSString).lastPathComponent,
                                         rootPath: path, templateSessionID: templateSessionID)
            addedProjects[project.id] = project
            return SessionProjectResult(project: project)
        }
    }

    func startSession(
        _ text: String, attachments: [ComposerAttachment] = [],
        agentConfigID: String?,
        selections: [RunConfigChoice],
        projectID: String,
        templateSessionID: SessionSummary.ID,
        sessionID: SessionSummary.ID,
        turnID: ConversationTurn.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws -> SessionSummary.ID {
        if let startDelay { try await Task.sleep(for: startDelay) }
        try Task.checkCancellation()
        try requireAccount()
        try requireWorkspace(workspaceID)
        if let pending = pendingSessionStarts(workspaceID: workspaceID).first(where: { $0.projectID == projectID }) {
            guard pending.text == text.trimmingCharacters(in: .whitespacesAndNewlines), pending.attachments == attachments else {
                throw LodyClientError.previousSendPending(pending.text)
            }
            return try await retrySessionStart(sessionID: pending.id, workspaceID: workspaceID)
        }
        let options = try await newSessionOptions(
            templateSessionID: templateSessionID, agentConfigID: agentConfigID, workspaceID: workspaceID
        )
        let template = try record(templateSessionID)
        guard template.summary.projectID == projectID || addedProjects[projectID]?.templateSessionID == templateSessionID else { throw LodyClientError.sessionMissing }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { throw LodyClientError.emptyMessage }
        let runConfig = try appliedRunConfig(options, selections: selections, mismatch: LodyClientError.notConnected)
        let id = sessionID
        let created = SessionRecord(
            summary: SessionSummary(
                id: id, title: String((trimmed.isEmpty ? attachments.first?.fileName ?? "New session" : trimmed).prefix(50)), agentName: options.agentConfigID,
                activity: .idle, preview: trimmed,
                projectID: projectID, projectName: addedProjects[projectID]?.name ?? template.summary.projectName,
                machineName: template.summary.machineName
            ),
            turns: [ConversationTurn(id: turnID, author: .user, text: trimmed, parts: attachmentParts(attachments, text: trimmed))],
            permission: nil,
            runConfig: SessionRunConfig(
                model: runConfig.selectedModel.map { SessionRunConfig.Value(value: $0.value, label: $0.label) },
                reasoning: runConfig.selectedReasoning,
                editable: nil
            )
        )
        if failStartAndArchiveProjectOnce {
            failStartAndArchiveProjectOnce = false
            pendingStarts[id] = (PendingSessionStart(id: id, projectID: projectID,
                templateSessionID: templateSessionID, text: trimmed, attachments: attachments, turnID: turnID), created)
            archivedSessionIDs.formUnion(records.filter { $0.summary.projectID == projectID }.map(\.summary.id))
            throw LodyClientError.deliveryUnconfirmed
        }
        records.insert(created, at: 0)
        return id
    }

    func pendingSessionStarts(workspaceID: WorkspaceSummary.ID) -> [PendingSessionStart] {
        guard account != nil, workspaceID == "ws-demo" else { return [] }
        return pendingStarts.values.map(\.pending).sorted { $0.id < $1.id }
    }

    func retrySessionStart(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> SessionSummary.ID {
        if let startDelay { try await Task.sleep(for: startDelay) }
        try Task.checkCancellation()
        try requireAccount()
        try requireWorkspace(workspaceID)
        guard let pending = pendingStarts.removeValue(forKey: sessionID) else { throw LodyClientError.sessionMissing }
        records.insert(pending.record, at: 0)
        return sessionID
    }

    func cancelSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        try update(sessionID) { record in
            guard record.summary.activity == .running else { throw LodyClientError.sessionBusy }
            record.summary.activity = .idle
            record.permission = nil
        }
    }

    private var attachmentImages: [String: Data] = [:]

    private func attachmentParts(_ attachments: [ComposerAttachment], text: String) -> [ConversationPart] {
        (text.isEmpty ? [] : [.text(text)]) + attachments.map { attachment in
            let id = attachment.id.uuidString
            if attachment.isImage {
                attachmentImages[id] = attachment.data
                return .image(ConversationImage(imageID: id, mimeType: attachment.mimeType, fileName: attachment.fileName))
            }
            return .file(ConversationFile(fileID: id, fileName: attachment.fileName, sizeBytes: attachment.data.count))
        }
    }

    func loadSessionImage(
        workspaceID: WorkspaceSummary.ID,
        sessionID: SessionSummary.ID,
        imageID: String,
        variant: SessionImageVariant
    ) async throws -> Data {
        try requireAccount()
        try requireWorkspace(workspaceID)
        let known = records.contains { record in
            record.turns.contains { turn in
                turn.content.contains { part in
                    guard case .image(let image) = part, image.imageID == imageID else { return false }
                    return (image.storageSessionID ?? record.summary.id) == sessionID
                }
            }
        }
        guard known else { throw LodyClientError.sessionMissing }
        return attachmentImages[imageID] ?? (imageID == "pr-user-shot" ? FixtureImage.portraitPNG : FixtureImage.png)
    }

    @discardableResult
    func archiveSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws -> [SessionSummary.ID] {
        try requireAccount()
        try requireWorkspace(workspaceID)
        guard records.contains(where: { $0.summary.id == sessionID }) else {
            throw LodyClientError.sessionMissing
        }
        archivedSessionIDs.insert(sessionID)
        archivedActivity[sessionID] = Date()
        return [sessionID]
    }

    func updateSessionMetadata(_ change: SessionMetadataChange, sessionID: String, workspaceID: String) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        try Task.checkCancellation()
        guard let index = records.firstIndex(where: { $0.summary.id == sessionID }),
              !archivedSessionIDs.contains(sessionID) else { throw LodyClientError.sessionMissing }
        switch change {
        case .tabClosed(let value):
            guard records[index].summary.parentSessionID != nil else { throw LodyClientError.sessionMissing }
            records[index].summary.isTabClosed = value
        case .pin(let value): records[index].summary.isPinned = value
        case .rename(let title): records[index].summary.title = title
        case .read(let timestamp):
            records[index].summary.lastReadAt = max(records[index].summary.lastReadAt ?? timestamp, timestamp)
        }
    }

    var supportsSessionMetadataEditing: Bool { true }

    func archivedSessions(workspaceID: WorkspaceSummary.ID) async throws -> [ArchivedSessionSummary] {
        try requireAccount()
        try requireWorkspace(workspaceID)
        return records.compactMap { record in
            guard archivedSessionIDs.contains(record.summary.id) else { return nil }
            return ArchivedSessionSummary(
                id: record.summary.id,
                title: record.summary.title,
                lastActivityAt: archivedActivity[record.summary.id] ?? .distantPast,
                canRestore: record.canRestore,
                projectName: record.summary.projectName
            )
        }
        .sorted { lhs, rhs in
            if lhs.lastActivityAt != rhs.lastActivityAt { return lhs.lastActivityAt > rhs.lastActivityAt }
            return lhs.id < rhs.id
        }
    }

    func restoreArchivedSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        guard let record = records.first(where: { $0.summary.id == sessionID }),
              archivedSessionIDs.contains(sessionID) else {
            throw LodyClientError.sessionMissing
        }
        guard record.canRestore else { throw LodyClientError.archivedProjectUnavailable }
        archivedSessionIDs.remove(sessionID)
        if let index = records.firstIndex(where: { $0.summary.id == sessionID }) {
            records.insert(records.remove(at: index), at: 0)
        }
    }

    func deleteArchivedSession(sessionID: SessionSummary.ID, workspaceID: WorkspaceSummary.ID) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        guard archivedSessionIDs.contains(sessionID) else { throw LodyClientError.sessionMissing }
        records.removeAll { $0.summary.id == sessionID }
        archivedSessionIDs.remove(sessionID)
        archivedActivity.removeValue(forKey: sessionID)
    }

    var supportsQuestionResponses: Bool { true }

    func respondToQuestion(_ request: ConversationQuestionRequest, answers: [String: QuestionAnswer]?,
                           sessionID: String, workspaceID: String) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        try Task.checkCancellation()
        try update(sessionID) { record in
            guard record.questions.contains(where: { $0.id == request.id }) else { throw LodyClientError.permissionMissing }
            if let answers {
                guard request.answerOptionID != nil,
                      request.questions.allSatisfy({ question in
                          guard let answer = answers[question.id] else { return false }
                          switch answer {
                          case .text(let value): return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          case .choices(let values): return question.multiSelect && !values.isEmpty
                          }
                      }) else { throw LodyClientError.emptyMessage }
            } else if request.skipOptionID == nil { throw LodyClientError.permissionMissing }
            record.questions.removeAll { $0.id == request.id }
            record.turns.append(ConversationTurn(id: "question-result-\(request.id)", author: .agent,
                                                 text: answers == nil ? "Question skipped." : "Answer received."))
        }
    }

    func respond(
        _ decision: PermissionDecision,
        requestID: PermissionPrompt.ID,
        sessionID: SessionSummary.ID,
        workspaceID: WorkspaceSummary.ID
    ) async throws {
        try requireAccount()
        try requireWorkspace(workspaceID)
        try update(sessionID) { record in
            guard record.permission?.id == requestID else {
                throw LodyClientError.permissionMissing
            }
            record.permission = nil
            switch decision {
            case .allow:
                record.summary.preview = "Allowed"
            case .deny:
                record.summary.preview = "Denied"
            }
        }
    }

    private func requireAccount() throws {
        guard account != nil else { throw LodyClientError.signedOut }
    }

    private func requireWorkspace(_ workspaceID: WorkspaceSummary.ID) throws {
        guard workspaceID == "ws-demo" else { throw LodyClientError.notConnected }
    }

    private func record(_ sessionID: SessionSummary.ID) throws -> SessionRecord {
        guard let record = records.first(where: { $0.summary.id == sessionID }) else {
            throw LodyClientError.sessionMissing
        }
        return record
    }

    private func update(
        _ sessionID: SessionSummary.ID,
        _ body: (inout SessionRecord) throws -> Void
    ) throws {
        guard let index = records.firstIndex(where: { $0.summary.id == sessionID }) else {
            throw LodyClientError.sessionMissing
        }
        try body(&records[index])
    }

    private func makeTurnID() -> String {
        nextTurnNumber += 1
        return "turn-\(nextTurnNumber)"
    }
}

struct SessionRecord: Equatable, Sendable {
    var summary: SessionSummary
    var turns: [ConversationTurn]
    var permission: PermissionPrompt?
    var runConfig: SessionRunConfig? = nil
    var contextWindowUsage: ContextWindowUsage? = nil
    var fileChanges: [ConversationFileChangeGroup]? = nil
    var canRestore: Bool = true
    var subtasks: [ConversationSubtask] = []
    var questions: [ConversationQuestionRequest] = []
}

extension SessionRunConfig {
    static let fixtureReasoning = SessionRunConfig(
        model: Value(value: "gpt-5.5", label: "gpt-5.5"),
        reasoning: Value(value: "high", label: "High"),
        editable: Editable(kind: .reasoning, configOptionID: "reasoning_effort", options: [
            Value(value: "low", label: "Low"),
            Value(value: "medium", label: "Medium"),
            Value(value: "high", label: "High"),
        ])
    )

    static let fixtureModel = SessionRunConfig(
        model: Value(value: "sonnet", label: "Sonnet"),
        reasoning: nil,
        editable: Editable(kind: .model, configOptionID: nil, options: [
            Value(value: "sonnet", label: "Sonnet"),
            Value(value: "opus", label: "Opus"),
        ])
    )
}

extension NewSessionRunConfig {
    static let fixture = NewSessionRunConfig(
        model: Model(configOptionID: nil, value: "gpt-5.5", options: [
            ModelOption(value: "gpt-5.5", label: "gpt-5.5", reasoning: [
                SessionRunConfig.Value(value: "low", label: "Low"),
                SessionRunConfig.Value(value: "medium", label: "Medium"),
                SessionRunConfig.Value(value: "high", label: "High"),
            ]),
            ModelOption(value: "gpt-5.4-mini", label: "gpt-5.4-mini", reasoning: [
                SessionRunConfig.Value(value: "low", label: "Low"),
            ]),
        ]),
        reasoning: Reasoning(configOptionID: "reasoning_effort", value: "high", options: [])
    )

    static let fixtureModelOnly = NewSessionRunConfig(
        model: Model(configOptionID: nil, value: "sonnet", options: [
            ModelOption(value: "sonnet", label: "Sonnet", reasoning: []),
            ModelOption(value: "opus", label: "Opus", reasoning: []),
        ]),
        reasoning: nil
    )
}

enum FixtureImage {
    /// 300×400 portrait with no message dimensions, exercising loaded-image sizing.
    static let portraitPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAASwAAAGQCAIAAACbF8osAAAE00lEQVR42u3TsQkAIBAEwS/MEm3NIoyNzb8EQQRBB7aC4yb6mJIuFiaQIJQglAShBKEkCCUIJUEoQSgJQglCSRBKEEqCUIJQEoQShJIglCCUBKEEoSQIJQglQShBKAlCCUJJEEoQSoJQglAShBKEkiCUIJQEoQShJAglCCVBKEEoCUIJQkkQShBKglCCUBKEEoSSIJQg3KrUJp0NQggFIYSCEEIIBSGEghBCCAUhhIIQQggFIYSCEEIIBSGEghBCCAUhhIIQQggFIYSCEEIIBSGEghBCCAUhhIIQQggFIYSCEEIIBSGEghBCCAUhhIIQQqcRhBAKQgglCCEUhBBKEEIoCCGUIIRQEEIoQQihIIRQghBCQQihBCGEghBCCUIIBSGEEoQQCkIIJQghFIQQShBCKAghlCCEUBBCKEEIoSCEUIIQQkEIoQQhhIIQQglCCAUhhBKEEApCCCUIIRSEEEoQQigIIZQghFAQQigIIYRQEEIoCCGEUBBCKAghhFAQQigIIYRQEEIoCCGEUBBCKAghhFAQQigIIYRQEEIoCCGEUBBCKAghhFAQQigIIYRQEEIoCCGEUBBCKAghhFAQQigIIZQghFAQQihBCKEghFCCEEJBCKEEIYSCEEIJQggFIYQShBAKQgglCCEUhBBKEEIoCCGUIIRQEEIoQQihIIRQghBCQQihBCGEghBCCUIIBSGEEoQQCkIIJQghFIQQShBCKAghlCCEUBBCKEEIoSCEUIIQQkEIoQQhhIIQQkEIIYSCEEJBCCGEghBCQQghhIIQQkEIIYSCEEJBCCGEghBCQQghhIIQQkEIIYSCEEJBCCGEghBCQQghhIIQQkEIIYSCEEJBCCGEghBCQQihxwhCCAUhhBKEEApCCCUIIRSEEEoQQigIIZQghFAQQihBCKEghFCCEEJBCKEEIYSCEEIJQggFIYQShBAKQgglCCEUhBBKEEIoCCGUIIRQEEIoQQihIIRQghBCQQihBCGEghBCCUIIBSGEEoQQCkIIJQghFIQQShBCKAghlCCEUBBCKAghhFAQQigIIYRQEEIoCCGEUBBCKAghhFAQQigIIYRQEEIoCCGEUBBCKAghhFAQQigIIYRQEEIoCCGEUBBCKAghhFAQQigIIYRQEEIoCCF0GkEIoSCEUIIQQkEIoQQhhIIQQglCCAUhhBKEEApCCCUIIRSEEEoQQigIIZQghFAQQihBCKEghFCCEEJBCKEEIYSCEEIJQggFIYQShBAKQgglCCEUhBBKEEIoCCGUIIRQEEIoQQihIIRQghBCQQihBCGEghBCCUIIBSGEEoQQCkIIBSGEEApCCAUhhBAKQggFIYQQCkIIBSGEEApCCAUhhBAKQggFIYQQCkIIBSGEEApCCAUhhBAKQggFIYQQCkIIBSGEEApCCAUhhBAKQggFIYROIwghFIQQShBCKAghlCCEUBBCKEEIoSCEUIIQQkEIoQQhhIIQQglCCAUhhBKEEArC1xFKnwShBKEEoSQIJQglQShBKAlCCUJJEEoQSoJQglAShBKEkiCUIJQEoQShJAglCCVBKEEoCUIJQkkQShBKglCCUBKEEoSSIJQglAShBKEkCCUIJUEoQSgJQglCSRBKEEqCUIJQEoQShJIglCCUtCgBDpLAqyYZ9voAAAAASUVORK5CYII=")!

    /// 120×80 PNG, so fixture layouts also exercise non-square image content.
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAHgAAABQCAYAAADSm7GJAAAA00lEQVR4nO3RMQ0AIADAMPwLQARyMAQySEaP/ks21tyHrvE6AIMxGIM/ZXCcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGxxkcZ3CcwXEGx10d8AQ+quhfSQAAAABJRU5ErkJggg==")!
}

extension SessionRecord {
    static let questionSample = SessionRecord(
        summary: SessionSummary(id: "session-question", title: "question demo", agentName: "codex",
                                activity: .running, preview: "Waiting for your answer",
                                projectID: "local:machine-1:kurage", projectName: "kurage", machineName: "spike@mac"),
        turns: [ConversationTurn(id: "question-user", author: .user, text: "Help me review the changes."),
                ConversationTurn(id: "question-agent", author: .agent, text: "I need a little more context before continuing.")],
        permission: nil,
        questions: [ConversationQuestionRequest(id: "question-demo", turnID: "question-agent", requestID: "request-demo",
            questions: [
                ConversationQuestion(id: "session", question: "Which session should I inspect? Include its title or session ID.",
                                     header: "Session", options: [], multiSelect: false, allowCustomAnswer: true, isSecret: false),
                ConversationQuestion(id: "preview", question: "What do you see when opening AppModel.swift?",
                                     header: "Preview", options: [.init(label: "Code diff", description: "The file changes are visible."),
                                                                  .init(label: "Preview unavailable", description: "No code is shown.")],
                                     multiSelect: false, allowCustomAnswer: true, isSecret: false),
            ], answerOptionID: "answer", skipOptionID: "skip")]
    )

    static let samples: [SessionRecord] = [
        SessionRecord(
            summary: SessionSummary(
                id: "session-tests",
                title: "fix flaky tests",
                agentName: "codex",
                activity: .running,
                preview: "Running npm test",
                projectID: "local:machine-1:kurage",
                projectName: "kurage",
                machineName: "spike@mac"
            ),
            turns: [
                ConversationTurn(id: "tests-user", author: .user, text: "Run the tests again"),
                ConversationTurn(id: "tests-agent", author: .agent, text: "Running npm test",
                                 timing: ConversationTiming(startedAtMs: Date.now.timeIntervalSince1970 * 1000 - 35_000)),
            ],
            permission: PermissionPrompt(
                id: "perm-npm-test",
                title: "Allow npm test?",
                detail: "codex wants to run npm test on this machine"
            ),
            runConfig: .fixtureReasoning
        ),
        SessionRecord(
            summary: SessionSummary(
                id: "session-long",
                title: "long conversation",
                agentName: "codex",
                activity: .idle,
                preview: "Latest reply in long conversation",
                projectID: "local:machine-1:kurage",
                projectName: "kurage",
                machineName: "spike@mac",
                lastMessageAt: 1_000,
                lastReadAt: 900
            ),
            turns: (1...20).flatMap { number in
                [
                    ConversationTurn(id: "long-user-\(number)", author: .user, text: "Question \(number)"),
                    ConversationTurn(
                        id: "long-agent-\(number)",
                        author: .agent,
                        text: number == 20 ? "Latest reply in long conversation" : "Answer \(number): More details about this question.",
                        parts: number == 20 ? [
                            .file(ConversationFile(fileID: "before-work", fileName: "Before work.txt", sizeBytes: 12)),
                            .text("Latest reply in long conversation"),
                        ] : [],
                        work: number == 20 ? .fixture : nil
                    ),
                ]
            },
            permission: nil,
            runConfig: .fixtureReasoning,
            contextWindowUsage: ContextWindowUsage(size: 258_000, used: 217_000),
            fileChanges: [.fixture]
        ),
        SessionRecord(
            summary: SessionSummary(
                id: "session-pr",
                title: "review the PR",
                agentName: "claude",
                activity: .idle,
                preview: "Waiting for you",
                projectID: "local:machine-1:prism",
                projectName: "prism",
                machineName: "spike@mac"
            ),
            turns: [
                ConversationTurn(
                    id: "pr-user", author: .user, text: "Look at this PR",
                    parts: [
                        .image(ConversationImage(
                            imageID: "pr-user-shot", mimeType: "image/png", fileName: "screenshot.png"
                        )),
                        .text("Look at this PR"),
                    ]
                ),
                ConversationTurn(
                    id: "pr-agent", author: .agent, text: "The diff is small. Waiting for you.",
                    parts: [
                        .text("The diff is small. Waiting for you."),
                        .image(ConversationImage(
                            imageID: "pr-shot", mimeType: "image/png", fileName: "diff.png",
                            width: 120, height: 80
                        )),
                        .image(ConversationImage(imageID: "pr-shot-2", mimeType: "image/png", fileName: "details.png")),
                        .image(ConversationImage(imageID: "pr-shot-3", mimeType: "image/png", fileName: "result.png")),
                    ]
                ),
            ],
            permission: nil,
            runConfig: .fixtureModel
        ),
        SessionRecord(
            summary: SessionSummary(
                id: "archived-newer",
                title: "newer archived",
                agentName: "codex",
                activity: .idle,
                preview: "Archived note",
                projectID: "local:machine-1:kurage",
                projectName: "kurage"
            ),
            turns: [
                ConversationTurn(id: "archived-newer-user", author: .user, text: "Archived note"),
            ],
            permission: nil
        ),
        SessionRecord(
            summary: SessionSummary(
                id: "archived-older",
                title: "older archived",
                agentName: "codex",
                activity: .idle,
                preview: "Old note",
                projectID: "local:machine-1:prism",
                projectName: "prism"
            ),
            turns: [
                ConversationTurn(id: "archived-older-user", author: .user, text: "Old note"),
            ],
            permission: nil
        ),
    ]
}


extension ConversationWork {
    static let fixture = ConversationWork(durationMs: 87_400, insertionIndex: 1, parts: [
        .text("I will check the conversation layout first."),
        .activity(ConversationActivity(id: "2:long-tool-1", commands: 2, reads: 1, steps: [
            .init(id: "long-tool-1", kind: .command, title: "git status --short"),
            .init(id: "long-tool-2", kind: .read, title: "Read ConversationView.swift"),
            .init(id: "long-tool-3", kind: .command, title: "xcodebuild test"),
        ])),
    ])
}

extension ConversationFileChangeGroup {
    static let fixture = ConversationFileChangeGroup(id: "long-agent-20", turnNumber: 20, files: [
        ConversationFileChange(path: "KurageApp/Features/Conversation/ConversationView.swift",
                               additions: 2, deletions: 1, edits: [
            ConversationFileEdit(id: "edit-1", oldText: "struct ConversationView {\n    let title = \"Chat\"\n}\n",
                                 newText: "struct ConversationView {\n    let title = \"Conversation\"\n    let showsChanges = true\n}\n"),
        ]),
        ConversationFileChange(path: "KurageTests/ConversationChangesTests.swift",
                               additions: 12, deletions: 0, edits: []),
    ])
}


extension SessionRecord {
    static var samplesWithSubtasks: [SessionRecord] {
        var records = samples
        if let index = records.firstIndex(where: { $0.summary.id == "session-long" }) {
            records[index].subtasks = [
                ConversationSubtask(id: "review-reuse", title: "Review code reuse", agentName: "Codex agent",
                                    status: .completed, summary: "Reuse review finished.",
                                    totalTokens: 1200, toolUses: 3, steps: [
                    .init(id: "reuse-start", title: "Start subagent reuse_review", status: .completed),
                    .init(id: "reuse-interact", title: "Interact with subagent reuse_review", status: .completed,
                          summary: "Checked shared helpers."),
                    .init(id: "reuse-complete", title: "Complete subagent reuse_review", status: .completed),
                ]),
                ConversationSubtask(id: "review-quality", title: "Review correctness", agentName: "Codex agent",
                                    status: .running, summary: "Checking state isolation.", lastToolName: "Read"),
            ]
        }
        return records
    }
}
