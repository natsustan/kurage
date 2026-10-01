import Foundation

/// Delivery belongs to a message, independently of the next composer draft.
enum MessageDelivery: Equatable, Sendable {
    case sending
    case unconfirmed
    case failed(String)
    case superseded
    case sent
}

/// Identity and context exist before a first message reaches the service.
struct OutgoingSessionStart {
    let request: SessionTabStart
    let summary: SessionSummary
    let templateSessionID: SessionSummary.ID
    let stagedAt = Date()
    var isConfirmed = false

    var pending: PendingSessionStart {
        PendingSessionStart(id: request.sessionID, projectID: summary.projectID ?? "",
                            templateSessionID: templateSessionID, text: request.text,
                            attachments: request.attachments, turnID: request.turnID)
    }
}

struct OutgoingMessage: Identifiable, Equatable {
    let id: ConversationTurn.ID
    let text: String
    let composerText: String
    let mentions: ComposerMentionState
    let attachments: [ComposerAttachment]
    let runConfig: RunConfigChoice?
    var previewScopeID: UUID? = nil
    var delivery: MessageDelivery = .sending
    var canRetry = true

    var turn: ConversationTurn {
        var parts = attachments.map { attachment -> ConversationPart in
            if attachment.isImage {
                return .image(ConversationImage(
                    imageID: attachment.id.uuidString.lowercased(), mimeType: attachment.mimeType,
                    fileName: attachment.fileName, localPreviewData: attachment.thumbnailData ?? attachment.data,
                    localOriginalData: attachment.data, localPreviewScopeID: previewScopeID
                ))
            }
            return .file(ConversationFile(fileID: attachment.id.uuidString.lowercased(),
                                          fileName: attachment.fileName, sizeBytes: attachment.data.count))
        }
        if !text.isEmpty { parts.append(.text(text)) }
        var turn = ConversationTurn(id: id, author: .user, text: text, parts: parts)
        turn.delivery = delivery == .sent ? nil : delivery
        return turn
    }

    /// The protocol preserves attachment order within each user turn. Transfer
    /// only thumbnail bytes to received images; originals leave with the outbox.
    func preservingPreviews(in turn: ConversationTurn) -> ConversationTurn {
        var turn = turn
        let images = attachments.filter(\.isImage)
        var index = 0
        turn.parts = turn.parts.map { part in
            guard case .image(var image) = part else { return part }
            defer { index += 1 }
            guard index < images.count else { return part }
            let attachment = images[index]
            image.localPreviewData = attachment.thumbnailData ?? attachment.data
            image.localPreviewScopeID = previewScopeID
            return .image(image)
        }
        return turn
    }
}

/// Confirmed thumbnails have their own budget. Stored conversation snapshots
/// contain only references, so evicting a preview actually releases its bytes.
struct SessionImagePreviewCache {
    private struct Key: Hashable {
        let workspaceID: String
        let sessionID: String
        let imageID: String
    }

    private struct Preview {
        let data: Data
        let scopeID: UUID?
    }

    private let maxCount: Int
    private let maxBytes: Int
    private var previews: [Key: Preview] = [:]
    private var order: [Key] = []
    private var byteCount = 0

    init(maxCount: Int = 24, maxBytes: Int = 8 * 1024 * 1024) {
        self.maxCount = maxCount
        self.maxBytes = maxBytes
    }

    mutating func store(_ turn: ConversationTurn, sessionID: String, workspaceID: String) {
        for part in turn.parts {
            guard case .image(let image) = part, let data = image.localPreviewData else { continue }
            let key = Key(workspaceID: workspaceID, sessionID: image.storageSessionID ?? sessionID, imageID: image.imageID)
            remove(key)
            guard maxCount > 0, data.count <= maxBytes else { continue }
            previews[key] = Preview(data: data, scopeID: image.localPreviewScopeID)
            order.append(key)
            byteCount += data.count
            while order.count > maxCount || byteCount > maxBytes {
                remove(order[0])
            }
        }
    }

    func applying(to conversation: Conversation, workspaceID: String) -> Conversation {
        conversation.mappingImages { image in
            var image = image
            let key = Key(workspaceID: workspaceID, sessionID: image.storageSessionID ?? conversation.sessionID,
                          imageID: image.imageID)
            image.localPreviewData = previews[key]?.data
            image.localPreviewScopeID = previews[key]?.scopeID
            image.localOriginalData = nil
            return image
        }
    }

    mutating func retainWorkspaces(_ workspaceIDs: Set<String>) {
        for key in order where !workspaceIDs.contains(key.workspaceID) { remove(key) }
    }

    mutating func removeSessions(_ sessionIDs: Set<String>, workspaceID: String) {
        for key in order where key.workspaceID == workspaceID && sessionIDs.contains(key.sessionID) { remove(key) }
    }

    private mutating func remove(_ key: Key) {
        if let previous = previews.removeValue(forKey: key) { byteCount -= previous.data.count }
        order.removeAll { $0 == key }
    }
}

extension Conversation {
    func removingLocalImageData() -> Conversation {
        mappingImages { image in
            var image = image
            image.localPreviewData = nil
            image.localOriginalData = nil
            image.localPreviewScopeID = nil
            return image
        }
    }

    fileprivate func mappingImages(_ transform: (ConversationImage) -> ConversationImage) -> Conversation {
        var conversation = self
        for turnIndex in turns.indices {
            for partIndex in turns[turnIndex].parts.indices {
                guard case .image(let image) = turns[turnIndex].parts[partIndex] else { continue }
                let updated = transform(image)
                if updated != image { conversation.turns[turnIndex].parts[partIndex] = .image(updated) }
            }
        }
        return conversation
    }
}
