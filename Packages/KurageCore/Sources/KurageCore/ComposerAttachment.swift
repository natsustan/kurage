import Foundation

/// Only selected items are retained, in memory, until the draft is sent or discarded.
public struct ComposerAttachment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fileName: String
    public let mimeType: String
    public let data: Data
    public let isImage: Bool
    public let thumbnailData: Data?

    public init(id: UUID = UUID(), fileName: String, mimeType: String, data: Data, isImage: Bool, thumbnailData: Data? = nil) throws {
        guard !fileName.isEmpty, !mimeType.contains("\r"), !mimeType.contains("\n"),
              !isImage || ConversationImage.displayableMIMETypes.contains(mimeType) else {
            throw AttachmentError.invalid("Unsupported attachment type.")
        }
        guard !data.isEmpty else { throw AttachmentError.invalid("The selected file is empty.") }
        let limit = isImage ? 5 * 1024 * 1024 : 16 * 1024 * 1024
        guard data.count <= limit else {
            throw AttachmentError.invalid(isImage ? "Images must be 5 MB or smaller." : "Files must be 16 MB or smaller.")
        }
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
        self.isImage = isImage
        self.thumbnailData = thumbnailData
    }
}

public enum AttachmentError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}

/// Lody's image/file input block, also stored verbatim in history.
public struct UploadedAttachment: Codable, Equatable, Sendable {
    public var type: String
    public var imageId: String?
    public var fileId: String?
    public var fileName: String
    public var mimeType: String
    public var sizeBytes: Int
    public var width: Int?
    public var height: Int?
    public var sha256: String?
    public var textPreview: Bool?
    public var transport: String?
    public var uploadedAt: Double?

    public func bridgeValue() throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] else {
            throw AttachmentError.invalid("Invalid attachment metadata.")
        }
        return value
    }
}
