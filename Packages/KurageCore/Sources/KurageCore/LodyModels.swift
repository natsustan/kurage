import Foundation

public struct Account: Codable, Equatable, Sendable {
    public var email: String
    public var id: String? = nil
    public var name: String? = nil
    public var image: String? = nil
}

public enum SessionActivity: String, Codable, Equatable, Sendable {
    case running
    case idle
}

public struct SessionSummary: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var agentName: String
    public var activity: SessionActivity
    public var preview: String
    public var projectID: String? = nil
    public var projectName: String? = nil
    public var machineName: String? = nil
    public var parentSessionID: String? = nil
    public var isTabClosed: Bool? = nil
    public var isPinned: Bool? = nil
    public var lastMessageAt: Double? = nil
    public var lastReadAt: Double? = nil
    /// List sorting fallback from the bridge, including creation time when no message exists.
    public var lastActivityAt: Double? = nil
    /// List-only aggregation; `activity` remains the state of this exact tab.
    public var hasRunningTabs: Bool? = nil
    /// Stable configured provider identity; never infer it from the display name.
    public var agentConfigID: String? = nil

    public var isRunningInList: Bool { activity == .running || hasRunningTabs == true }

    public var isUnread: Bool {
        guard let lastMessageAt, lastMessageAt.isFinite else { return false }
        guard let lastReadAt, lastReadAt.isFinite else { return true }
        return lastMessageAt > lastReadAt
    }
}

public struct MentionSession: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let projectID: String?
    public let lastActivityAt: Double
}

public struct MentionSkill: Codable, Identifiable, Equatable, Sendable {
    public let token: String
    public let name: String
    public let description: String
    public let path: String

    public var id: String { token }
}

public struct ArchivedSessionSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var lastActivityAt: Date
    public var canRestore: Bool
    public var projectName: String?
}

public enum TurnAuthor: String, Codable, Equatable, Sendable {
    case user
    case agent
}

public enum SessionImageVariant: Hashable, Sendable {
    /// Wide preview, aspect preserved by the thumbnail service.
    case inline
    /// Square cover thumbnail for a group of images.
    case square
    case original
}

public struct ConversationImage: Codable, Equatable, Sendable, Identifiable {
    public var imageID: String
    public var mimeType: String?
    public var fileName: String?
    public var storageSessionID: String?
    public var width: Int?
    public var height: Int?
    /// Process-local previews are never encoded into synchronized documents.
    public var localPreviewData: Data? = nil
    public var localOriginalData: Data? = nil
    public var localPreviewScopeID: UUID? = nil

    private enum CodingKeys: String, CodingKey {
        case imageID, mimeType, fileName, storageSessionID, width, height
    }

    public var id: String { "\(storageSessionID ?? "")\n\(imageID)" }

    public var isDisplayable: Bool {
        (mimeType.map { Self.displayableMIMETypes.contains($0.lowercased()) } ?? true)
            && Self.isReference(imageID)
    }

    public var accessibilityName: String {
        let name = fileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return "Attached image" }
        return name.count > 80 ? String(name.prefix(80)) : name
    }

    public static let displayableMIMETypes: Set<String> = ["image/png", "image/jpeg", "image/webp", "image/gif"]

    public static func isReference(_ value: String) -> Bool {
        value.wholeMatch(of: /^[A-Za-z0-9_-]{1,128}$/) != nil
    }
}

public struct ConversationFile: Codable, Equatable, Sendable {
    public let fileID: String
    public let fileName: String
    public let sizeBytes: Int
}

/// A run of consecutive tool calls, summarized like Lody's activity groups.
public struct ConversationActivity: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case command, read, edit, search, fetch, tool
    }

    public struct Step: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public var kind: Kind
        public var title: String
    }

    public let id: String
    public var commands = 0
    public var reads = 0
    public var edits = 0
    public var searches = 0
    public var fetches = 0
    public var tools = 0
    public var steps: [Step] = []

    /// Lody's wording, e.g. "Ran 3 commands · Read 2 files".
    public var summary: String {
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
    public var primaryKind: Kind {
        [(commands, Kind.command), (reads, .read), (edits, .edit), (searches, .search), (fetches, .fetch)]
            .first { $0.0 > 0 }?.1 ?? .tool
    }

    public var isEmpty: Bool { commands + reads + edits + searches + fetches + tools == 0 }

    private static func phrase(_ count: Int, _ verb: String, _ one: String, _ many: String) -> String? {
        count > 0 ? "\(verb) \(count) \(count == 1 ? one : many)" : nil
    }

    public init(id: String, commands: Int = 0, reads: Int = 0, edits: Int = 0, searches: Int = 0,
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

    public init(from decoder: Decoder) throws {
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
public struct ConversationWork: Codable, Equatable, Sendable {
    /// Effective working time, excluding permission waits. Absent when not recorded.
    public var durationMs: Double?
    /// Number of visible turn parts before the folded group; old caches default to zero.
    public var insertionIndex: Int
    public var parts: [ConversationPart]

    public init(durationMs: Double? = nil, insertionIndex: Int = 0, parts: [ConversationPart]) {
        self.insertionIndex = insertionIndex
        self.durationMs = durationMs
        self.parts = parts
    }

    public var title: String {
        guard let durationMs, durationMs.isFinite, durationMs >= 0 else { return "Finished working" }
        return "Worked for \(Self.formatDuration(durationMs))"
    }

    /// Matches Lody's compact format: `12s`, `1m 05s`, `1h 02m 03s`.
    public static func formatDuration(_ milliseconds: Double) -> String {
        let total = Int(min(max(milliseconds, 0), 1e15) / 1000)
        let (hours, minutes, seconds) = (total / 3600, total % 3600 / 60, total % 60)
        let padded = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        if hours > 0 { return "\(hours)h \(padded(minutes))m \(padded(seconds))s" }
        if minutes > 0 { return "\(minutes)m \(padded(seconds))s" }
        return "\(seconds)s"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        insertionIndex = try container.decodeIfPresent(Int.self, forKey: .insertionIndex) ?? 0
        durationMs = try container.decodeIfPresent(Double.self, forKey: .durationMs)
        parts = try container.decodeIfPresent([PartBox].self, forKey: .parts)?.compactMap(\.part) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(insertionIndex, forKey: .insertionIndex)
        try container.encodeIfPresent(durationMs, forKey: .durationMs)
        try container.encode(parts.map(PartBox.init), forKey: .parts)
    }

    private enum CodingKeys: String, CodingKey {
        case durationMs, insertionIndex, parts
    }
}

public enum ConversationPart: Equatable, Sendable {
    case text(String)
    case image(ConversationImage)
    case file(ConversationFile)
    case activity(ConversationActivity)
    case error(ConversationError)

    /// Hides blank text and images this client cannot display.
    public var displayable: ConversationPart? {
        switch self {
        case .text(let text):
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
        case .image(let image):
            image.isDisplayable ? self : nil
        case .activity(let activity):
            activity.isEmpty ? nil : self
        case .file, .error:
            self
        }
    }
}

/// Live history timing, in milliseconds since Unix epoch; absent on completed turns.
public struct ConversationTiming: Codable, Equatable, Sendable {
    public var startedAtMs: Double?
    public var permissionWaitMs: Double = 0

    public func title(at date: Date) -> String {
        guard let startedAtMs, startedAtMs.isFinite else { return "Working…" }
        let now = date.timeIntervalSince1970 * 1000
        guard now.isFinite else { return "Working…" }
        let wait = permissionWaitMs.isFinite ? max(0, permissionWaitMs) : 0
        let elapsed = max(0, now - startedAtMs - wait)
        return "Working… \(ConversationWork.formatDuration(elapsed))"
    }
}

public struct ConversationTurn: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var author: TurnAuthor
    public var text: String
    public var parts: [ConversationPart]
    /// Folded earlier work of a finished agent turn; `parts` then holds its answer.
    public var work: ConversationWork?
    public var timing: ConversationTiming?
    /// Explicit machine acceptance projected from history or session metadata.
    public var isDeliveryConfirmed = false
    /// This exact ID was permanently rejected by missing-history recovery.
    public var isDeliveryRejected = false
    /// A local presentation state, excluded from the wire representation.
    public var delivery: MessageDelivery? = nil

    public init(id: String, author: TurnAuthor, text: String, parts: [ConversationPart] = [], work: ConversationWork? = nil, timing: ConversationTiming? = nil) {
        self.id = id
        self.author = author
        self.text = text
        self.parts = parts
        self.work = work
        self.timing = timing
    }

    /// Ordered chat content. Text-only turns written before image parts still render their text.
    public var content: [ConversationPart] {
        let visible = parts.compactMap(\.displayable)
        if !visible.isEmpty { return visible }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.text(text)]
    }

    /// Folded work that still has something to show.
    public var displayedWork: ConversationWork? {
        guard author == .agent, var work else { return nil }
        work.parts = work.parts.compactMap(\.displayable)
        return work.parts.isEmpty ? nil : work
    }

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
        case "error":
            if let error = try? ConversationError(from: decoder), !error.id.isEmpty {
                part = .error(error)
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
        case .error(let error):
            try container.encode("error", forKey: .type)
            try error.encode(to: encoder)
        case nil:
            break
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, imageID, mimeType, fileName, storageSessionID, width, height
    }
}

public struct PermissionPrompt: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var detail: String
}

/// One subagent projected from parent history. Normalized runs carry their own
/// transcript; legacy Codex lifecycle activities are grouped into `steps`.
public struct ConversationSubtask: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case pending, running = "in_progress", completed, failed, cancelled, unknown
    }

    /// Projected from the normalized run embedded in parent history, not a child Session.
    public struct Run: Codable, Equatable, Sendable {
        public struct PlanEntry: Codable, Equatable, Sendable {
            public enum Status: String, Codable, Sendable {
                case pending, inProgress = "in_progress", completed
            }
            public var content: String
            public var status: Status
        }

        public var turns: [ConversationTurn]
        public var streamsOutput: Bool
        public var outputIncomplete: Bool
        public var plan: [PlanEntry] = []
    }

    public struct Step: Codable, Equatable, Hashable, Sendable, Identifiable {
        public let id: String
        public var title: String
        public var status: Status
        public var summary: String? = nil
        public var error: String? = nil
    }

    public let id: String
    public var title: String
    public var agentName: String
    public var status: Status
    public var summary: String? = nil
    public var error: String? = nil
    public var lastToolName: String? = nil
    public var modelID: String? = nil
    public var totalTokens: Int? = nil
    public var toolUses: Int? = nil
    public var steps: [Step]? = nil
    public var run: Run? = nil
    public var progressSummary: String? = nil
}

public struct Conversation: Codable, Equatable, Sendable {
    public var sessionID: SessionSummary.ID
    public var turns: [ConversationTurn]
    public var permission: PermissionPrompt?
    public var fileChanges: [ConversationFileChangeGroup]? = nil
    public var latestTurnNumber: Int? = nil
    public var subtasks: [ConversationSubtask]? = nil
    public var questions: [ConversationQuestionRequest]? = nil
    public var cacheUsage: ConversationCacheUsage? = nil

    public var lastTurnNumber: Int {
        latestTurnNumber ?? max(1, turns.filter { $0.author == .user }.count,
                                fileChanges?.map(\.turnNumber).max() ?? 1)
    }
}

/// Cache accounting from the recorded assistant turns of this conversation.
/// Ordinary input excludes cache reads and writes in Lody's token protocol.
public struct ConversationCacheUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var cacheReadInputTokens: Int
    public var cacheCreationInputTokens: Int
    public var reportedTurns: Int
    public var totalTurns: Int

    public var isValid: Bool {
        inputTokens >= 0 && cacheReadInputTokens >= 0 && cacheCreationInputTokens >= 0 &&
            reportedTurns > 0 && totalTurns >= reportedTurns
    }

    public var hitFraction: Double? {
        guard isValid else { return nil }
        let input = Double(inputTokens) + Double(cacheReadInputTokens) + Double(cacheCreationInputTokens)
        return input > 0 ? Double(cacheReadInputTokens) / input : nil
    }
}

/// Latest context usage reported in the session's Lody metadata.
public struct ContextWindowUsage: Codable, Equatable, Sendable {
    public var size: Int
    public var used: Int

    public var usedFraction: Double { isValid ? min(Double(used) / Double(size), 1) : 0 }
    public var isValid: Bool { size > 0 && used >= 0 }
}

public enum PermissionDecision: Equatable, Sendable {
    case allow
    case deny
}

public struct WorkspaceSummary: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var slug: String

    public init(id: String, name: String, slug: String) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

public struct DeviceAuthorization: Equatable, Sendable {
    public var userCode: String
    public var verificationURL: URL
    public var deviceCode: String
    public var expiresIn: TimeInterval
    public var interval: TimeInterval
}

public enum LodyClientError: Error, Equatable {
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
public struct SessionRunConfig: Codable, Equatable, Sendable {
    public struct Value: Codable, Equatable, Sendable, Identifiable {
        public var value: String
        public var label: String
        /// Public brand key for provider choices; absent on model/reasoning values.
        public var icon: String? = nil
        public var id: String { value }

        public init(value: String, label: String, icon: String? = nil) {
            self.value = value
            self.label = label
            self.icon = icon
        }
    }

    public struct Editable: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case model
            case reasoning
        }

        public var kind: Kind
        /// `nil` writes the turn's `modelId`; otherwise a config option value.
        public var configOptionID: String?
        public var options: [Value]

        public init(kind: Kind, configOptionID: String?, options: [Value]) {
            self.kind = kind
            self.configOptionID = configOptionID
            self.options = options
        }
    }

    public var model: Value?
    public var reasoning: Value?
    public var editable: Editable?

    public init(model: Value?, reasoning: Value?, editable: Editable?) {
        self.model = model
        self.reasoning = reasoning
        self.editable = editable
    }

    public func choosing(_ value: String) -> RunConfigChoice? {
        guard let editable, editable.options.contains(where: { $0.value == value }) else { return nil }
        return RunConfigChoice(configOptionID: editable.configOptionID, value: value)
    }

    public func applying(_ choice: RunConfigChoice?) -> SessionRunConfig {
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
public struct RunConfigChoice: Equatable, Sendable {
    public var configOptionID: String?
    public var value: String

    public init(configOptionID: String?, value: String) {
        self.configOptionID = configOptionID
        self.value = value
    }
}

/// Model and reasoning for a new session's first turn. Both are editable:
/// a new session has no provider context that switching models could discard.
public struct NewSessionRunConfig: Codable, Equatable, Sendable {
    public struct ModelOption: Codable, Equatable, Sendable, Identifiable {
        public var value: String
        public var label: String
        /// Reasoning choices this model accepts.
        public var reasoning: [SessionRunConfig.Value]
        public var id: String { value }
    }

    public struct Model: Codable, Equatable, Sendable {
        /// `nil` writes the turn's `modelId`; otherwise a config option value.
        public var configOptionID: String?
        public var value: String
        public var options: [ModelOption]
    }

    public struct Reasoning: Codable, Equatable, Sendable {
        public var configOptionID: String
        public var value: String?
        /// Used when the agent has no model list to carry per-model choices.
        public var options: [SessionRunConfig.Value]
        /// Capability's preferred value, separate from the inherited turn value.
        public var defaultValue: String? = nil
    }

    public var model: Model?
    public var reasoning: Reasoning?

    public var selectedModel: ModelOption? {
        model.flatMap { model in model.options.first { $0.value == model.value } }
    }

    public var reasoningOptions: [SessionRunConfig.Value] {
        guard let reasoning else { return [] }
        return model == nil ? reasoning.options : selectedModel?.reasoning ?? []
    }

    /// The stored reasoning is kept across model changes and applies only while offered.
    /// Otherwise display and send the capability preference or the first supported value.
    public var selectedReasoning: SessionRunConfig.Value? {
        let options = reasoningOptions
        return options.first { $0.value == reasoning?.value }
            ?? options.first { $0.value == reasoning?.defaultValue }
            ?? options.first
    }

    public mutating func selectModel(_ value: String) {
        guard model?.options.contains(where: { $0.value == value }) == true else { return }
        model?.value = value
    }

    public mutating func selectReasoning(_ value: String) {
        guard reasoningOptions.contains(where: { $0.value == value }) else { return }
        reasoning?.value = value
    }


    /// Model first, so the bridge checks reasoning against the chosen model.
    public var selections: [RunConfigChoice] {
        var choices: [RunConfigChoice] = []
        if let model { choices.append(RunConfigChoice(configOptionID: model.configOptionID, value: model.value)) }
        if let reasoning, let selectedReasoning {
            choices.append(RunConfigChoice(configOptionID: reasoning.configOptionID, value: selectedReasoning.value))
        }
        return choices
    }
}

/// A new session runs on its project's machine with one of that machine's agents.
public struct NewSessionOptions: Codable, Equatable, Sendable {
    public var machineName: String
    /// The chosen agent config. Empty only for a legacy session without one.
    public var agentConfigID: String
    /// Agent configs on the machine, labelled by name.
    public var providers: [SessionRunConfig.Value]
    public var runConfig: NewSessionRunConfig?
    /// Cached options can be displayed while a scoped request refreshes them.
    public var needsRefresh: Bool? = nil

    public init(
        machineName: String,
        agentConfigID: String,
        providers: [SessionRunConfig.Value],
        runConfig: NewSessionRunConfig? = nil,
        needsRefresh: Bool? = nil
    ) {
        self.machineName = machineName
        self.agentConfigID = agentConfigID
        self.providers = providers
        self.runConfig = runConfig
        self.needsRefresh = needsRefresh
    }

    public var provider: SessionRunConfig.Value? {
        providers.first { $0.value == agentConfigID }
    }
}

public struct ConversationUpdate: Equatable, Sendable {
    public var conversation: Conversation
    public var activity: SessionActivity?
    public var syncState: ConversationSyncState
    public var runConfig: SessionRunConfig? = nil
    public var contextWindowUsage: ContextWindowUsage? = nil
    public var lastMessageAt: Double? = nil
    public var sessionTabs: [SessionSummary]? = nil
}

public enum ConversationSyncState: String, Decodable, Sendable {
    case connecting
    case live
}

public struct ConversationPatch: Decodable {
    public let sessionID: String
    public let order: [String]
    public let changed: [ConversationTurn]
    public let permission: PermissionPrompt?
    public var replacesFileChanges: Bool? = nil
    public var replacesSubtasks: Bool? = nil
    public var fileChanges: [ConversationFileChangeGroup]? = nil
    public var latestTurnNumber: Int? = nil
    public var subtasks: [ConversationSubtask]? = nil
    public var subtaskOrder: [ConversationSubtask.ID]? = nil
    public var changedSubtasks: [ConversationSubtask]? = nil
    public var questions: [ConversationQuestionRequest]? = nil
    public var cacheUsage: ConversationCacheUsage? = nil
    public let activity: String
    public let syncState: ConversationSyncState
    public var runConfig: SessionRunConfig? = nil
    public var contextWindowUsage: ContextWindowUsage? = nil
    public var lastMessageAt: Double? = nil
    public var sessionTabs: [SessionSummary]? = nil

    public func applying(to previous: Conversation) throws -> ConversationUpdate {
        guard previous.sessionID == sessionID, Set(order).count == order.count else {
            throw LodyClientError.notConnected
        }
        var turns = Dictionary(uniqueKeysWithValues: previous.turns.map { ($0.id, $0) })
        for turn in changed { turns[turn.id] = turn }
        let ordered = try order.map { id in
            guard let turn = turns[id] else { throw LodyClientError.notConnected }
            return turn
        }
        var updatedSubtasks = replacesSubtasks == true ? subtasks : previous.subtasks
        if let subtaskOrder {
            guard Set(subtaskOrder).count == subtaskOrder.count else { throw LodyClientError.notConnected }
            var tasks = Dictionary((updatedSubtasks ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            for task in changedSubtasks ?? [] { tasks[task.id] = task }
            updatedSubtasks = try subtaskOrder.map { id in
                guard let task = tasks[id] else { throw LodyClientError.notConnected }
                return task
            }
        }
        return ConversationUpdate(
            conversation: Conversation(sessionID: sessionID, turns: ordered, permission: permission,
                                       fileChanges: replacesFileChanges == true ? fileChanges : previous.fileChanges,
                                       latestTurnNumber: latestTurnNumber ?? previous.latestTurnNumber,
                                       subtasks: updatedSubtasks,
                                       questions: questions, cacheUsage: cacheUsage),
            activity: activity == "running" ? .running : .idle, syncState: syncState,
            runConfig: runConfig, contextWindowUsage: contextWindowUsage, lastMessageAt: lastMessageAt, sessionTabs: sessionTabs
        )
    }
}

/// Display data only; credentials remain in Keychain.
public struct SessionCache: Codable, Equatable, Sendable {
    public var account: Account
    public var workspaces: [WorkspaceSummary] = []
    public var selectedWorkspaceID: String?
    public var sessionsByWorkspace: [String: [SessionSummary]] = [:]
    /// Locally observed negative ACKs, scoped by workspace, session, then turn.
    public var rejectedTurnIDsByWorkspace: [String: [String: Set<String>]] = [:]

    private enum CodingKeys: String, CodingKey {
        case account, workspaces, selectedWorkspaceID, sessionsByWorkspace, rejectedTurnIDsByWorkspace
    }
}

extension SessionCache {
    public init(from decoder: Decoder) throws {
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
public struct SessionArchiveResult: Decodable, Sendable {
    public let status: String
    public let sessionIDs: [String]
}


public struct SessionProject: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let rootPath: String
    public let templateSessionID: String

    public init(id: String, name: String, rootPath: String, templateSessionID: String) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.templateSessionID = templateSessionID
    }
}

public struct MachineDirectory: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        public struct ID: Hashable, Sendable {
            public let name: String
            public let absolutePath: String
        }
        // Lody resolves symlinks: distinct rows can share the same canonical path.
        public var id: ID { ID(name: name, absolutePath: absolutePath) }
        public let name: String
        public let absolutePath: String
        public var error: String? = nil
    }
    public let path: String
    public let parentPath: String?
    public var entries: [Entry]
    public let truncated: Bool
    public let nextCursor: String?
}

public enum SessionProjectAction: String, Sendable { case catalog, browse, select }

public struct SessionProjectResult: Codable, Sendable {
    public var projects: [SessionProject]? = nil
    public var directory: MachineDirectory? = nil
    public var project: SessionProject? = nil
}
