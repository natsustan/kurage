import AppKit
import SwiftUI

/// Keep AppKit at the text-system boundary so Paste works through the responder chain.
struct MacMessageEditor: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    var initiallyFocused = false
    let onPasteAttachments: ([MacAttachmentSource]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let editor = MacPasteTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.textColor = .textColor
        editor.textContainerInset = NSSize(width: 4, height: 6)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.string = text
        editor.onPasteAttachments = onPasteAttachments
        editor.focusOnAttach = initiallyFocused
        editor.setAccessibilityLabel(accessibilityLabel)
        editor.setAccessibilityIdentifier(accessibilityIdentifier)
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? MacPasteTextView else { return }
        editor.onPasteAttachments = onPasteAttachments
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacMessageEditor
        init(_ parent: MacMessageEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
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
