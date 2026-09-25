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
            ConversationImageGrid(trailing: alignment == .trailing) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    ConversationImageTile(
                        image: image,
                        variant: .square,
                        size: nil,
                        fills: true,
                        loadImage: loadImage,
                        onPreview: onPreview
                    )
                }
            }
        }
    }

}

/// Up to three square thumbnails, sized by the actual chat content width.
private struct ConversationImageGrid: Layout {
    let trailing: Bool
    private let spacing: CGFloat = 8

    private func metrics(width: CGFloat?, count: Int) -> (columns: Int, side: CGFloat, width: CGFloat) {
        let columns = min(3, max(1, count))
        let idealWidth = CGFloat(columns) * 112 + CGFloat(columns - 1) * spacing
        let width = max(0, width ?? idealWidth)
        let side = min(112, max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)))
        return (columns, side, width)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let grid = metrics(width: proposal.width, count: subviews.count)
        let rows = (subviews.count + grid.columns - 1) / grid.columns
        return CGSize(width: grid.width, height: CGFloat(rows) * grid.side + CGFloat(max(0, rows - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grid = metrics(width: bounds.width, count: subviews.count)
        for (index, view) in subviews.enumerated() {
            let row = index / grid.columns
            let column = index % grid.columns
            let count = min(grid.columns, subviews.count - row * grid.columns)
            let rowWidth = CGFloat(count) * grid.side + CGFloat(count - 1) * spacing
            let start = trailing ? bounds.maxX - rowWidth : bounds.minX
            view.place(
                at: CGPoint(x: start + CGFloat(column) * (grid.side + spacing),
                            y: bounds.minY + CGFloat(row) * (grid.side + spacing)),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: grid.side, height: grid.side)
            )
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
        .preferredColorScheme(.dark)
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
    let size: CGSize?
    let fills: Bool
    let loadImage: @MainActor (ConversationImage, SessionImageVariant) async throws -> Data
    let onPreview: (ConversationImage) -> Void
    @State private var loaded: UIImage?
    @State private var failed = false

    var body: some View {
        Button {
            onPreview(image)
        } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay {
                    Group {
                        if let loaded {
                            Image(uiImage: loaded)
                                .resizable()
                                .aspectRatio(contentMode: fills ? .fill : .fit)
                        } else if failed {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .frame(width: size?.width, height: size?.height)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(.rect)
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
