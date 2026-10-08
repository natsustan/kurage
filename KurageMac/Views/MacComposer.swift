import SwiftUI
import UniformTypeIdentifiers
import KurageCore

struct MacComposer: View {
    @Binding var draft: MacWindowState.Draft
    var runConfig: SessionRunConfig?
    let canSend: Bool
    let isRunning: Bool
    let canStop: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onChoose: (String) -> Void
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MacAttachmentPicker(attachments: $draft.attachments, pending: $draft.pendingAttachments, importing: $importing)
            MacMessageEditor(text: $draft.text, accessibilityLabel: "Message", accessibilityIdentifier: "message-editor") {
                draft.pendingAttachments.append(contentsOf: $0)
            }
            .frame(height: 88)
            .overlay(alignment: .topLeading) {
                if draft.text.isEmpty {
                    Text("Message…").foregroundStyle(.tertiary).padding(.leading, 9).padding(.top, 6)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                if let config = runConfig {
                    if let editable = config.editable {
                        Menu {
                            ForEach(editable.options) { option in
                                Button(option.label) { onChoose(option.value) }
                            }
                        } label: {
                            Text([config.model?.label, config.reasoning?.label].compactMap { $0 }.joined(separator: " · "))
                        }
                        .accessibilityIdentifier("run-config")
                        .help("Applies to the next message")
                    } else {
                        Text([config.model?.label, config.reasoning?.label].compactMap { $0 }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isRunning {
                    Button("Stop", systemImage: "stop.fill", action: onStop).disabled(!canStop)
                }
                Button(isRunning ? "Steer" : "Send", systemImage: "arrow.up", action: onSend)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSend || draft.isLoadingAttachments || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.attachments.isEmpty)
                    .accessibilityIdentifier("send-message")
            }
            .controlSize(.regular)
        }
        .padding(16)
    }
}

struct MacAttachmentPicker: View {
    @Binding var attachments: [ComposerAttachment]
    @Binding var pending: [MacAttachmentSource]
    @Binding var importing: Bool
    var showsButton = true
    @State private var error: String?

    var body: some View {
        HStack {
            if showsButton {
                Button("Attach files", systemImage: "plus") { importing = true }
                    .labelStyle(.iconOnly)
                    .help("Attach images or files, or paste with ⌘V")
                    .disabled(!pending.isEmpty).accessibilityIdentifier("attach-images")
            }
            if !pending.isEmpty { ProgressView().controlSize(.small) }
            if !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(attachments) { attachment in
                            HStack(spacing: 4) {
                                if let data = attachment.thumbnailData, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(width: 44, height: 44)
                                } else {
                                    Image(systemName: attachment.isImage ? "photo" : "doc")
                                }
                                Text(attachment.fileName).lineLimit(1)
                                Button("Remove \(attachment.fileName)", systemImage: "xmark") {
                                    attachments.removeAll { $0.id == attachment.id }
                                }.labelStyle(.iconOnly).buttonStyle(.plain)
                            }
                            .font(.caption).padding(6).background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            do {
                pending.append(contentsOf: try result.get().map { MacAttachmentSource(content: .file($0)) })
            } catch { self.error = "Could not open the selected files." }
        }
        .task(id: pending.map(\.id)) {
            let selected = pending
            guard !selected.isEmpty else { return }
            error = nil
            do {
                guard attachments.count + selected.count <= 8 else {
                    throw AttachmentError.invalid("Attach up to 8 items per message.")
                }
                var loaded: [ComposerAttachment] = []
                for source in selected { loaded.append(try await source.load()) }
                try Task.checkCancellation()
                guard pending.map(\.id) == selected.map(\.id) else { return }
                attachments.append(contentsOf: loaded)
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, pending.map(\.id) == selected.map(\.id) else { return }
                self.error = error.localizedDescription
            }
            pending = []
        }
    }
}
