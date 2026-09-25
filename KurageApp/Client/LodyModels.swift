import Foundation

struct Account: Codable, Equatable, Sendable {
    var email: String
    var id: String? = nil
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

enum ConversationPart: Equatable, Sendable {
    case text(String)
    case image(ConversationImage)
}

struct ConversationTurn: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var author: TurnAuthor
    var text: String
    var parts: [ConversationPart]

    init(id: String, author: TurnAuthor, text: String, parts: [ConversationPart] = []) {
        self.id = id
        self.author = author
        self.text = text
        self.parts = parts
    }

    /// Ordered chat content. Text-only turns written before image parts still render their text.
    var content: [ConversationPart] {
        let visible = parts.compactMap { part -> ConversationPart? in
            switch part {
            case .text(let text):
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .text(text)
            case .image(let image):
                return image.isDisplayable ? .image(image) : nil
            }
        }
        if !visible.isEmpty { return visible }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.text(text)]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        author = try container.decode(TurnAuthor.self, forKey: .author)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        parts = try container.decodeIfPresent([PartBox].self, forKey: .parts)?.compactMap(\.part) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(author, forKey: .author)
        try container.encode(text, forKey: .text)
        try container.encode(parts.map(PartBox.init), forKey: .parts)
    }

    private enum CodingKeys: String, CodingKey {
        case id, author, text, parts
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
        case "image":
            if let image = try? ConversationImage(from: decoder), image.isDisplayable {
                part = .image(image)
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
        case .image(let image):
            try container.encode("image", forKey: .type)
            try container.encode(image.imageID, forKey: .imageID)
            try container.encodeIfPresent(image.mimeType, forKey: .mimeType)
            try container.encodeIfPresent(image.fileName, forKey: .fileName)
            try container.encodeIfPresent(image.storageSessionID, forKey: .storageSessionID)
            try container.encodeIfPresent(image.width, forKey: .width)
            try container.encodeIfPresent(image.height, forKey: .height)
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

struct Conversation: Codable, Equatable, Sendable {
    var sessionID: SessionSummary.ID
    var turns: [ConversationTurn]
    var permission: PermissionPrompt?
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
    case deliveryUnconfirmed
    case previousSendPending(String)
    case sendSuperseded
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

struct ConversationUpdate: Equatable, Sendable {
    var conversation: Conversation
    var activity: SessionActivity?
    var syncState: ConversationSyncState
    var runConfig: SessionRunConfig? = nil
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
    let activity: String
    let syncState: ConversationSyncState
    var runConfig: SessionRunConfig? = nil

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
            conversation: Conversation(sessionID: sessionID, turns: ordered, permission: permission),
            activity: activity == "running" ? .running : .idle, syncState: syncState,
            runConfig: runConfig
        )
    }
}

/// Display data only; credentials remain in Keychain.
struct SessionCache: Codable, Equatable, Sendable {
    var account: Account
    var workspaces: [WorkspaceSummary] = []
    var selectedWorkspaceID: String?
    var sessionsByWorkspace: [String: [SessionSummary]] = [:]
}

/// Confirmed archive targets use document IDs, matching the active session list.
struct SessionArchiveResult: Decodable, Sendable {
    let status: String
    let sessionIDs: [String]
}
