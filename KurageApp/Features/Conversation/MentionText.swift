import SwiftUI
import UIKit

/// Presentation only: the underlying draft and the sent protocol text remain intact.
enum MentionText {
    struct Reference {
        let range: NSRange
        let label: String
        let symbol: String
    }

    private static let sessionPattern = try! NSRegularExpression(
        pattern: #"\[@((?:\\.|[^\]\\])+)]\(session://([A-Za-z0-9_-]+)\)"#
    )
    private static let skillPattern = try! NSRegularExpression(
        pattern: #"(?<!\S)use /([^\s\[\]]+) \[Skill Path\]\(((?:\\.|[^)\\\n])+)\)"#
    )

    /// Only the two explicit Lody reference forms are decorated. Ordinary
    /// Markdown, paths, and unselected @/$ words remain ordinary text.
    static func references(in text: String) -> [Reference] {
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        let sessions = sessionPattern.matches(in: text, range: range).map {
            Reference(range: $0.range, label: unescape(source.substring(with: $0.range(at: 1))),
                      symbol: "bubble.left.and.text.bubble.right")
        }
        let skills = skillPattern.matches(in: text, range: range).map {
            Reference(range: $0.range, label: source.substring(with: $0.range(at: 1)), symbol: "sparkles")
        }
        var end = 0
        return (sessions + skills).sorted { $0.range.location < $1.range.location }.filter {
            guard $0.range.location >= end else { return false }
            end = NSMaxRange($0.range)
            return true
        }
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var escaped = false
        for character in value {
            if escaped { result.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else { result.append(character) }
        }
        if escaped { result.append("\\") }
        return result
    }

    static func decorate(_ text: String, ranges: [ComposerMentionState.Range], font: UIFont, color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.label])
        for range in ranges {
            guard range.start >= 0, range.end <= result.length, range.end > range.start,
                  (text as NSString).substring(with: NSRange(location: range.start, length: range.end - range.start)) == range.token else { continue }
            let symbol: String
            switch range.kind {
            case .session: symbol = "bubble.left.and.text.bubble.right"
            case .skill: symbol = "sparkles"
            }
            let tokenRange = NSRange(location: range.start, length: range.end - range.start)
            result.addAttributes([.foregroundColor: color, .font: font], range: tokenRange)
            let prefix = (text as NSString).substring(with: NSRange(location: range.start, length: 1))
            result.replaceCharacters(in: NSRange(location: range.start, length: 1),
                                     with: icon(symbol, original: prefix, font: font, color: color))
        }
        return result
    }

    static func message(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let source = text as NSString
        let result = NSMutableAttributedString(string: "")
        var position = 0
        for reference in references(in: text) {
            result.append(NSAttributedString(string: source.substring(with: NSRange(
                location: position, length: reference.range.location - position
            )), attributes: [.font: font, .foregroundColor: UIColor.label]))
            let chip = NSMutableAttributedString(attributedString: icon(reference.symbol, original: "", font: font, color: color))
            chip.append(NSAttributedString(string: reference.label, attributes: [.font: font, .foregroundColor: color]))
            // Copying any selection that includes this complete reference keeps
            // its original target, while the screen shows its human label.
            chip.addAttribute(originalReferenceKey, value: source.substring(with: reference.range),
                              range: NSRange(location: 0, length: chip.length))
            result.append(chip)
            position = NSMaxRange(reference.range)
        }
        result.append(NSAttributedString(string: source.substring(from: position),
                                         attributes: [.font: font, .foregroundColor: UIColor.label]))
        return result
    }

    private static let originalReferenceKey = NSAttributedString.Key("KurageOriginalReference")

    static func originalText(_ attributed: NSAttributedString) -> String {
        var result = ""
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            if let original = attributes[originalReferenceKey] as? String {
                // Adjacent runs can have different font/attachment attributes.
                // Emit the original only at the beginning of the reference.
                var effective = NSRange()
                attributed.attribute(originalReferenceKey, at: range.location, longestEffectiveRange: &effective,
                                     in: NSRange(location: 0, length: attributed.length))
                if range.location == effective.location { result += original }
            } else if let attachment = attributes[.attachment] as? MentionIconAttachment {
                result += attachment.original
            } else {
                result += (attributed.string as NSString).substring(with: range)
            }
        }
        return result
    }

    private static func icon(_ symbol: String, original: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let attachment = MentionIconAttachment(original: original)
        let size = font.pointSize
        let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.85, weight: .medium))
        attachment.image = image?.withTintColor(color, renderingMode: .alwaysOriginal)
        let ratio = (image?.size.width ?? size) / max(1, image?.size.height ?? size)
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - size) / 2, width: size * ratio + 4, height: size)
        return NSAttributedString(attachment: attachment)
    }
}

private final class MentionIconAttachment: NSTextAttachment {
    let original: String

    init(original: String) {
        self.original = original
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

/// UTF-16 positions stay unchanged: only the one-character trigger becomes an
/// icon attachment. Native selection, dictation, and IME composition stay in UIKit.
struct MentionEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: TextSelection?
    @Binding var isFocused: Bool
    let ranges: [ComposerMentionState.Range]
    let isEnabled: Bool
    let identifier: String
    let accessibilityLabel: LocalizedStringResource
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = MentionEditorTextView()
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection)
        if view.markedTextRange == nil {
            if coordinator.renderedText != text || coordinator.renderedRanges != ranges || coordinator.renderedFont != font ||
                coordinator.renderedStyle != view.traitCollection.userInterfaceStyle {
                let attributed = MentionText.decorate(text, ranges: ranges, font: font, color: view.tintColor)
                let previousSelection = view.selectedRange
                view.attributedText = attributed
                let restored = NSRange(location: min(previousSelection.location, attributed.length),
                                       length: min(previousSelection.length, max(0, attributed.length - previousSelection.location)))
                if view.selectedRange != restored { view.selectedRange = restored }
                coordinator.renderedText = text
                coordinator.renderedRanges = ranges
                coordinator.renderedFont = font
                coordinator.renderedStyle = view.traitCollection.userInterfaceStyle
            }
            if let selection, case .selection(let range) = selection.indices,
               (range.lowerBound == text.endIndex || text.indices.contains(range.lowerBound)),
               (range.upperBound == text.endIndex || text.indices.contains(range.upperBound)) {
                let start = range.lowerBound.utf16Offset(in: text)
                let end = range.upperBound.utf16Offset(in: text)
                if start <= end, end <= view.attributedText.length {
                    let desired = NSRange(location: start, length: end - start)
                    if view.selectedRange != desired { view.selectedRange = desired }
                }
            }
        }
        view.typingAttributes = [.font: font, .foregroundColor: UIColor.label]
        // Changing isEditable while this is the first responder can reenter
        // SwiftUI's responder graph during updateUIView. Gate edits in the
        // delegate instead, preserving the keyboard during a send.
        (view as? MentionEditorTextView)?.isInputEnabled = isEnabled
        view.accessibilityIdentifier = identifier
        var label = accessibilityLabel
        label.locale = locale
        view.accessibilityLabel = String(localized: label)
        view.accessibilityValue = text
        if isFocused && isEnabled && !view.isFirstResponder { view.becomeFirstResponder() }
        else if !isFocused && view.isFirstResponder { view.resignFirstResponder() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: uiView.traitCollection)
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: min(max(font.lineHeight, ceil(size.height)), ceil(font.lineHeight * 5)))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MentionEditor
        var isUpdating = false
        var renderedText: String?
        var renderedRanges: [ComposerMentionState.Range] = []
        var renderedFont: UIFont?
        var renderedStyle: UIUserInterfaceStyle = .unspecified

        init(_ parent: MentionEditor) { self.parent = parent }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            parent.isEnabled
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            let edited = MentionText.originalText(textView.attributedText)
            parent.text = edited
            // Atomic deletion can expand the edit and supply its own caret.
            if parent.text == edited { updateSelection(textView) }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating else { return }
            updateSelection(textView)
        }

        private func updateSelection(_ view: UITextView) {
            let range = view.selectedRange
            let text = parent.text
            guard NSMaxRange(range) <= text.utf16.count else { return }
            let indices = String.Index(utf16Offset: range.location, in: text)..<String.Index(utf16Offset: NSMaxRange(range), in: text)
            if let selection = parent.selection, case .selection(let previous) = selection.indices, previous == indices { return }
            parent.selection = TextSelection(range: indices)
        }

        func textViewDidBeginEditing(_ textView: UITextView) { if !isUpdating { parent.isFocused = true } }
        func textViewDidEndEditing(_ textView: UITextView) { if !isUpdating { parent.isFocused = false } }
    }
}

private final class MentionEditorTextView: UITextView {
    var isInputEnabled = true

    override var accessibilityTraits: UIAccessibilityTraits {
        get { isInputEnabled ? super.accessibilityTraits : super.accessibilityTraits.union(.notEnabled) }
        set { super.accessibilityTraits = newValue }
    }
    override func copy(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        UIPasteboard.general.string = MentionText.originalText(attributedText.attributedSubstring(from: selectedRange))
    }

    override func paste(_ sender: Any?) {
        guard isInputEnabled, let value = UIPasteboard.general.string, let range = selectedTextRange else { return }
        replace(range, withText: value)
    }
}
