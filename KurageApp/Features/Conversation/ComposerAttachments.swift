import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import ImageIO

struct ComposerAttachments: View {
    @Binding var attachments: [ComposerAttachment]
    @Binding var pending: [PendingComposerAttachment]
    private var isLoading: Bool { !pending.isEmpty }
    @Binding var error: String?
    let presentation: ComposerPresentation
    let disabled: Bool
    var showsSummary = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var importID: UUID?
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        @Bindable var presentation = presentation
        ZStack {
            Menu {
                Button("Files", systemImage: "paperclip") { presentation.showsFiles = true }
                    .accessibilityIdentifier("attach-files")
                Button("Camera", systemImage: "camera") {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        error = "Camera is unavailable on this device."; return
                    }
                    let generation = presentation.dismissGeneration
                    importTask = Task {
                        let allowed = await AVCaptureDevice.requestAccess(for: .video)
                        guard !Task.isCancelled, presentation.dismissGeneration == generation else { return }
                        if allowed { presentation.showsCamera = true }
                        else { error = "Allow camera access in Settings to take a photo." }
                    }
                }
                .accessibilityIdentifier("attach-camera")
                Button("Photos", systemImage: "photo.on.rectangle") { presentation.showsPhotos = true }
                    .accessibilityIdentifier("attach-photos")
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: ComposerControlMetrics.iconSize))
                    .foregroundStyle(Color.primary)
                    .frame(width: ComposerControlMetrics.hitSize, height: ComposerControlMetrics.hitSize)
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if showsSummary && isLoading {
                            ProgressView().controlSize(.mini)
                                .allowsHitTesting(false)
                        } else if showsSummary && !attachments.isEmpty {
                            Text(attachments.count, format: .number)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 4)
                                .background(Color.accentColor, in: Capsule())
                                .allowsHitTesting(false)
                        }
                    }
            }
            .tint(Color.primary)
            .menuOrder(.fixed)
            .disabled(disabled || isLoading || attachments.count >= 8)
            .accessibilityLabel("Add attachment")
            .accessibilityValue(isLoading ? "Loading attachments" : attachments.isEmpty ? "" : "\(attachments.count) attachments")
            .accessibilityIdentifier("add-attachment")
        }
        .photosPicker(isPresented: $presentation.showsPhotos, selection: $photos,
                      maxSelectionCount: max(1, 8 - attachments.count), selectionBehavior: .ordered,
                      matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: photos) { _, selection in
            guard !selection.isEmpty else { return }
            beginImport(placeholders: selection.map { _ in PendingComposerAttachment(fileName: "Photo", isImage: true) }) {
                var result: [ComposerAttachment] = []
                for photo in selection {
                    try Task.checkCancellation()
                    guard let data = try await photo.loadTransferable(type: Data.self) else {
                        throw AttachmentError.invalid("Could not load the selected photo.")
                    }
                    result.append(try await Self.image(data))
                }
                return result
            }
        }
        .fileImporter(isPresented: $presentation.showsFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                guard urls.count + attachments.count <= 8 else { error = "Select up to 8 attachments."; return }
                beginImport(placeholders: urls.map { PendingComposerAttachment(fileName: $0.lastPathComponent,
                    isImage: UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true) }) {
                    try await Self.files(urls)
                }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $presentation.showsCamera) {
            CameraCapture { image in
                presentation.showsCamera = false
                if let image {
                    beginImport(placeholders: [PendingComposerAttachment(fileName: "Photo", isImage: true)]) {
                        [try await Self.cameraImage(image)]
                    }
                }
            }.ignoresSafeArea()
        }
        .onDisappear { importTask?.cancel(); importID = nil; pending = []; photos = [] }
    }

    private func beginImport(placeholders: [PendingComposerAttachment], _ load: @escaping @Sendable () async throws -> [ComposerAttachment]) {
        importTask?.cancel()
        let id = UUID()
        importID = id
        pending = placeholders
        importTask = Task {
            defer {
                if importID == id { pending = []; photos = []; importTask = nil; importID = nil }
            }
            do {
                let imported = try await load()
                try Task.checkCancellation()
                guard attachments.count + imported.count <= 8 else { throw AttachmentError.invalid("Select up to 8 attachments.") }
                attachments.append(contentsOf: imported)
            } catch {
                if !Task.isCancelled, importID == id { self.error = error.localizedDescription }
            }
        }
    }

    @concurrent private static func files(_ urls: [URL]) async throws -> [ComposerAttachment] {
        var result: [ComposerAttachment] = []
        for url in urls {
            try Task.checkCancellation()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 16 * 1024 * 1024 else { throw AttachmentError.invalid("Files must be 16 MB or smaller.") }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 16 * 1024 * 1024 + 1) ?? Data()
            guard data.count <= 16 * 1024 * 1024 else { throw AttachmentError.invalid("Files must be 16 MB or smaller.") }
            let type = UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .image) == true,
               CGImageSourceCreateWithData(data as CFData, nil) != nil {
                result.append(try await Self.image(data, name: url.lastPathComponent))
                continue
            }
            result.append(try ComposerAttachment(fileName: url.lastPathComponent,
                mimeType: type?.preferredMIMEType ?? "application/octet-stream", data: data, isImage: false))
        }
        try Task.checkCancellation()
        return result
    }

    @concurrent static func cameraImage(_ image: UIImage) async throws -> ComposerAttachment {
        try Task.checkCancellation()
        guard image.size.width > 0, image.size.height > 0 else {
            throw AttachmentError.invalid("Could not prepare this image.")
        }
        let scale = min(1, 2048 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        try Task.checkCancellation()
        guard let data = resized.jpegData(compressionQuality: 0.85) else {
            throw AttachmentError.invalid("Could not prepare this image.")
        }
        return try await Self.image(data)
    }

    @concurrent private static func image(_ data: Data, name: String = "Photo.jpg") async throws -> ComposerAttachment {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) else { throw AttachmentError.invalid("Could not read this image.") }
        let type = UTType(identifier as String)
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 360
        ] as CFDictionary).flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.8) }
        try Task.checkCancellation()
        if let mime = type?.preferredMIMEType, ["image/jpeg", "image/png", "image/webp", "image/gif"].contains(mime), data.count <= 5 * 1024 * 1024 {
            return try ComposerAttachment(fileName: name == "Photo.jpg" ? "Photo.\(type?.preferredFilenameExtension ?? "jpg")" : name,
                                          mimeType: mime, data: data, isImage: true, thumbnailData: thumbnail)
        }
        // HEIC and oversized camera photos become bounded JPEGs; no library write is needed.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048
        ] as CFDictionary), let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else {
            throw AttachmentError.invalid("Could not prepare this image.")
        }
        try Task.checkCancellation()
        return try ComposerAttachment(fileName: (name as NSString).deletingPathExtension + ".jpg", mimeType: "image/jpeg", data: jpeg, isImage: true, thumbnailData: thumbnail)
    }
}

/// Selection placeholders stay separate from validated, sendable attachment bytes.
struct PendingComposerAttachment: Identifiable {
    let id = UUID()
    let fileName: String
    let isImage: Bool
}

struct ComposerAttachmentStrip: View {
    @Binding var attachments: [ComposerAttachment]
    let pending: [PendingComposerAttachment]
    let disabled: Bool
    let onPreview: (ComposerAttachment) -> Void

    private var containsImage: Bool {
        attachments.contains(where: \.isImage) || pending.contains(where: \.isImage)
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ComposerAttachmentPreview(
                        fileName: attachment.fileName,
                        isImage: attachment.isImage,
                        thumbnailData: attachment.thumbnailData,
                        isLoading: disabled,
                        onRemove: { attachments.removeAll { $0.id == attachment.id } },
                        onPreview: attachment.isImage ? { onPreview(attachment) } : nil
                    )
                }
                ForEach(pending) { item in
                    ComposerAttachmentPreview(fileName: item.fileName, isImage: item.isImage,
                                              thumbnailData: nil, isLoading: true, onRemove: nil)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
        }
        .frame(height: containsImage ? 122 : nil)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("composer-attachments")
    }
}

private struct ComposerAttachmentPreview: View {
    let fileName: String
    let isImage: Bool
    let thumbnailData: Data?
    let isLoading: Bool
    let onRemove: (() -> Void)?
    var onPreview: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            if isImage {
                Button {
                    onPreview?()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.07))
                        if let thumbnailData, let image = UIImage(data: thumbnailData) {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(.rect(cornerRadius: 20))
                    .overlay {
                        if isLoading {
                            RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.2))
                            ProgressView().tint(thumbnailData == nil ? Color.primary : .white)
                                .accessibilityLabel("Loading \(fileName)")
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(onPreview == nil)
                .accessibilityLabel(fileName)
                .accessibilityHint("Shows the full image")
                .accessibilityIdentifier("composer-image-thumbnail")
                .overlay(alignment: .topTrailing) { removeButton }
            } else {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(isPDF ? Color.red : Color.secondary)
                        if isLoading {
                            ProgressView().tint(.white)
                                .accessibilityLabel("Loading \(fileName)")
                        } else {
                            Image(systemName: isPDF ? "doc.richtext" : "doc.fill")
                                .font(.system(size: 19, weight: .medium)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 32, height: 36)
                    Text(fileName).font(.subheadline).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 160, alignment: .leading)
                    removeButton
                }
                .padding(.leading, 6)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 18))
            }
        }
    }

    private var isPDF: Bool { (fileName as NSString).pathExtension.lowercased() == "pdf" }

    @ViewBuilder private var removeButton: some View {
        if let onRemove {
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.black.opacity(isImage ? 0.5 : 0.35), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel("Remove \(fileName)")
        }
    }
}

private struct CameraCapture: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }
    }
}
