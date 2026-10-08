import AppKit
import SwiftUI

/// Keep AppKit at the text-system boundary so Paste works through the responder chain.
struct MacMessageEditor: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    var initiallyFocused = false
    var onContentHeight: ((CGFloat) -> Void)? = nil
    let onPasteAttachments: ([MacAttachmentSource]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = MacEditorScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.focusRingType = .none
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let editor = MacPasteTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.focusRingType = .none
        editor.font = .systemFont(ofSize: 15)
        editor.textColor = .textColor
        editor.textContainerInset = NSSize(width: 0, height: 1)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.string = text
        editor.onPasteAttachments = onPasteAttachments
        editor.focusOnAttach = initiallyFocused
        editor.setAccessibilityLabel(accessibilityLabel)
        editor.setAccessibilityIdentifier(accessibilityIdentifier)
        scroll.documentView = editor
        context.coordinator.scrollView = scroll
        scroll.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.reportHeight()
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.scrollView = scroll
        guard let editor = scroll.documentView as? MacPasteTextView else { return }
        editor.onPasteAttachments = onPasteAttachments
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
        context.coordinator.reportHeight()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacMessageEditor
        weak var scrollView: NSScrollView?
        private var reportedHeight: CGFloat = 0
        init(_ parent: MacMessageEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            reportHeight()
        }

        func reportHeight() {
            guard let scroll = scrollView, scroll.bounds.width > 2,
                  let editor = scroll.documentView as? NSTextView,
                  let layout = editor.layoutManager,
                  let container = editor.textContainer else { return }
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            let insets = editor.textContainerInset.height * 2
            let line = ceil((editor.font ?? .systemFont(ofSize: 15)).boundingRectForFont.height)
            let height = max(line + insets, ceil(used.height + insets))
            guard abs(height - reportedHeight) > 0.5 else { return }
            reportedHeight = height
            let callback = parent.onContentHeight
            DispatchQueue.main.async { callback?(height) }
        }
    }
}

/// Reports content height after the text wraps to the current card width.
final class MacEditorScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

final class MacPasteTextView: NSTextView {
    var onPasteAttachments: (([MacAttachmentSource]) -> Void)?
    var focusOnAttach = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusOnAttach, let window {
            focusOnAttach = false
            window.makeFirstResponder(self)
        }
    }

    override func paste(_ sender: Any?) {
        let sources = MacAttachmentSource.read(from: .general)
        if !sources.isEmpty, let onPasteAttachments {
            onPasteAttachments(sources)
        } else {
            super.paste(sender)
        }
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), isEditable,
           (NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || NSPasteboard.general.availableType(from: [.png, .tiff]) != nil) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
