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
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = MarkdownEditorTextView()
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
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.smartInsertDeleteEnabled = false

        context.coordinator.applyPresentation(to: textView)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownEditorTextView else { return }
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
            if let textView = textView as? MarkdownEditorTextView {
                textView.displayMode = displayMode
                textView.thematicBreakRanges = MarkdownPresentationBuilder.thematicBreakRanges(in: textView.string)
            }
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

private final class MarkdownEditorTextView: NSTextView {
    var displayMode: MarkdownDisplayMode = .markdownOnly
    var thematicBreakRanges: [NSRange] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawThematicBreaks()
    }

    private func drawThematicBreaks() {
        guard displayMode != .markdownOnly,
              let layoutManager else {
            return
        }

        let textContainerOrigin = self.textContainerOrigin
        let startX = textContainerOrigin.x
        let endX = bounds.width - textContainerOrigin.x

        for range in thematicBreakRanges {
            guard range.location != NSNotFound, range.length > 0 else { continue }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound else { continue }

            var effectiveRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: &effectiveRange,
                withoutAdditionalLayout: true
            )

            let path = NSBezierPath()
            let y = lineRect.midY + textContainerOrigin.y
            path.move(to: NSPoint(x: startX, y: y))
            path.line(to: NSPoint(x: endX, y: y))
            path.lineWidth = 2
            thematicBreakColor.setStroke()
            path.stroke()
        }
    }

    private var thematicBreakColor: NSColor {
        switch displayMode {
        case .markdownOnly:
            return .clear
        case .hybrid:
            return NSColor.separatorColor.withAlphaComponent(0.75)
        case .markupOnly:
            return NSColor.separatorColor
        }
    }
}

@MainActor
private enum MarkdownPresentationBuilder {
    private struct SetextHeadingRange {
        let contentRange: NSRange
        let underlineRange: NSRange
        let level: Int
    }

    private struct FenceDelimiter {
        let marker: Character
        let count: Int
        let indent: Int
    }

    private struct FenceState {
        let delimiter: FenceDelimiter
        let blockStart: Int
    }

    private enum SetextCandidateKind {
        case paragraph
        case other
    }

    private struct BlockStructureSnapshot {
        let thematicBreaks: [NSRange]
        let setextHeadings: [SetextHeadingRange]
        let fencedBlocks: [NSRange]
        let fenceDelimiters: [NSRange]
    }

    static func attributedString(for text: String, mode: MarkdownDisplayMode) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes(for: mode))

        guard mode != .markdownOnly else {
            return attributed
        }

        let blockStructure = blockStructure(in: text)
        applyLineStyling(to: attributed, mode: mode, blockStructure: blockStructure)
        applyInlineStyling(to: attributed, mode: mode, blockStructure: blockStructure)
        return attributed
    }

    static func typingAttributes(for mode: MarkdownDisplayMode) -> [NSAttributedString.Key: Any] {
        baseAttributes(for: mode)
    }

    static func thematicBreakRanges(in text: String) -> [NSRange] {
        blockStructure(in: text).thematicBreaks
    }

    private static func blockStructure(in text: String) -> BlockStructureSnapshot {
        let nsText = text as NSString
        var thematicBreaks: [NSRange] = []
        var setextHeadings: [SetextHeadingRange] = []
        var fencedBlocks: [NSRange] = []
        var fenceDelimiters: [NSRange] = []
        var searchLocation = 0
        var currentFence: FenceState?
        var previousContentLine: (kind: SetextCandidateKind, range: NSRange)?

        while searchLocation < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: searchLocation, length: 0))
            let line = nsText.substring(with: lineRange)
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let isIndentedCode = isIndentedCodeLine(line)
            let visibleLineRange = NSRange(location: lineRange.location, length: max(lineRange.length - trailingNewlineLength(in: line), 0))
            let opener = openingFenceDelimiter(for: line)

            if let activeFence = currentFence {
                if isClosingFence(line, for: activeFence.delimiter) {
                    fenceDelimiters.append(visibleLineRange)
                    fencedBlocks.append(NSRange(location: activeFence.blockStart, length: NSMaxRange(lineRange) - activeFence.blockStart))
                    currentFence = nil
                }
                previousContentLine = nil
            } else if isIndentedCode {
                previousContentLine = nil
            } else if let opener {
                currentFence = FenceState(delimiter: opener, blockStart: lineRange.location)
                fenceDelimiters.append(visibleLineRange)
                previousContentLine = nil
            } else if let setextLevel = setextHeadingLevel(for: trimmedLine),
                      let previousLine = previousContentLine,
                      previousLine.kind == .paragraph {
                setextHeadings.append(
                    SetextHeadingRange(
                        contentRange: previousLine.range,
                        underlineRange: visibleLineRange,
                        level: setextLevel
                    )
                )
                previousContentLine = nil
            } else if isThematicBreakLine(trimmedLine) {
                thematicBreaks.append(visibleLineRange)
                previousContentLine = nil
            } else if trimmedLine.isEmpty {
                previousContentLine = nil
            } else {
                previousContentLine = (
                    kind: setextCandidateKind(for: line),
                    range: visibleLineRange
                )
            }

            searchLocation = NSMaxRange(lineRange)
        }

        if let currentFence {
            fencedBlocks.append(NSRange(location: currentFence.blockStart, length: nsText.length - currentFence.blockStart))
        }

        return BlockStructureSnapshot(
            thematicBreaks: thematicBreaks,
            setextHeadings: setextHeadings,
            fencedBlocks: fencedBlocks,
            fenceDelimiters: fenceDelimiters
        )
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

    private static func applyLineStyling(
        to attributed: NSMutableAttributedString,
        mode: MarkdownDisplayMode,
        blockStructure: BlockStructureSnapshot
    ) {
        applyMatches(
            pattern: #"(?m)^(#{1,6})(\s+)(.+)$"#,
            in: attributed,
            skipping: blockStructure.fencedBlocks
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
            in: attributed,
            skipping: blockStructure.fencedBlocks
        ) { match in
            styleMarker(match.range(at: 1), in: attributed, mode: mode)
        }

        for range in blockStructure.fenceDelimiters.reversed() {
            attributed.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: range)
        }

        for heading in blockStructure.setextHeadings.reversed() {
            let font = setextHeadingFont(for: heading.level)
            attributed.addAttributes([.font: font], range: heading.contentRange)
            styleSetextUnderline(heading.underlineRange, in: attributed, mode: mode)
        }

        for range in blockStructure.thematicBreaks.reversed() {
            styleThematicBreak(range, in: attributed, mode: mode)
        }
    }

    private static func applyInlineStyling(
        to attributed: NSMutableAttributedString,
        mode: MarkdownDisplayMode,
        blockStructure: BlockStructureSnapshot
    ) {
        applyDelimitedPattern(#"(\*\*)(.+?)(\*\*)"#, to: attributed, mode: mode, skipping: blockStructure.fencedBlocks) { range in
            let existingFont = currentFont(in: attributed, at: range.location, fallback: baseFont(for: mode))
            attributed.addAttributes([
                .font: font(byApplying: .boldFontMask, to: existingFont)
            ], range: range)
        }

        applyDelimitedPattern(#"(__)(.+?)(__)"#, to: attributed, mode: mode, skipping: blockStructure.fencedBlocks) { range in
            let existingFont = currentFont(in: attributed, at: range.location, fallback: baseFont(for: mode))
            attributed.addAttributes([
                .font: font(byApplying: .boldFontMask, to: existingFont)
            ], range: range)
        }

        applyDelimitedPattern(#"(?<!\*)(\*)(?!\s)(.+?)(?<!\s)(\*)(?!\*)"#, to: attributed, mode: mode, skipping: blockStructure.fencedBlocks) { range in
            let existingFont = currentFont(in: attributed, at: range.location, fallback: baseFont(for: mode))
            attributed.addAttributes([
                .font: font(byApplying: .italicFontMask, to: existingFont)
            ], range: range)
        }

        applyDelimitedPattern(#"(?<!_)(_)(?!\s)(.+?)(?<!\s)(_)(?!_)"#, to: attributed, mode: mode, skipping: blockStructure.fencedBlocks) { range in
            let existingFont = currentFont(in: attributed, at: range.location, fallback: baseFont(for: mode))
            attributed.addAttributes([
                .font: font(byApplying: .italicFontMask, to: existingFont)
            ], range: range)
        }

        applyDelimitedPattern(#"(`)([^`\n]+)(`)"#, to: attributed, mode: mode, skipping: blockStructure.fencedBlocks) { range in
            attributed.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .backgroundColor: NSColor.controlBackgroundColor
            ], range: range)
        }

        applyMatches(
            pattern: #"(\[)([^\]]+)(\]\([^)]+\))"#,
            in: attributed,
            skipping: blockStructure.fencedBlocks
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
        skipping skipRanges: [NSRange] = [],
        contentAttributes: (NSRange) -> Void
    ) {
        applyMatches(pattern: pattern, in: attributed, skipping: skipRanges) { match in
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

    private static func styleSetextUnderline(_ range: NSRange, in attributed: NSMutableAttributedString, mode: MarkdownDisplayMode) {
        guard range.location != NSNotFound, range.length > 0 else { return }

        switch mode {
        case .markdownOnly:
            return
        case .hybrid:
            styleMarker(range, in: attributed, mode: mode)
        case .markupOnly:
            attributed.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.3),
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            ], range: range)
        }
    }

    private static func styleThematicBreak(_ range: NSRange, in attributed: NSMutableAttributedString, mode: MarkdownDisplayMode) {
        guard range.location != NSNotFound, range.length > 0 else { return }

        switch mode {
        case .markdownOnly:
            return
        case .hybrid:
            attributed.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.18)
            ], range: range)
        case .markupOnly:
            attributed.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.08)
            ], range: range)
        }
    }

    private static func currentFont(in attributed: NSAttributedString, at location: Int, fallback: NSFont) -> NSFont {
        guard attributed.length > 0 else { return fallback }
        let safeLocation = min(max(location, 0), attributed.length - 1)
        return attributed.attribute(.font, at: safeLocation, effectiveRange: nil) as? NSFont ?? fallback
    }

    private static func font(byApplying trait: NSFontTraitMask, to font: NSFont) -> NSFont {
        let desiredTrait: NSFontDescriptor.SymbolicTraits
        switch trait {
        case .italicFontMask:
            desiredTrait = .italic
        case .boldFontMask:
            desiredTrait = .bold
        default:
            desiredTrait = []
        }

        let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
        if converted.pointSize > 0,
           desiredTrait.isEmpty || converted.fontDescriptor.symbolicTraits.contains(desiredTrait) {
            return converted
        }

        if trait == .italicFontMask {
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(desiredTrait))
            return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        }

        if trait == .boldFontMask {
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(desiredTrait))
            return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        }

        return font
    }

    private static func applyMatches(
        pattern: String,
        in attributed: NSMutableAttributedString,
        skipping skipRanges: [NSRange] = [],
        body: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let range = NSRange(location: 0, length: attributed.length)
        let matches = regex.matches(in: attributed.string, options: [], range: range)
        for match in matches.reversed() {
            guard shouldSkip(match.range, for: skipRanges) == false else { continue }
            body(match)
        }
    }

    private static func shouldSkip(_ range: NSRange, for skipRanges: [NSRange]) -> Bool {
        skipRanges.contains { NSIntersectionRange(range, $0).length > 0 }
    }

    private static func openingFenceDelimiter(for line: String) -> FenceDelimiter? {
        fenceDelimiter(for: line, requireBlankTrailingText: false)
    }

    private static func isClosingFence(_ line: String, for delimiter: FenceDelimiter) -> Bool {
        guard let closingDelimiter = fenceDelimiter(for: line, requireBlankTrailingText: true) else {
            return false
        }

        return closingDelimiter.marker == delimiter.marker && closingDelimiter.count >= delimiter.count
    }

    private static func fenceDelimiter(for line: String, requireBlankTrailingText: Bool) -> FenceDelimiter? {
        let withoutNewline = line.trimmingCharacters(in: .newlines)
        let indent = withoutNewline.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        guard withoutNewline.prefix(indent).allSatisfy({ $0 == " " }) else { return nil }

        let trimmed = withoutNewline.dropFirst(indent)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }

        let count = trimmed.prefix { $0 == marker }.count
        guard count >= 3 else { return nil }
        let trailing = String(trimmed.dropFirst(count))
        if requireBlankTrailingText, trailing.trimmingCharacters(in: .whitespaces).isEmpty == false {
            return nil
        }

        return FenceDelimiter(marker: marker, count: count, indent: indent)
    }

    private static func isThematicBreakLine(_ line: String) -> Bool {
        guard line.isEmpty == false else { return false }
        let filtered = line.filter { $0 != " " && $0 != "\t" }
        guard filtered.count >= 3 else { return false }
        let characters = Set(filtered)
        guard characters.count == 1, let character = characters.first else { return false }
        return character == "-" || character == "*" || character == "_"
    }

    private static func isIndentedCodeLine(_ line: String) -> Bool {
        let withoutNewline = line.trimmingCharacters(in: .newlines)
        guard withoutNewline.isEmpty == false else { return false }
        if withoutNewline.first == "\t" {
            return true
        }
        return withoutNewline.prefix { $0 == " " }.count >= 4
    }

    private static func setextHeadingLevel(for line: String) -> Int? {
        guard line.isEmpty == false else { return nil }
        let filtered = line.filter { $0 != " " && $0 != "\t" }
        guard filtered.count >= 2 else { return nil }
        let characters = Set(filtered)
        guard characters.count == 1, let character = characters.first else { return nil }
        switch character {
        case "=":
            return 1
        case "-":
            return 2
        default:
            return nil
        }
    }

    private static func setextCandidateKind(for line: String) -> SetextCandidateKind {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return .other }
        guard trimmed.hasPrefix(">") == false,
              trimmed.hasPrefix("<") == false,
              trimmed.hasPrefix("#") == false else {
            return .other
        }

        let withoutNewline = line.trimmingCharacters(in: .newlines)
        let leadingSpaceCount = withoutNewline.prefix { $0 == " " }.count
        let indent = min(leadingSpaceCount, 3)
        let content = withoutNewline.dropFirst(indent)
        guard content.isEmpty == false else { return .other }

        if let first = content.first, ["-", "+", "*"].contains(first) {
            let remainder = content.dropFirst()
            if remainder.first?.isWhitespace == true {
                return .other
            }
        }

        var digits = 0
        for character in content {
            if character.isNumber {
                digits += 1
                continue
            }
            if character == ".", digits > 0, content.dropFirst(digits + 1).first?.isWhitespace == true {
                return .other
            }
            break
        }

        return .paragraph
    }

    private static func setextHeadingFont(for level: Int) -> NSFont {
        let size = level == 1 ? 30 : 28
        let weight: NSFont.Weight = level == 1 ? .bold : .semibold
        return NSFont.systemFont(ofSize: CGFloat(size), weight: weight)
    }

    private static func trailingNewlineLength(in line: String) -> Int {
        if line.hasSuffix("\r\n") {
            return 2
        }
        if line.hasSuffix("\n") || line.hasSuffix("\r") {
            return 1
        }
        return 0
    }

#if DEBUG
    static func debugSnapshot(for text: String, mode: MarkdownDisplayMode) -> MarkdownPresentationDebug.Snapshot {
        let blockStructure = blockStructure(in: text)
        return MarkdownPresentationDebug.Snapshot(
            attributedString: attributedString(for: text, mode: mode),
            thematicBreaks: blockStructure.thematicBreaks,
            setextUnderlineRanges: blockStructure.setextHeadings.map { $0.underlineRange },
            fencedBlocks: blockStructure.fencedBlocks
        )
    }
#endif
}

#if DEBUG
@MainActor
enum MarkdownPresentationDebug {
    struct Snapshot {
        let attributedString: NSAttributedString
        let thematicBreaks: [NSRange]
        let setextUnderlineRanges: [NSRange]
        let fencedBlocks: [NSRange]
    }

    static func snapshot(for text: String, mode: MarkdownDisplayMode) -> Snapshot {
        MarkdownPresentationBuilder.debugSnapshot(for: text, mode: mode)
    }
}
#endif
