import SwiftUI
import UniformTypeIdentifiers
import KurageCore

struct MacComposer: View {
    @Binding var draft: MacWindowState.Draft
    var runConfig: RunConfigMenu?
    @Binding var showsRunConfig: Bool
    var isLoadingModels = false
    let canSend: Bool
    let isRunning: Bool
    let canStop: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onChoose: (String) -> Void
    @State private var importing = false
    @State private var measuredHeight: CGFloat = 22
    @State private var suppressRunConfigOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var editorHeight: CGFloat { min(160, max(22, measuredHeight)) }

    private var sendEnabled: Bool {
        canSend && !draft.isLoadingAttachments &&
            (!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.attachments.isEmpty)
    }

    /// Stop takes the send slot while a reply is running and there is nothing to steer.
    private var showsStop: Bool { isRunning && !hasSteerDraft }

    private var hasSteerDraft: Bool {
        guard canSend else { return false }
        return draft.isLoadingAttachments || !draft.attachments.isEmpty ||
            !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            runConfigControl
            if showsStop {
                Button(action: onStop) {
                    MacComposerSendMark(enabled: canStop, systemName: "stop.fill", symbolSize: 11)
                }
                .buttonStyle(.plain)
                .disabled(!canStop)
                .accessibilityLabel("Stop")
                .help("Stop the reply")
                .accessibilityIdentifier("pause-session")
            } else {
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
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var runConfigControl: some View {
        if let menu = runConfig {
            let summary = [menu.modelLabel, menu.reasoningLabel].compactMap { $0 }.joined(separator: " · ")
            if !summary.isEmpty, canAdjust(menu) {
                Button {
                    if showsRunConfig {
                        showsRunConfig = false
                    } else if !suppressRunConfigOpen {
                        showsRunConfig = true
                    }
                } label: {
                    MacComposerMenuLabel(title: summary, active: showsRunConfig)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(-1)
                .accessibilityLabel(menu.accessibilitySummary)
                .accessibilityIdentifier("run-config")
                .help("Applies to the next message")
                .background {
                    MacPopoverAnchor(isPresented: $showsRunConfig, onClose: {
                        suppressRunConfigOpen = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(200))
                            suppressRunConfigOpen = false
                        }
                    }) {
                        MacRunConfigPopover(menu: menu, isLoadingModels: isLoadingModels) { value in
                            onChoose(value)
                            showsRunConfig = false
                        }
                    }
                }
            } else if !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
        }
    }

    private func canAdjust(_ menu: RunConfigMenu) -> Bool {
        if menu.sections.contains(where: { $0.kind == .reasoning && $0.options.count > 1 }) { return true }
        if menu.sections.contains(where: { $0.kind == .model && $0.options.count > 1 }) { return true }
        return menu.modelShortcuts.contains(where: \.isEnabled)
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
    var systemName = "arrow.up"
    var symbolSize: CGFloat = 13

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(enabled ? Color(nsColor: .textBackgroundColor) : Color.secondary)
            .frame(width: 32, height: 32)
            .background(enabled ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Circle())
    }
}

private struct MacComposerMenuLabel: View {
    let title: String
    var active = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 168)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .bold))
                .layoutPriority(1)
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background(active || hovering ? Color.primary.opacity(0.06) : Color.clear, in: Capsule())
        .contentShape(Capsule())
        .onHover { hovering = $0 }
    }
}

/// Model shortcuts sit above the reasoning choices. An existing session keeps
/// its model locked when the agent exposes reasoning, matching the iOS panel.
private struct MacRunConfigPopover: View {
    let menu: RunConfigMenu
    var isLoadingModels: Bool
    let onChoose: (String) -> Void

    private struct Row: Identifiable {
        let id: String
        let title: String
        let icon: String?
        let selected: Bool
        let enabled: Bool
        let value: String
        let identifier: String
    }

    private var modelRows: [Row] {
        let section = menu.sections.first { $0.kind == .model }
        let editable = Set(section?.options.map(\.value) ?? [])
        var rows: [Row] = []
        for shortcut in menu.modelShortcuts {
            let value = shortcut.model.modelID
            let id = "\(shortcut.model.agentConfigID)-\(value)"
            guard !rows.contains(where: { $0.id == id }) else { continue }
            rows.append(Row(
                id: id, title: shortcut.model.modelName, icon: shortcut.model.icon,
                selected: shortcut.isSelected || section?.selection == value,
                enabled: section != nil && editable.contains(value), value: value,
                identifier: "model-shortcut-\(shortcut.model.agentConfigID)-\(value)"))
        }
        if let section {
            let icon = menu.modelShortcuts.first { $0.isSelected }?.model.icon ?? menu.modelShortcuts.first?.model.icon
            for option in section.options where !rows.contains(where: { $0.value == option.value }) {
                rows.append(Row(
                    id: "option-\(option.value)", title: option.label, icon: icon,
                    selected: option.value == section.selection, enabled: true, value: option.value,
                    identifier: "model-option-\(option.value)"))
            }
        }
        return rows
    }

    private var reasoning: RunConfigMenu.Section? {
        menu.sections.first { $0.kind == .reasoning && !$0.options.isEmpty }
    }

    var body: some View {
        let rows = VStack(alignment: .leading, spacing: 1) {
            if !modelRows.isEmpty {
                sectionTitle("Model")
                ForEach(modelRows) { row in
                    choiceRow(title: row.title, icon: row.icon, reserveIcon: false, selected: row.selected,
                              enabled: row.enabled, identifier: row.identifier) { onChoose(row.value) }
                }
            }
            if let reasoning {
                if !modelRows.isEmpty { Divider().padding(.vertical, 4).padding(.horizontal, 8) }
                sectionTitle("Reasoning")
                ForEach(reasoning.options) { option in
                    choiceRow(title: option.label, icon: nil, reserveIcon: modelRows.contains { $0.icon != nil },
                              selected: option.value == reasoning.selection,
                              enabled: reasoning.options.count > 1,
                              identifier: "run-config-reasoning-\(option.value)") { onChoose(option.value) }
                }
            }
            if isLoadingModels {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .accessibilityLabel("Loading models")
            }
        }
        .padding(4)
        .frame(width: 228)
        Group {
            if modelRows.count + (reasoning?.options.count ?? 0) > 12 {
                ScrollView { rows }.frame(height: 420)
            } else {
                rows.fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private func choiceRow(title: String, icon: String?, reserveIcon: Bool, selected: Bool, enabled: Bool,
                           identifier: String, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack(spacing: 8) {
                if let icon {
                    MacProviderIcon(icon: icon)
                } else if reserveIcon {
                    Color.clear.frame(width: 16, height: 16)
                }
                Text(title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(MacRunConfigRowButtonStyle())
        .disabled(!enabled)
        .opacity(enabled || selected ? 1 : 0.45)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

private struct MacProviderIcon: View {
    let icon: String?

    private var asset: String? {
        guard let icon, ["codex", "claude", "gemini", "deepseek", "kimi", "grok", "minimax", "glm", "mimo",
                         "pi", "devin", "amp", "cursor", "opencode", "copilot"].contains(icon) else { return nil }
        return "provider-\(icon)"
    }

    var body: some View {
        Group {
            if let asset {
                Image(asset).resizable().scaledToFit()
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

private struct MacRunConfigRowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed || hovering ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { hovering = $0 }
    }
}

/// Anchors an NSPopover to the run-config button and keeps it above that button,
/// next to Send. SwiftUI's popover edge is ignored when the composer sits low in the window.
private struct MacPopoverAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented, onClose: onClose) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.anchor = view
        coordinator.isPresented = $isPresented
        coordinator.onClose = onClose
        coordinator.install(content())
        // Show after the click that opened the popover finishes. A semitransient
        // popover presented inside that click closes again immediately.
        coordinator.schedulePresentation()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        var isPresented: Binding<Bool>
        var onClose: () -> Void
        weak var anchor: NSView?
        let popover: NSPopover
        var hosting: NSHostingController<Content>?
        private var presentationQueued = false

        @MainActor
        init(isPresented: Binding<Bool>, onClose: @escaping () -> Void) {
            self.isPresented = isPresented
            self.onClose = onClose
            let popover = NSPopover()
            self.popover = popover
            super.init()
            popover.behavior = .semitransient
            popover.animates = true
            popover.delegate = self
        }

        func install(_ content: Content) {
            let hosting = self.hosting ?? {
                let hosting = NSHostingController(rootView: content)
                hosting.sizingOptions = .preferredContentSize
                self.hosting = hosting
                popover.contentViewController = hosting
                return hosting
            }()
            hosting.rootView = content
        }

        func schedulePresentation() {
            guard !presentationQueued else { return }
            presentationQueued = true
            Task { @MainActor in
                self.presentationQueued = false
                self.applyPresentation()
            }
        }

        func applyPresentation() {
            guard let anchor, let hosting else { return }
            let fitted = hosting.sizeThatFits(in: CGSize(width: 228, height: 480))
            popover.contentSize = CGSize(width: 228, height: max(1, fitted.height))
            guard anchor.window != nil else { return }
            if isPresented.wrappedValue {
                guard !popover.isShown else { return }
                let rect = anchor.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 1, height: 1) : anchor.bounds
                popover.show(relativeTo: rect, of: anchor, preferredEdge: .maxY)
            } else if popover.isShown {
                popover.performClose(nil)
            }
        }

        func popoverDidClose(_ notification: Notification) {
            if isPresented.wrappedValue { isPresented.wrappedValue = false }
            onClose()
        }
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
