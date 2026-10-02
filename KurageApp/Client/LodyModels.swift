import Foundation

struct Account: Codable, Equatable, Sendable {
    var email: String
    var id: String? = nil
    var name: String? = nil
    var image: String? = nil
}

enum SessionActivity: String, Codable, Equatable, Sendable {
    case running
    case idle
}

struct SessionSummary: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var title: String
    var agentName: String
    var activity: SessionActivity
    var preview: String
    var projectID: String? = nil
    var projectName: String? = nil
    var machineName: String? = nil
    var parentSessionID: String? = nil
    var isTabClosed: Bool? = nil
    var isPinned: Bool? = nil
    var lastMessageAt: Double? = nil
    var lastReadAt: Double? = nil
    /// List sorting fallback from the bridge, including creation time when no message exists.
    var lastActivityAt: Double? = nil
    /// List-only aggregation; `activity` remains the state of this exact tab.
    var hasRunningTabs: Bool? = nil

    var isRunningInList: Bool { activity == .running || hasRunningTabs == true }

    var isUnread: Bool {
        guard let lastMessageAt, lastMessageAt.isFinite else { return false }
        guard let lastReadAt, lastReadAt.isFinite else { return true }
        return lastMessageAt > lastReadAt
    }
}

struct MentionSession: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let projectID: String?
    let lastActivityAt: Double
}

struct MentionSkill: Codable, Identifiable, Equatable, Sendable {
    let token: String
    let name: String
    let description: String
    let path: String

    var id: String { token }
}

struct ArchivedSessionSummary: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var lastActivityAt: Date
    var canRestore: Bool
    var projectName: String?
}

enum TurnAuthor: String, Codable, Equatable, Sendable {
    case user
    case agent
}

enum SessionImageVariant: Hashable, Sendable {
    /// Wide preview, aspect preserved by the thumbnail service.
    case inline
    /// Square cover thumbnail for a group of images.
    case square
    case original
}

struct ConversationImage: Codable, Equatable, Sendable, Identifiable {
    var imageID: String
    var mimeType: String?
    var fileName: String?
    var storageSessionID: String?
    var width: Int?
    var height: Int?
    /// Process-local previews are never encoded into synchronized documents.
    var localPreviewData: Data? = nil
    var localOriginalData: Data? = nil
    var localPreviewScopeID: UUID? = nil

    private enum CodingKeys: String, CodingKey {
        case imageID, mimeType, fileName, storageSessionID, width, height
    }

    var id: String { "\(storageSessionID ?? "")\n\(imageID)" }

    var isDisplayable: Bool {
        (mimeType.map { Self.displayableMIMETypes.contains($0.lowercased()) } ?? true)
            && Self.isReference(imageID)
    }

    var accessibilityName: String {
        let name = fileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return "Attached image" }
        return name.count > 80 ? String(name.prefix(80)) : name
    }

    static let displayableMIMETypes: Set<String> = ["image/png", "image/jpeg", "image/webp", "image/gif"]

    static func isReference(_ value: String) -> Bool {
        value.wholeMatch(of: /^[A-Za-z0-9_-]{1,128}$/) != nil
    }
}

struct ConversationFile: Codable, Equatable, Sendable {
    let fileID: String
    let fileName: String
    let sizeBytes: Int
}

/// A run of consecutive tool calls, summarized like Lody's activity groups.
struct ConversationActivity: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case command, read, edit, search, fetch, tool
    }

    struct Step: Codable, Equatable, Sendable, Identifiable {
        let id: String
        var kind: Kind
        var title: String
    }

    let id: String
    var commands = 0
    var reads = 0
    var edits = 0
    var searches = 0
    var fetches = 0
    var tools = 0
    var steps: [Step] = []

    /// Lody's wording, e.g. "Ran 3 commands · Read 2 files".
    var summary: String {
        [
            Self.phrase(commands, "Ran", "command", "commands"),
            Self.phrase(reads, "Read", "file", "files"),
            Self.phrase(edits, "Edited", "file", "files"),
            Self.phrase(searches, "Ran", "search", "searches"),
            Self.phrase(fetches, "Fetched", "resource", "resources"),
            Self.phrase(tools, "Called", "tool", "tools"),
        ].compactMap(\.self).joined(separator: " · ")
    }

    /// The first kind in summary order.
    var primaryKind: Kind {
        [(commands, Kind.command), (reads, .read), (edits, .edit), (searches, .search), (fetches, .fetch)]
            .first { $0.0 > 0 }?.1 ?? .tool
    }

    var isEmpty: Bool { commands + reads + edits + searches + fetches + tools == 0 }

    private static func phrase(_ count: Int, _ verb: String, _ one: String, _ many: String) -> String? {
        count > 0 ? "\(verb) \(count) \(count == 1 ? one : many)" : nil
    }

    init(id: String, commands: Int = 0, reads: Int = 0, edits: Int = 0, searches: Int = 0,
         fetches: Int = 0, tools: Int = 0, steps: [Step] = []) {
        self.id = id
        self.commands = commands
        self.reads = reads
        self.edits = edits
        self.searches = searches
        self.fetches = fetches
        self.tools = tools
        self.steps = steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        func count(_ key: CodingKeys) -> Int { max(0, (try? container.decodeIfPresent(Int.self, forKey: key)) ?? 0) }
        commands = count(.commands)
        reads = count(.reads)
        edits = count(.edits)
        searches = count(.searches)
        fetches = count(.fetches)
        tools = count(.tools)
        steps = ((try? container.decodeIfPresent([LossyStep].self, forKey: .steps)) ?? []).compactMap(\.step)
    }

    private enum CodingKeys: String, CodingKey {
        case id, commands, reads, edits, searches, fetches, tools, steps
    }

    /// Drops steps of kinds this client does not know instead of the whole group.
    private struct LossyStep: Decodable {
        var step: Step?
        init(from decoder: Decoder) throws { step = try? Step(from: decoder) }
    }
}

/// Earlier work of a finished turn, folded behind "Worked for …" above its answer.
struct ConversationWork: Codable, Equatable, Sendable {
    /// Effective working time, excluding permission waits. Absent when not recorded.
    var durationMs: Double?
    /// Number of visible turn parts before the folded group; old caches default to zero.
    var insertionIndex: Int
    var parts: [ConversationPart]

    init(durationMs: Double? = nil, insertionIndex: Int = 0, parts: [ConversationPart]) {
        self.insertionIndex = insertionIndex
        self.durationMs = durationMs
        self.parts = parts
    }

    var title: String {
        guard let durationMs, durationMs.isFinite, durationMs >= 0 else { return "Finished working" }
        return "Worked for \(Self.formatDuration(durationMs))"
    }

    /// Matches Lody's compact format: `12s`, `1m 05s`, `1h 02m 03s`.
    static func formatDuration(_ milliseconds: Double) -> String {
        let total = Int(min(max(milliseconds, 0), 1e15) / 1000)
        let (hours, minutes, seconds) = (total / 3600, total % 3600 / 60, total % 60)
        let padded = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        if hours > 0 { return "\(hours)h \(padded(minutes))m \(padded(seconds))s" }
        if minutes > 0 { return "\(minutes)m \(padded(seconds))s" }
        return "\(seconds)s"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        insertionIndex = try container.decodeIfPresent(Int.self, forKey: .insertionIndex) ?? 0
        durationMs = try container.decodeIfPresent(Double.self, forKey: .durationMs)
        parts = try container.decodeIfPresent([PartBox].self, forKey: .parts)?.compactMap(\.part) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(insertionIndex, forKey: .insertionIndex)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
        try container.encode(parts.map(PartBox.init), forKey: .parts)
    }

    private enum CodingKeys: String, CodingKey {
        case durationMs, insertionIndex, parts
    }
}

enum ConversationPart: Equatable, Sendable {
    case text(String)
    case image(ConversationImage)
    case file(ConversationFile)
    case activity(ConversationActivity)

    /// Hides blank text and images this client cannot display.
    var displayable: ConversationPart? {
        switch self {
        case .text(let text):
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
        case .image(let image):
            image.isDisplayable ? self : nil
        case .activity(let activity):
            activity.isEmpty ? nil : self
        case .file:
            self
        }
    }
}

/// Live history timing, in milliseconds since Unix epoch; absent on completed turns.
struct ConversationTiming: Codable, Equatable, Sendable {
    var startedAtMs: Double?
    var permissionWaitMs: Double = 0

    func title(at date: Date) -> String {
        guard let startedAtMs, startedAtMs.isFinite else { return "Working…" }
        let now = date.timeIntervalSince1970 * 1000
        guard now.isFinite else { return "Working…" }
        let wait = permissionWaitMs.isFinite ? max(0, permissionWaitMs) : 0
        let elapsed = max(0, now - startedAtMs - wait)
        return "Working… \(ConversationWork.formatDuration(elapsed))"
    }
}

struct ConversationTurn: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var author: TurnAuthor
    var text: String
    var parts: [ConversationPart]
    /// Folded earlier work of a finished agent turn; `parts` then holds its answer.
    var work: ConversationWork?
    var timing: ConversationTiming?
    /// Explicit machine acceptance projected from history or session metadata.
    var isDeliveryConfirmed = false
    /// This exact ID was permanently rejected by missing-history recovery.
    var isDeliveryRejected = false
    /// A local presentation state, excluded from the wire representation.
    var delivery: MessageDelivery? = nil

    init(id: String, author: TurnAuthor, text: String, parts: [ConversationPart] = [], work: ConversationWork? = nil, timing: ConversationTiming? = nil) {
        self.id = id
        self.author = author
        self.text = text
        self.parts = parts
        self.work = work
        self.timing = timing
    }

    /// Ordered chat content. Text-only turns written before image parts still render their text.
    var content: [ConversationPart] {
        let visible = parts.compactMap(\.displayable)
        if !visible.isEmpty { return visible }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.text(text)]
    }

    /// Folded work that still has something to show.
    var displayedWork: ConversationWork? {
        guard author == .agent, var work else { return nil }
        work.parts = work.parts.compactMap(\.displayable)
        return work.parts.isEmpty ? nil : work
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        author = try container.decode(TurnAuthor.self, forKey: .author)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        parts = try container.decodeIfPresent([PartBox].self, forKey: .parts)?.compactMap(\.part) ?? []
        work = try? container.decodeIfPresent(ConversationWork.self, forKey: .work)
        timing = try? container.decodeIfPresent(ConversationTiming.self, forKey: .timing)
        isDeliveryConfirmed = try container.decodeIfPresent(Bool.self, forKey: .isDeliveryConfirmed) ?? false
        isDeliveryRejected = try container.decodeIfPresent(Bool.self, forKey: .isDeliveryRejected) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(author, forKey: .author)
        try container.encode(text, forKey: .text)
        try container.encode(parts.map(PartBox.init), forKey: .parts)
        try container.encodeIfPresent(work, forKey: .work)
        try container.encodeIfPresent(timing, forKey: .timing)
        if isDeliveryConfirmed { try container.encode(true, forKey: .isDeliveryConfirmed) }
        if isDeliveryRejected { try container.encode(true, forKey: .isDeliveryRejected) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, author, text, parts, work, timing, isDeliveryConfirmed, isDeliveryRejected
    }
}

/// Decodes one projected part and drops kinds this client does not display.
private struct PartBox: Codable {
    var part: ConversationPart?

    init(_ part: ConversationPart) {
        self.part = part
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decodeIfPresent(String.self, forKey: .type) {
        case "text":
            if let text = try container.decodeIfPresent(String.self, forKey: .text),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                part = .text(text)
            }
        case "file":
            if let file = try? ConversationFile(from: decoder), ConversationImage.isReference(file.fileID), file.sizeBytes > 0 { part = .file(file) }
        case "image":
            if let image = try? ConversationImage(from: decoder), image.isDisplayable {
                part = .image(image)
            }
        case "activity":
            if let activity = try? ConversationActivity(from: decoder), !activity.isEmpty {
                part = .activity(activity)
            }
        default:
            break
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch part {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .file(let file):
            try container.encode("file", forKey: .type)
            try file.encode(to: encoder)
        case .image(let image):
            try container.encode("image", forKey: .type)
            try container.encode(image.imageID, forKey: .imageID)
            try container.encodeIfPresent(image.mimeType, forKey: .mimeType)
            try container.encodeIfPresent(image.fileName, forKey: .fileName)
            try container.encodeIfPresent(image.storageSessionID, forKey: .storageSessionID)
            try container.encodeIfPresent(image.width, forKey: .width)
            try container.encodeIfPresent(image.height, forKey: .height)
        case .activity(let activity):
            try container.encode("activity", forKey: .type)
            try activity.encode(to: encoder)
        case nil:
            break
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, imageID, mimeType, fileName, storageSessionID, width, height
    }
}

struct PermissionPrompt: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var detail: String
}

/// One subagent the session spawned. Codex reports its lifecycle activities as
/// separate history tasks, so the bridge groups them here: `steps` keeps what
/// the subagent ran through, while the remaining fields describe it as a whole.
struct ConversationSubtask: Codable, Equatable, Hashable, Sendable, Identifiable {
    enum Status: String, Codable, Sendable {
        case pending, running = "in_progress", completed, failed
    }

    struct Step: Codable, Equatable, Hashable, Sendable, Identifiable {
        let id: String
        var title: String
        var status: Status
        var summary: String? = nil
        var error: String? = nil
    }

    let id: String
    var title: String
    var agentName: String
    var status: Status
    var summary: String? = nil
    var error: String? = nil
    var lastToolName: String? = nil
    var modelID: String? = nil
    var totalTokens: Int? = nil
    var toolUses: Int? = nil
    var steps: [Step]? = nil
}

struct Conversation: Codable, Equatable, Sendable {
    var sessionID: SessionSummary.ID
    var turns: [ConversationTurn]
    var permission: PermissionPrompt?
    var fileChanges: [ConversationFileChangeGroup]? = nil
    var latestTurnNumber: Int? = nil
    var subtasks: [ConversationSubtask]? = nil
    var questions: [ConversationQuestionRequest]? = nil

    var lastTurnNumber: Int {
        latestTurnNumber ?? max(1, turns.filter { $0.author == .user }.count,
                                fileChanges?.map(\.turnNumber).max() ?? 1)
    }
}

/// Latest context usage reported in the session's Lody metadata.
struct ContextWindowUsage: Codable, Equatable, Sendable {
    var size: Int
    var used: Int

    var usedFraction: Double { isValid ? min(Double(used) / Double(size), 1) : 0 }
    var isValid: Bool { size > 0 && used >= 0 }
}

enum PermissionDecision: Equatable, Sendable {
    case allow
    case deny
}

struct WorkspaceSummary: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var slug: String
}

struct DeviceAuthorization: Equatable, Sendable {
    var userCode: String
    var verificationURL: URL
    var deviceCode: String
    var expiresIn: TimeInterval
    var interval: TimeInterval
}

enum LodyClientError: Error, Equatable {
    case signedOut
    case sessionMissing
    case archivedProjectUnavailable
    case permissionMissing
    case emptyMessage
    case sessionCreationRejected
    case deliveryUnconfirmed
    case previousSendPending(String)
    case sendSuperseded
    case sendNotDelivered
    case sessionBusy
    case notConnected
    case unreachable
    case signInFailed
    case accessDenied
    case codeExpired
}

/// Model and reasoning for the session's next turn, as projected from the
/// latest user turn, the CLI's applied config and the agent's capabilities.
struct SessionRunConfig: Codable, Equatable, Sendable {
    struct Value: Codable, Equatable, Sendable, Identifiable {
        var value: String
        var label: String
        var id: String { value }
    }

    struct Editable: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case model
            case reasoning
        }

        var kind: Kind
        /// `nil` writes the turn's `modelId`; otherwise a config option value.
        var configOptionID: String?
        var options: [Value]
    }

    var model: Value?
    var reasoning: Value?
    var editable: Editable?

    func choosing(_ value: String) -> RunConfigChoice? {
        guard let editable, editable.options.contains(where: { $0.value == value }) else { return nil }
        return RunConfigChoice(configOptionID: editable.configOptionID, value: value)
    }

    func applying(_ choice: RunConfigChoice?) -> SessionRunConfig {
        guard let choice, let editable, editable.configOptionID == choice.configOptionID,
              let option = editable.options.first(where: { $0.value == choice.value }) else { return self }
        var copy = self
        switch editable.kind {
        case .model: copy.model = option
        case .reasoning: copy.reasoning = option
        }
        return copy
    }
}

/// A single model or reasoning change applied to the next new turn.
struct RunConfigChoice: Equatable, Sendable {
    var configOptionID: String?
    var value: String
}

/// Model and reasoning for a new session's first turn. Both are editable:
/// a new session has no provider context that switching models could discard.
struct NewSessionRunConfig: Codable, Equatable, Sendable {
    struct ModelOption: Codable, Equatable, Sendable, Identifiable {
        var value: String
        var label: String
        /// Reasoning choices this model accepts.
        var reasoning: [SessionRunConfig.Value]
        var id: String { value }
    }

    struct Model: Codable, Equatable, Sendable {
        /// `nil` writes the turn's `modelId`; otherwise a config option value.
        var configOptionID: String?
        var value: String
        var options: [ModelOption]
    }

    struct Reasoning: Codable, Equatable, Sendable {
        var configOptionID: String
        var value: String?
        /// Used when the agent has no model list to carry per-model choices.
        var options: [SessionRunConfig.Value]
    }

    var model: Model?
    var reasoning: Reasoning?

    var selectedModel: ModelOption? {
        model.flatMap { model in model.options.first { $0.value == model.value } }
    }

    var reasoningOptions: [SessionRunConfig.Value] {
        guard let reasoning else { return [] }
        return model == nil ? reasoning.options : selectedModel?.reasoning ?? []
    }

    /// The stored reasoning is kept across model changes and applies only while offered.
    var selectedReasoning: SessionRunConfig.Value? {
        reasoningOptions.first { $0.value == reasoning?.value }
    }

    mutating func selectModel(_ value: String) {
        guard model?.options.contains(where: { $0.value == value }) == true else { return }
        model?.value = value
    }

    mutating func selectReasoning(_ value: String) {
        guard reasoningOptions.contains(where: { $0.value == value }) else { return }
        reasoning?.value = value
    }


    /// Model first, so the bridge checks reasoning against the chosen model.
    var selections: [RunConfigChoice] {
        var choices: [RunConfigChoice] = []
        if let model { choices.append(RunConfigChoice(configOptionID: model.configOptionID, value: model.value)) }
        if let reasoning, let selectedReasoning {
            choices.append(RunConfigChoice(configOptionID: reasoning.configOptionID, value: selectedReasoning.value))
        }
        return choices
    }
}

/// A new session runs on its project's machine with one of that machine's agents.
struct NewSessionOptions: Codable, Equatable, Sendable {
    var machineName: String
    /// The chosen agent config. Empty only for a legacy session without one.
    var agentConfigID: String
    /// Agent configs on the machine, labelled by name.
    var providers: [SessionRunConfig.Value]
    var runConfig: NewSessionRunConfig?
    /// Cached options can be displayed while a scoped request refreshes them.
    var needsRefresh: Bool? = nil

    var provider: SessionRunConfig.Value? {
        providers.first { $0.value == agentConfigID }
    }
}

struct ConversationUpdate: Equatable, Sendable {
    var conversation: Conversation
    var activity: SessionActivity?
    var syncState: ConversationSyncState
    var runConfig: SessionRunConfig? = nil
    var contextWindowUsage: ContextWindowUsage? = nil
    var lastMessageAt: Double? = nil
    var sessionTabs: [SessionSummary]? = nil
}

enum ConversationSyncState: String, Decodable, Sendable {
    case connecting
    case live
}

struct ConversationPatch: Decodable {
    let sessionID: String
    let order: [String]
    let changed: [ConversationTurn]
    let permission: PermissionPrompt?
    var replacesFileChanges: Bool? = nil
    var replacesSubtasks: Bool? = nil
    var fileChanges: [ConversationFileChangeGroup]? = nil
    var latestTurnNumber: Int? = nil
    var subtasks: [ConversationSubtask]? = nil
    var questions: [ConversationQuestionRequest]? = nil
    let activity: String
    let syncState: ConversationSyncState
    var runConfig: SessionRunConfig? = nil
    var contextWindowUsage: ContextWindowUsage? = nil
    var lastMessageAt: Double? = nil
    var sessionTabs: [SessionSummary]? = nil

    func applying(to previous: Conversation) throws -> ConversationUpdate {
        guard previous.sessionID == sessionID, Set(order).count == order.count else {
            throw LodyClientError.notConnected
        }
        var turns = Dictionary(uniqueKeysWithValues: previous.turns.map { ($0.id, $0) })
        for turn in changed { turns[turn.id] = turn }
        let ordered = try order.map { id in
            guard let turn = turns[id] else { throw LodyClientError.notConnected }
            return turn
        }
        return ConversationUpdate(
            conversation: Conversation(sessionID: sessionID, turns: ordered, permission: permission,
                                       fileChanges: replacesFileChanges == true ? fileChanges : previous.fileChanges,
                                       latestTurnNumber: latestTurnNumber ?? previous.latestTurnNumber,
                                       subtasks: replacesSubtasks == true ? subtasks : previous.subtasks,
                                       questions: questions),
            activity: activity == "running" ? .running : .idle, syncState: syncState,
            runConfig: runConfig, contextWindowUsage: contextWindowUsage, lastMessageAt: lastMessageAt, sessionTabs: sessionTabs
        )
    }
}

/// Display data only; credentials remain in Keychain.
struct SessionCache: Codable, Equatable, Sendable {
    var account: Account
    var workspaces: [WorkspaceSummary] = []
    var selectedWorkspaceID: String?
    var sessionsByWorkspace: [String: [SessionSummary]] = [:]
    /// Locally observed negative ACKs, scoped by workspace, session, then turn.
    var rejectedTurnIDsByWorkspace: [String: [String: Set<String>]] = [:]

    private enum CodingKeys: String, CodingKey {
        case account, workspaces, selectedWorkspaceID, sessionsByWorkspace, rejectedTurnIDsByWorkspace
    }
}

extension SessionCache {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            account: try container.decode(Account.self, forKey: .account),
            workspaces: try container.decodeIfPresent([WorkspaceSummary].self, forKey: .workspaces) ?? [],
            selectedWorkspaceID: try container.decodeIfPresent(String.self, forKey: .selectedWorkspaceID),
            sessionsByWorkspace: try container.decodeIfPresent([String: [SessionSummary]].self, forKey: .sessionsByWorkspace) ?? [:],
            rejectedTurnIDsByWorkspace: try container.decodeIfPresent([String: [String: Set<String>]].self,
                                                                      forKey: .rejectedTurnIDsByWorkspace) ?? [:]
        )
    }
}

/// Confirmed archive targets use document IDs, matching the active session list.
struct SessionArchiveResult: Decodable, Sendable {
    let status: String
    let sessionIDs: [String]
}


struct SessionProject: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let rootPath: String
    let templateSessionID: String
}

struct MachineDirectory: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        struct ID: Hashable, Sendable {
            let name: String
            let absolutePath: String
        }
        // Lody resolves symlinks: distinct rows can share the same canonical path.
        var id: ID { ID(name: name, absolutePath: absolutePath) }
        let name: String
        let absolutePath: String
        var error: String? = nil
    }
    let path: String
    let parentPath: String?
    var entries: [Entry]
    let truncated: Bool
    let nextCursor: String?
}

enum SessionProjectAction: String, Sendable { case catalog, browse, select }

struct SessionProjectResult: Codable, Sendable {
    var projects: [SessionProject]? = nil
    var directory: MachineDirectory? = nil
    var project: SessionProject? = nil
}
