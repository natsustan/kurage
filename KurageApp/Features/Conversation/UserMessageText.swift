import SwiftUI
import UIKit
import KurageCore

/// Starts with a bubble menu, then hands selection and its handles to UIKit.
struct UserMessageText: UIViewRepresentable {
    let text: String
    @AppStorage(AppAccent.storageKey) private var accent: AppAccent = .black

    func makeUIView(context: Context) -> UserMessageTextView {
        UserMessageTextView()
    }

    func updateUIView(_ view: UserMessageTextView, context: Context) {
        view.backgroundColor = accent.userMessageBackgroundColor
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection)
        if view.originalText != text || view.renderedFont != font ||
            view.renderedStyle != view.traitCollection.userInterfaceStyle || view.renderedAccent != accent {
            view.endSelection()
            view.originalText = text
            view.renderedFont = font
            view.renderedStyle = view.traitCollection.userInterfaceStyle
            view.renderedAccent = accent
            let foregroundColor = accent.userMessageForegroundColor
            view.attributedText = MentionText.message(text, font: font, color: foregroundColor, textColor: foregroundColor)
        }
        view.accessibilityLabel = view.attributedText.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UserMessageTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let inset = uiView.textContainerInset.left + uiView.textContainerInset.right
        let textBounds = uiView.attributedText.boundingRect(
            with: CGSize(width: max(1, width - inset), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        )
        let bubbleWidth = min(width, ceil(textBounds.width) + inset)
        let size = uiView.sizeThatFits(CGSize(width: bubbleWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: bubbleWidth, height: ceil(size.height))
    }

    static func dismantleUIView(_ view: UserMessageTextView, coordinator: ()) {
        view.endSelection()
    }
}

final class UserMessageTextView: UITextView, UIContextMenuInteractionDelegate, UITextViewDelegate {
    var originalText = ""
    var renderedFont: UIFont?
    var renderedStyle: UIUserInterfaceStyle = .unspecified
    var renderedAccent: AppAccent?
    private var selectsAfterMenu = false
    private var isSelectingAll = false
    private let selectionMenu = UIEditMenuInteraction(delegate: nil)

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isSelectable = false
        isScrollEnabled = false
        delegate = self
        adjustsFontForContentSizeCategory = true
        textContainerInset = UIEdgeInsets(top: 12, left: 15, bottom: 12, right: 15)
        textContainer.lineFragmentPadding = 0
        textColor = .label
        layer.cornerRadius = 20
        accessibilityHint = "Your message"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Copy") { [weak self] _ in
                guard let self else { return false }
                if isSelectable {
                    copy(nil)
                } else {
                    copyMessage()
                }
                return true
            },
            UIAccessibilityCustomAction(name: "Select") { [weak self] _ in
                self?.beginSelection()
                return true
            }
        ]
        addInteraction(UIContextMenuInteraction(delegate: self))
        addInteraction(selectionMenu)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard !isSelectable, !text.isEmpty else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                    self?.copyMessage()
                },
                UIAction(title: "Select", image: UIImage(systemName: "selection.pin.in.out")) { [weak self] _ in
                    self?.selectsAfterMenu = true
                }
            ])
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willEndFor configuration: UIContextMenuConfiguration,
                                animator: (any UIContextMenuInteractionAnimating)?) {
        // Wait for the preview to return to the transcript before showing handles.
        // UIKit may deliver the action after willEnd, so check at completion.
        if let animator {
            animator.addCompletion { [weak self] in self?.selectAfterMenuIfNeeded() }
        } else {
            DispatchQueue.main.async { [weak self] in self?.selectAfterMenuIfNeeded() }
        }
    }

    private func selectAfterMenuIfNeeded() {
        guard selectsAfterMenu else { return }
        selectsAfterMenu = false
        beginSelection()
    }

    private func copyMessage() {
        UIPasteboard.general.string = originalText
    }

    override func copy(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        if selectedRange == NSRange(location: 0, length: attributedText.length) {
            copyMessage()
        } else {
            UIPasteboard.general.string = MentionText.originalText(attributedText.attributedSubstring(from: selectedRange))
        }
    }

    private func beginSelection() {
        guard window != nil, !text.isEmpty else { return }
        isSelectingAll = true
        defer { isSelectingAll = false }
        isSelectable = true
        becomeFirstResponder()
        selectAll(nil)
        if let range = selectedTextRange {
            let rect = firstRect(for: range)
            selectionMenu.presentEditMenu(with: UIEditMenuConfiguration(
                identifier: nil, sourcePoint: CGPoint(x: rect.midX, y: rect.midY)
            ))
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isSelectingAll, isSelectable, isFirstResponder,
              selectedTextRange?.isEmpty != false else { return }
        // A tap that clears the selection returns the bubble to its initial menu.
        endSelection()
    }

    func endSelection() {
        selectionMenu.dismissMenu()
        _ = resignFirstResponder()
        isSelectable = false
        selectedTextRange = nil
        selectsAfterMenu = false
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            selectionMenu.dismissMenu()
            isSelectable = false
            selectedTextRange = nil
        }
        return resigned
    }
}
