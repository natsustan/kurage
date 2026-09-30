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

extension Conversation {
    /// Keep local thumbnails across subsequent stream patches without adding
    /// them to the Codable protocol projection or the disk session cache.
    func preservingPreviews(from previous: Conversation?) -> Conversation {
        guard let previous else { return self }
        var previews: [String: ConversationImage] = [:]
        for turn in previous.turns {
            for part in turn.parts {
                if case .image(let image) = part, image.localPreviewData != nil {
                    previews[image.id] = image
                }
            }
        }
        guard !previews.isEmpty else { return self }
        var conversation = self
        conversation.turns = turns.map { turn in
            var turn = turn
            turn.parts = turn.parts.map { part in
                guard case .image(var image) = part, let previousImage = previews[image.id] else { return part }
                image.localPreviewData = previousImage.localPreviewData
                image.localPreviewScopeID = previousImage.localPreviewScopeID
                return .image(image)
            }
            return turn
        }
        return conversation
    }
}
