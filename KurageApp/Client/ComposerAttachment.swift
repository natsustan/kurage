import Foundation

/// Only selected items are retained, in memory, until the draft is sent or discarded.
struct ComposerAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let fileName: String
    let mimeType: String
    let data: Data
    let isImage: Bool
    let thumbnailData: Data?

    init(id: UUID = UUID(), fileName: String, mimeType: String, data: Data, isImage: Bool, thumbnailData: Data? = nil) throws {
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

enum AttachmentError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}

/// Lody's image/file input block, also stored verbatim in history.
struct UploadedAttachment: Codable, Equatable, Sendable {
    var type: String
    var imageId: String?
    var fileId: String?
    var fileName: String
    var mimeType: String
    var sizeBytes: Int
    var width: Int?
    var height: Int?
    var sha256: String?
    var textPreview: Bool?
    var transport: String?
    var uploadedAt: Double?

    func bridgeValue() throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] else {
            throw AttachmentError.invalid("Invalid attachment metadata.")
        }
        return value
    }
}
