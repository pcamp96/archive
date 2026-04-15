import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String

    let displayMode: MarkdownDisplayMode
    var onEndEditing: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            selectedText: $selectedText,
            displayMode: displayMode,
            onEndEditing: onEndEditing
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.string = text
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.smartInsertDeleteEnabled = false

        context.coordinator.applyPresentation(to: textView)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.displayMode = displayMode
        context.coordinator.onEndEditing = onEndEditing

        if textView.string != text {
            textView.string = text
            context.coordinator.applyPresentation(to: textView)
        } else if context.coordinator.lastDisplayMode != displayMode {
            context.coordinator.applyPresentation(to: textView)
        }

        context.coordinator.updateSelection(in: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedText: String

        var displayMode: MarkdownDisplayMode
        var onEndEditing: () -> Void
        var lastDisplayMode: MarkdownDisplayMode?

        private var isApplyingPresentation = false

        init(
            text: Binding<String>,
            selectedText: Binding<String>,
            displayMode: MarkdownDisplayMode,
            onEndEditing: @escaping () -> Void
        ) {
            self._text = text
            self._selectedText = selectedText
            self.displayMode = displayMode
            self.onEndEditing = onEndEditing
        }

        @MainActor
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            applyPresentation(to: textView)
            updateSelection(in: textView)
        }

        @MainActor
        func textDidEndEditing(_ notification: Notification) {
            onEndEditing()
        }

        @MainActor
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateSelection(in: textView)
        }

        @MainActor
        func updateSelection(in textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.location != NSNotFound,
                  let stringRange = Range(range, in: textView.string) else {
                selectedText = ""
                return
            }
            selectedText = String(textView.string[stringRange])
        }

        @MainActor
        func applyPresentation(to textView: NSTextView) {
            guard isApplyingPresentation == false,
                  let textStorage = textView.textStorage else {
                return
            }

            isApplyingPresentation = true
            defer { isApplyingPresentation = false }

            let currentSelection = clampedSelection(textView.selectedRange(), maxLength: textStorage.length)
            let attributed = MarkdownPresentationBuilder.attributedString(for: textView.string, mode: displayMode)
            textStorage.setAttributedString(attributed)
            textView.typingAttributes = MarkdownPresentationBuilder.typingAttributes(for: displayMode)
            textView.setSelectedRange(currentSelection)
            lastDisplayMode = displayMode
        }

        private func clampedSelection(_ selection: NSRange, maxLength: Int) -> NSRange {
            guard maxLength > 0 else { return NSRange(location: 0, length: 0) }
            let location = min(selection.location, maxLength)
            let length = min(selection.length, maxLength - location)
            return NSRange(location: location, length: length)
        }
    }
}

private enum MarkdownPresentationBuilder {
    static func attributedString(for text: String, mode: MarkdownDisplayMode) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes(for: mode))

        guard mode != .markdownOnly else {
            return attributed
        }

        applyLineStyling(to: attributed, mode: mode)
        applyInlineStyling(to: attributed, mode: mode)
        return attributed
    }

    static func typingAttributes(for mode: MarkdownDisplayMode) -> [NSAttributedString.Key: Any] {
        baseAttributes(for: mode)
    }

    private static func baseAttributes(for mode: MarkdownDisplayMode) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = mode == .markdownOnly ? 3 : 6
        paragraph.paragraphSpacing = 10

        return [
            .font: baseFont(for: mode),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private static func baseFont(for mode: MarkdownDisplayMode) -> NSFont {
        switch mode {
        case .markdownOnly:
            return .monospacedSystemFont(ofSize: 14, weight: .regular)
        case .hybrid, .markupOnly:
            return .systemFont(ofSize: 16, weight: .regular)
        }
    }

    private static func applyLineStyling(to attributed: NSMutableAttributedString, mode: MarkdownDisplayMode) {
        applyMatches(
            pattern: #"(?m)^(#{1,6})(\s+)(.+)$"#,
            in: attributed
        ) { match in
            let markerRange = match.range(at: 1)
            let spacerRange = match.range(at: 2)
            let contentRange = match.range(at: 3)

            let level = markerRange.length
            let size = max(20, 30 - ((level - 1) * 2))
            let font = NSFont.systemFont(ofSize: CGFloat(size), weight: level <= 2 ? .bold : .semibold)

            attributed.addAttributes([.font: font], range: contentRange)
            styleMarker(markerRange, in: attributed, mode: mode)
            styleMarker(spacerRange, in: attributed, mode: mode)
        }

        applyMatches(
            pattern: #"(?m)^([ \t]*(?:[-*+]\s+|\d+\.\s+|>\s+))"#,
            in: attributed
        ) { match in
            styleMarker(match.range(at: 1), in: attributed, mode: mode)
        }

        applyMatches(
            pattern: #"(?m)^(```.*)$"#,
            in: attributed
        ) { match in
            let range = match.range(at: 1)
            attributed.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: range)
        }
    }

    private static func applyInlineStyling(to attributed: NSMutableAttributedString, mode: MarkdownDisplayMode) {
        applyDelimitedPattern(#"(\*\*)(.+?)(\*\*)"#, to: attributed, mode: mode) { range in
            attributed.addAttributes([
                .font: NSFont.systemFont(ofSize: 16, weight: .bold)
            ], range: range)
        }

        applyDelimitedPattern(#"(__)(.+?)(__)"#, to: attributed, mode: mode) { range in
            attributed.addAttributes([
                .font: NSFont.systemFont(ofSize: 16, weight: .bold)
            ], range: range)
        }

        applyDelimitedPattern(#"(?<!\*)(\*)(?!\s)(.+?)(?<!\s)(\*)(?!\*)"#, to: attributed, mode: mode) { range in
            attributed.addAttributes([
                .font: NSFontManager.shared.convert(baseFont(for: mode), toHaveTrait: .italicFontMask)
            ], range: range)
        }

        applyDelimitedPattern(#"(?<!_)(_)(?!\s)(.+?)(?<!\s)(_)(?!_)"#, to: attributed, mode: mode) { range in
            attributed.addAttributes([
                .font: NSFontManager.shared.convert(baseFont(for: mode), toHaveTrait: .italicFontMask)
            ], range: range)
        }

        applyDelimitedPattern(#"(`)([^`\n]+)(`)"#, to: attributed, mode: mode) { range in
            attributed.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .backgroundColor: NSColor.controlBackgroundColor
            ], range: range)
        }

        applyMatches(
            pattern: #"(\[)([^\]]+)(\]\([^)]+\))"#,
            in: attributed
        ) { match in
            styleMarker(match.range(at: 1), in: attributed, mode: mode)
            styleMarker(match.range(at: 3), in: attributed, mode: mode)
            attributed.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: match.range(at: 2))
        }
    }

    private static func applyDelimitedPattern(
        _ pattern: String,
        to attributed: NSMutableAttributedString,
        mode: MarkdownDisplayMode,
        contentAttributes: (NSRange) -> Void
    ) {
        applyMatches(pattern: pattern, in: attributed) { match in
            if match.numberOfRanges >= 4 {
                styleMarker(match.range(at: 1), in: attributed, mode: mode)
                contentAttributes(match.range(at: 2))
                styleMarker(match.range(at: 3), in: attributed, mode: mode)
            } else if match.numberOfRanges >= 2 {
                contentAttributes(match.range(at: 1))
            }
        }
    }

    private static func styleMarker(_ range: NSRange, in attributed: NSMutableAttributedString, mode: MarkdownDisplayMode) {
        guard range.location != NSNotFound, range.length > 0 else { return }

        switch mode {
        case .markdownOnly:
            return
        case .hybrid:
            attributed.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: range)
        case .markupOnly:
            attributed.addAttributes([
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: 1)
            ], range: range)
        }
    }

    private static func applyMatches(
        pattern: String,
        in attributed: NSMutableAttributedString,
        body: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let range = NSRange(location: 0, length: attributed.length)
        let matches = regex.matches(in: attributed.string, options: [], range: range)
        for match in matches.reversed() {
            body(match)
        }
    }
}
