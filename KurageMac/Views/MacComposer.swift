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
    @State private var measuredHeight: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var editorHeight: CGFloat { min(160, max(22, measuredHeight)) }

    private var sendEnabled: Bool {
        canSend && !draft.isLoadingAttachments &&
            (!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.attachments.isEmpty)
    }

    var body: some View {
        MacComposerCard {
            VStack(alignment: .leading, spacing: 0) {
                MacAttachmentPicker(attachments: $draft.attachments, pending: $draft.pendingAttachments, importing: $importing,
                                    showsButton: false)
                    .padding(.horizontal, 10)
                    .padding(.top, draft.attachments.isEmpty && draft.pendingAttachments.isEmpty ? 0 : 10)
                MacMessageEditor(text: $draft.text, accessibilityLabel: "Message",
                                 accessibilityIdentifier: "message-editor", onContentHeight: { measuredHeight = $0 }) {
                    draft.pendingAttachments.append(contentsOf: $0)
                }
                .frame(height: editorHeight)
                .overlay(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text("Message…")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
                toolbar
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: editorHeight)
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            Button { importing = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MacComposerIconButtonStyle())
            .help("Attach images or files, or paste with ⌘V")
            .disabled(draft.isLoadingAttachments)
            .accessibilityLabel("Attach files")
            .accessibilityIdentifier("attach-images")
            Spacer(minLength: 8)
            if isRunning {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canStop)
                .accessibilityLabel("Stop")
                .help("Stop the reply")
            }
            runConfigControl
            Button(action: onSend) {
                MacComposerSendMark(enabled: sendEnabled)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!sendEnabled)
            .accessibilityLabel(isRunning ? "Steer" : "Send")
            .help(isRunning ? "Steer the reply (⌘Return)" : "Send (⌘Return)")
            .accessibilityIdentifier("send-message")
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var runConfigControl: some View {
        if let config = runConfig {
            let summary = [config.model?.label, config.reasoning?.label].compactMap { $0 }.joined(separator: " · ")
            if let editable = config.editable {
                let selected = editable.kind == .model ? config.model?.value : config.reasoning?.value
                Menu {
                    ForEach(editable.options) { option in
                        Button { onChoose(option.value) } label: {
                            if option.value == selected {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    MacComposerMenuLabel(title: summary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .frame(maxWidth: 280)
                .layoutPriority(-1)
                .accessibilityIdentifier("run-config")
                .help("Applies to the next message")
            } else if !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }
        }
    }
}

struct MacComposerCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content()
            .background(Color(nsColor: .textBackgroundColor), in: shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }
            .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }
}

struct MacComposerSendMark: View {
    var enabled: Bool

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(enabled ? Color(nsColor: .textBackgroundColor) : Color.secondary)
            .frame(width: 32, height: 32)
            .background(enabled ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Circle())
    }
}

private struct MacComposerMenuLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 32)
        .contentShape(Rectangle())
    }
}

private struct MacComposerIconButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(configuration.isPressed || hovering ? Color.primary.opacity(0.06) : Color.clear, in: Circle())
            .onHover { hovering = $0 }
    }
}

struct MacAttachmentPicker: View {
    @Binding var attachments: [ComposerAttachment]
    @Binding var pending: [MacAttachmentSource]
    @Binding var importing: Bool
    var showsButton = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsButton {
                Button("Attach files", systemImage: "plus") { importing = true }
                    .labelStyle(.iconOnly)
                    .help("Attach images or files, or paste with ⌘V")
                    .disabled(!pending.isEmpty).accessibilityIdentifier("attach-images")
            }
            if !pending.isEmpty || !attachments.isEmpty {
                HStack(spacing: 6) {
                    if !pending.isEmpty { ProgressView().controlSize(.small) }
                    if !attachments.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(attachments) { attachment in
                                    HStack(spacing: 6) {
                                        if let data = attachment.thumbnailData, let image = NSImage(data: data) {
                                            Image(nsImage: image).resizable().scaledToFill()
                                                .frame(width: 28, height: 28)
                                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        } else {
                                            Image(systemName: attachment.isImage ? "photo" : "doc")
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(attachment.fileName).lineLimit(1)
                                        Button("Remove \(attachment.fileName)", systemImage: "xmark") {
                                            attachments.removeAll { $0.id == attachment.id }
                                        }
                                        .labelStyle(.iconOnly)
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                    }
                                    .font(.caption)
                                    .padding(.leading, 4)
                                    .padding(.trailing, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.05), in: Capsule())
                                }
                            }
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
