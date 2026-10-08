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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MacAttachmentPicker(attachments: $draft.attachments, loading: $draft.isLoadingAttachments)
            TextEditor(text: $draft.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(height: 88)
                .overlay(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text("Message…").foregroundStyle(.tertiary).padding(.leading, 5)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Message")
                .accessibilityIdentifier("message-editor")
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
    @Binding var loading: Bool
    @State private var importing = false
    @State private var error: String?
    @State private var urls: [URL] = []
    @State private var selection = UUID()

    var body: some View {
        HStack {
            Button("Attach images", systemImage: "paperclip") { importing = true }
                .disabled(loading).accessibilityIdentifier("attach-images")
            if loading { ProgressView().controlSize(.small) }
            ScrollView(.horizontal) {
                HStack {
                    ForEach(attachments) { attachment in
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                            Text(attachment.fileName).lineLimit(1)
                            Button("Remove \(attachment.fileName)", systemImage: "xmark") {
                                attachments.removeAll { $0.id == attachment.id }
                            }.labelStyle(.iconOnly).buttonStyle(.plain)
                        }
                        .font(.caption).padding(6).background(.quaternary, in: Capsule())
                    }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .gif, .webP], allowsMultipleSelection: true) { result in
            do {
                urls = try result.get()
                loading = !urls.isEmpty
                selection = UUID()
            } catch { self.error = "Could not open the selected images." }
        }
        .task(id: selection) {
            guard !urls.isEmpty else { return }
            loading = true
            defer { loading = false }
            error = nil
            do {
                let selected = urls
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try selected.map { url in
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                        guard let size = values.fileSize, size <= 5 * 1024 * 1024 else {
                            throw AttachmentError.invalid("Images must be 5 MB or smaller.")
                        }
                        return try ComposerAttachment(fileName: url.lastPathComponent,
                            mimeType: values.contentType?.preferredMIMEType ?? "application/octet-stream",
                            data: Data(contentsOf: url), isImage: true)
                    }
                }.value
                try Task.checkCancellation()
                attachments.append(contentsOf: loaded)
            } catch is CancellationError { return }
            catch { self.error = error.localizedDescription }
        }
        .onDisappear { loading = false }
    }
}
