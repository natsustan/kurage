import AppKit
import ImageIO
import UniformTypeIdentifiers
import KurageCore

struct MacAttachmentSource: Identifiable, Sendable {
    enum Content: Sendable {
        case file(URL)
        case image(Data, String)
    }

    let id = UUID()
    let content: Content

    @MainActor
    static func read(from pasteboard: NSPasteboard) -> [Self] {
        // Finder also offers text and image previews. File URLs must win to avoid duplicates.
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { return urls.map { Self(content: .file($0)) } }
        return (pasteboard.pasteboardItems ?? []).compactMap { item in
            for (type, mime) in [(NSPasteboard.PasteboardType.png, "image/png"), (.tiff, "image/tiff")] {
                if let data = item.data(forType: type) { return Self(content: .image(data, mime)) }
            }
            return nil
        }
    }

    @concurrent
    func load() async throws -> ComposerAttachment {
        try Task.checkCancellation()
        let name: String
        let mime: String
        let data: Data
        switch content {
        case .file(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw AttachmentError.invalid("Choose files, not folders.") }
            guard let size = values.fileSize, size <= 16 * 1024 * 1024 else {
                throw AttachmentError.invalid("Files must be 16 MB or smaller.")
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: 16 * 1024 * 1024 + 1) ?? Data()
            name = url.lastPathComponent
            mime = values.contentType?.preferredMIMEType ?? "application/octet-stream"
        case .image(let bytes, let type):
            data = bytes
            mime = type
            name = "Pasted image.\(type == "image/png" ? "png" : "tiff")"
        }
        try Task.checkCancellation()
        if mime.hasPrefix("image/") {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048
                  ] as CFDictionary) else { throw AttachmentError.invalid("Could not read the image.") }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw AttachmentError.invalid("Could not prepare the image.")
            }
            CGImageDestinationAddImage(destination, preview, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw AttachmentError.invalid("Could not prepare the image.") }
            try Task.checkCancellation()
            let keepOriginal = ConversationImage.displayableMIMETypes.contains(mime) && data.count <= 5 * 1024 * 1024
            return try ComposerAttachment(fileName: keepOriginal ? name : (name as NSString).deletingPathExtension + ".jpg",
                mimeType: keepOriginal ? mime : "image/jpeg", data: keepOriginal ? data : output as Data,
                isImage: true, thumbnailData: output as Data)
        }
        return try ComposerAttachment(fileName: name, mimeType: mime, data: data, isImage: false)
    }
}
