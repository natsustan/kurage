import SwiftUI
import UIKit

enum ConversationBlock: Equatable, Identifiable {
    case text(id: String, text: String)
    case images(id: String, images: [ConversationImage])

    var id: String {
        switch self {
        case .text(let id, _), .images(let id, _): id
        }
    }
}

/// User images sit above the typed text. Agent images stay in source order, with
/// consecutive images gathered into one row.
func conversationBlocks(author: TurnAuthor, content: [ConversationPart]) -> [ConversationBlock] {
    if author == .user {
        var images: [ConversationImage] = []
        var texts: [String] = []
        for part in content {
            switch part {
            case .text(let text): texts.append(text)
            case .image(let image): images.append(image)
            }
        }
        var blocks: [ConversationBlock] = []
        if !images.isEmpty { blocks.append(.images(id: "images", images: images)) }
        if !texts.isEmpty { blocks.append(.text(id: "text", text: texts.joined(separator: "\n\n"))) }
        return blocks
    }

    var blocks: [ConversationBlock] = []
    for part in content {
        switch part {
        case .text(let text):
            blocks.append(.text(id: "text-\(blocks.count)", text: text))
        case .image(let image):
            if case .images(let id, var images) = blocks.last {
                images.append(image)
                blocks[blocks.count - 1] = .images(id: id, images: images)
            } else {
                blocks.append(.images(id: "images-\(blocks.count)", images: [image]))
            }
        }
    }
    return blocks
}

struct ConversationImageGroup: View {
    let images: [ConversationImage]
    let alignment: HorizontalAlignment
    let loadImage: @MainActor (ConversationImage, SessionImageVariant) async throws -> Data
    let onPreview: (ConversationImage) -> Void

    var body: some View {
        if images.count == 1, let image = images.first {
            ConversationImageTile(
                image: image,
                variant: .inline,
                size: ConversationImageFrame.single(width: image.width, height: image.height),
                fills: false,
                loadImage: loadImage,
                onPreview: onPreview
            )
            .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
        } else {
            VStack(alignment: alignment, spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        if alignment == .trailing { Spacer(minLength: 0) }
                        ForEach(Array(row.enumerated()), id: \.offset) { _, image in
                            ConversationImageTile(
                                image: image,
                                variant: .square,
                                size: CGSize(width: 112, height: 112),
                                fills: true,
                                loadImage: loadImage,
                                onPreview: onPreview
                            )
                        }
                        if alignment == .leading { Spacer(minLength: 0) }
                    }
                }
            }
        }
    }

    private var rows: [[ConversationImage]] {
        stride(from: 0, to: images.count, by: 3).map { start in
            Array(images[start..<min(start + 3, images.count)])
        }
    }
}

struct ConversationImagePreview: View {
    let image: ConversationImage
    let loadImage: @MainActor (ConversationImage, SessionImageVariant) async throws -> Data
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: UIImage?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let loaded {
                    Image(uiImage: loaded)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(16)
                        .accessibilityLabel(image.accessibilityName)
                        .accessibilityIdentifier("conversation-image-preview")
                } else if failed {
                    ContentUnavailableView(
                        "Could not load image",
                        systemImage: "photo",
                        description: Text(image.accessibilityName)
                    )
                    .foregroundStyle(.white)
                } else {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("Loading image")
                }
            }
            .navigationTitle(image.accessibilityName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("conversation-image-close")
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { await loadOriginal() }
    }

    private func loadOriginal() async {
        do {
            let data = try await loadImage(image, .original)
            guard !Task.isCancelled, let uiImage = UIImage(data: data) else {
                failed = true
                return
            }
            loaded = uiImage
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

enum ConversationImageFrame {
    static func single(width: Int?, height: Int?) -> CGSize {
        let maxWidth: CGFloat = 300
        let maxHeight: CGFloat = 220
        guard let width, let height, width > 0, height > 0 else {
            return CGSize(width: maxWidth, height: 168)
        }
        let scale = min(maxWidth / CGFloat(width), maxHeight / CGFloat(height))
        return CGSize(
            width: max(44, (CGFloat(width) * scale).rounded()),
            height: max(44, (CGFloat(height) * scale).rounded())
        )
    }
}

private struct ConversationImageTile: View {
    let image: ConversationImage
    let variant: SessionImageVariant
    let size: CGSize
    let fills: Bool
    let loadImage: @MainActor (ConversationImage, SessionImageVariant) async throws -> Data
    let onPreview: (ConversationImage) -> Void
    @State private var loaded: UIImage?
    @State private var failed = false

    var body: some View {
        Button {
            onPreview(image)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let loaded {
                    Image(uiImage: loaded)
                        .resizable()
                        .aspectRatio(contentMode: fills ? .fill : .fit)
                } else if failed {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(image.accessibilityName)
        .accessibilityHint("Shows the full image")
        .accessibilityIdentifier("conversation-image-\(image.imageID)")
        .task(id: "\(image.id)-\(variant)") { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        failed = false
        loaded = nil
        do {
            let data = try await loadImage(image, variant)
            guard !Task.isCancelled, let uiImage = UIImage(data: data) else {
                failed = true
                return
            }
            loaded = uiImage
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
