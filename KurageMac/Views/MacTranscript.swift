import SwiftUI
import MarkdownView
import KurageCore

struct MacTranscript: View {
    let model: AppModel
    let sessionID: String
    let turns: [ConversationTurn]
    @Binding var atBottom: Bool
    let scrollRequest: Int
    let isAwake: Bool
    @State private var hasOpened = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(turns) { turn in
                        MacTurnView(model: model, sessionID: sessionID, turn: turn, isAwake: isAwake)
                            .id(turn.id)
                    }
                    Color.clear.frame(height: 1).id("transcript-bottom")
                }
                .frame(maxWidth: 800)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("transcript")
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .alignment)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 48
            } action: { _, bottom in atBottom = bottom }
            .onChange(of: turns) { old, new in
                guard !new.isEmpty else { return }
                if !hasOpened || old.isEmpty || atBottom {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
                hasOpened = true
            }
            .onChange(of: scrollRequest) { _, _ in
                atBottom = true
                proxy.scrollTo("transcript-bottom", anchor: .bottom)
            }
            .overlay(alignment: .bottomTrailing) {
                if !atBottom {
                    Button("Latest", systemImage: "arrow.down") {
                        atBottom = true
                        proxy.scrollTo("transcript-bottom", anchor: .bottom)
                    }
                    .buttonStyle(.bordered).padding(16)
                    .accessibilityIdentifier("scroll-latest")
                }
            }
        }
    }
}

private struct MacTurnView: View {
    let model: AppModel
    let sessionID: String
    let turn: ConversationTurn
    let isAwake: Bool

    var body: some View {
        VStack(alignment: turn.author == .user ? .trailing : .leading, spacing: 10) {
            Text(turn.author == .user ? "You" : "Agent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let work = turn.displayedWork {
                let insertion = min(max(work.insertionIndex, 0), turn.content.count)
                MacMessageParts(model: model, sessionID: sessionID, parts: Array(turn.content.prefix(insertion)),
                                isUser: turn.author == .user, isAwake: isAwake)
                DisclosureGroup(work.title) {
                    MacMessageParts(model: model, sessionID: sessionID, parts: work.parts, isUser: false, isAwake: isAwake)
                }.foregroundStyle(.secondary)
                MacMessageParts(model: model, sessionID: sessionID, parts: Array(turn.content.dropFirst(insertion)),
                                isUser: turn.author == .user, isAwake: isAwake)
            } else {
                MacMessageParts(model: model, sessionID: sessionID, parts: turn.content,
                                isUser: turn.author == .user, isAwake: isAwake)
            }
        }
        .frame(maxWidth: .infinity, alignment: turn.author == .user ? .trailing : .leading)
        .accessibilityIdentifier("turn-\(turn.id)")
    }
}

private struct MacMessageParts: View {
    let model: AppModel
    let sessionID: String
    let parts: [ConversationPart]
    let isUser: Bool
    let isAwake: Bool

    // Projected text slots have no event IDs. Keep their slot identity while the
    // text grows; images, errors, files and activities retain their domain IDs.
    private struct Block: Identifiable {
        let id: String
        let part: ConversationPart
    }

    private var blocks: [Block] {
        var occurrences: [String: Int] = [:]
        return parts.map { part in
            let key: String
            switch part {
            case .text: key = "text"
            case .image(let image): key = "image:\(image.id)"
            case .file(let file): key = "file:\(file.fileID)"
            case .activity(let activity): key = "activity:\(activity.id)"
            case .error(let error): key = "error:\(error.id)"
            }
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            return Block(id: "\(key):\(occurrence)", part: part)
        }
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 10) {
            ForEach(blocks) { block in
                VStack(alignment: .leading) {
                    switch block.part {
                    case .text(let text):
                        if isUser {
                            Text(text).textSelection(.enabled).padding(12)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                        } else {
                            MarkdownView(text).textSelection(.enabled)
                        }
                    case .image(let image):
                        MacSessionImage(model: model, sessionID: sessionID, image: image, isAwake: isAwake)
                    case .file(let file):
                        Label(file.fileName, systemImage: "doc").foregroundStyle(.secondary)
                    case .activity(let activity):
                        Text(activity.summary).font(.callout).foregroundStyle(.secondary)
                    case .error(let error):
                        Text(error.message ?? String(localized: error.title)).textSelection(.enabled)
                            .foregroundStyle(.orange).padding(12)
                            .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

private struct MacSessionImage: View {
    let model: AppModel
    let sessionID: String
    let image: ConversationImage
    let isAwake: Bool
    @State private var data: Data?
    @State private var failed = false
    @State private var expanded = false
    @State private var retry = 0

    private struct LoadKey: Equatable {
        let awake: Bool
        let expanded: Bool
        let retry: Int
    }

    var body: some View {
        VStack {
            if let data, let bitmap = NSImage(data: data) {
                Button { expanded.toggle() } label: {
                    Image(nsImage: bitmap).resizable().scaledToFit()
                        .frame(maxWidth: expanded ? 760 : 320, maxHeight: expanded ? 700 : 240)
                }
                .buttonStyle(.plain).accessibilityLabel(image.accessibilityName)
                .help(expanded ? "Show thumbnail" : "Show full image")
            } else if failed {
                Button("Retry image", systemImage: "photo") { retry += 1 }
            } else { ProgressView().frame(width: 180, height: 120) }
        }
        .task(id: LoadKey(awake: isAwake, expanded: expanded, retry: retry)) {
            guard isAwake else { return }
            failed = false
            do {
                let result = try await model.loadSessionImage(image, conversationSessionID: sessionID,
                                                              variant: expanded ? .original : .inline)
                try Task.checkCancellation()
                data = result
            } catch is CancellationError { return }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}
