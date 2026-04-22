import AppKit
import Foundation
import Testing
@testable import Archive

@MainActor
struct MarkdownHTMLRendererTests {
    @Test
    func renderFragmentOutputsHorizontalRule() {
        let renderer = MarkdownHTMLRenderer()

        let html = renderer.renderFragment(from: """
        Intro

        ---

        Outro
        """)

        #expect(html.contains("<hr />"))
    }

    @Test
    func renderFragmentPreservesEmphasisInsideHeading() {
        let renderer = MarkdownHTMLRenderer()

        let html = renderer.renderFragment(from: "## Heading *emphasis*")

        #expect(html == "<h2>Heading <em>emphasis</em></h2>")
    }

    @Test
    func markdownPresentationLeavesFencedCodeLiteralInMarkupOnlyMode() {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            ```swift
            # heading
            **bold**
            ```
            """,
            mode: .markupOnly
        )

        let nsString = snapshot.attributedString.string as NSString
        let headingMarkerRange = nsString.range(of: "#")
        let boldMarkerRange = nsString.range(of: "**bold**")

        let headingFont = snapshot.attributedString.attribute(.font, at: headingMarkerRange.location, effectiveRange: nil) as? NSFont
        let boldFont = snapshot.attributedString.attribute(.font, at: boldMarkerRange.location, effectiveRange: nil) as? NSFont

        #expect(snapshot.fencedBlocks.count == 1)
        #expect(headingFont?.pointSize == 16)
        #expect(boldFont?.pointSize == 16)
    }

    @Test
    func markdownPresentationDoesNotCloseFencesWithDifferentDelimiters() {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            ````
            code
            ~~~
            ---
            """,
            mode: .hybrid
        )

        #expect(snapshot.thematicBreaks.isEmpty)
        #expect(snapshot.fencedBlocks.count == 1)
    }

    @Test
    func markdownPresentationDoesNotCloseFencesWithTrailingFenceContent() {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            ```
            code
            ```swift
            ---
            ```
            """,
            mode: .hybrid
        )

        #expect(snapshot.thematicBreaks.isEmpty)
        #expect(snapshot.fencedBlocks.count == 1)
    }

    @Test
    func markdownPresentationIgnoresOverIndentedFenceDelimiters() {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
                ```
                code
                ```
            ---
            """,
            mode: .hybrid
        )

        #expect(snapshot.fencedBlocks.isEmpty)
        #expect(snapshot.thematicBreaks.count == 1)
    }

    @Test
    func markdownPresentationKeepsSetextUnderlinesVisibleInMarkupOnlyMode() throws {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            Heading
            ---
            """,
            mode: .markupOnly
        )

        let underlineRange = try #require(snapshot.setextUnderlineRanges.first)
        let underlineFont = snapshot.attributedString.attribute(.font, at: underlineRange.location, effectiveRange: nil) as? NSFont

        #expect(underlineFont?.pointSize == 11)
    }

    @Test
    func markdownPresentationDoesNotTreatListItemsAsSetextHeadings() {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            - Item
            ---
            """,
            mode: .hybrid
        )

        let nsString = snapshot.attributedString.string as NSString
        let itemRange = nsString.range(of: "Item")
        let itemFont = snapshot.attributedString.attribute(.font, at: itemRange.location, effectiveRange: nil) as? NSFont

        #expect(snapshot.setextUnderlineRanges.isEmpty)
        #expect(snapshot.thematicBreaks.count == 1)
        #expect(itemFont?.pointSize == 16)
    }

    @Test
    func markdownPresentationDoesNotTreatBlockquotesAsSetextHeadings() {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            > Quote
            ---
            """,
            mode: .hybrid
        )

        let nsString = snapshot.attributedString.string as NSString
        let quoteRange = nsString.range(of: "Quote")
        let quoteFont = snapshot.attributedString.attribute(.font, at: quoteRange.location, effectiveRange: nil) as? NSFont

        #expect(snapshot.setextUnderlineRanges.isEmpty)
        #expect(snapshot.thematicBreaks.count == 1)
        #expect(quoteFont?.pointSize == 16)
    }

    @Test
    func markdownPresentationDoesNotTreatRawHTMLAsSetextHeadings() {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            <div>HTML</div>
            ---
            """,
            mode: .hybrid
        )

        let nsString = snapshot.attributedString.string as NSString
        let htmlRange = nsString.range(of: "HTML")
        let htmlFont = snapshot.attributedString.attribute(.font, at: htmlRange.location, effectiveRange: nil) as? NSFont

        #expect(snapshot.setextUnderlineRanges.isEmpty)
        #expect(snapshot.thematicBreaks.count == 1)
        #expect(htmlFont?.pointSize == 16)
    }

    @Test
    func markdownPresentationBuildsVisibleBlockMarkersInMarkupOnlyMode() throws {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            - First item
              - Nested item
            1. Numbered item
            - [x] Completed task
            > Quoted line
            """,
            mode: .markupOnly
        )

        #expect(snapshot.blockMarkers.count == 5)
        #expect(snapshot.blockMarkers[0].kind == .unordered)
        #expect(snapshot.blockMarkers[1].kind == .unordered)
        #expect(snapshot.blockMarkers[2].kind == .ordered("1."))
        #expect(snapshot.blockMarkers[3].kind == .task(true))
        #expect(snapshot.blockMarkers[4].kind == .quote)

        let nestedMarker = try #require(snapshot.blockMarkers.dropFirst().first)
        let topLevelMarker = try #require(snapshot.blockMarkers.first)
        #expect(nestedMarker.headIndent > topLevelMarker.headIndent)

        let firstItemRange = (snapshot.attributedString.string as NSString).range(of: "First item")
        let firstParagraph = snapshot.attributedString.attribute(.paragraphStyle, at: firstItemRange.location, effectiveRange: nil) as? NSParagraphStyle
        #expect(firstParagraph?.headIndent == topLevelMarker.headIndent)
        #expect(topLevelMarker.headIndent == topLevelMarker.leadingInset + topLevelMarker.markerWidth + 6)
    }

    @Test
    func markdownPresentationPreservesOrderedListDelimiterAndQuoteDepth() throws {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            > 1) Quoted ordered item
            > - Quoted bullet
            """,
            mode: .markupOnly
        )

        let firstMarker = try #require(snapshot.blockMarkers.first)
        let secondMarker = try #require(snapshot.blockMarkers.dropFirst().first)
        #expect(firstMarker.kind == .ordered("1)"))
        #expect(firstMarker.quoteDepth == 1)
        #expect(secondMarker.kind == .unordered)
        #expect(secondMarker.quoteDepth == 1)
    }

    @Test
    func markdownPresentationRecognizesOrderedTaskMarkers() throws {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            1. [ ] Inbox item
            2) [x] Done item
            """,
            mode: .markupOnly
        )

        let firstMarker = try #require(snapshot.blockMarkers.first)
        let secondMarker = try #require(snapshot.blockMarkers.dropFirst().first)
        #expect(firstMarker.kind == .task(false))
        #expect(secondMarker.kind == .task(true))
    }

    @Test
    func markdownPresentationExpandsOrderedMarkerGutterForMultiDigitOrdinals() throws {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            1. First
            100. Hundredth
            """,
            mode: .markupOnly
        )

        let firstMarker = try #require(snapshot.blockMarkers.first)
        let secondMarker = try #require(snapshot.blockMarkers.dropFirst().first)
        #expect(secondMarker.markerWidth > firstMarker.markerWidth)
        #expect(secondMarker.headIndent > firstMarker.headIndent)
    }

    @Test
    func markdownPresentationAppliesListParagraphIndentToContinuationLines() throws {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            - First item that continues
              onto the next source line
            """,
            mode: .markupOnly
        )

        let marker = try #require(snapshot.blockMarkers.first)
        let nsString = snapshot.attributedString.string as NSString
        let firstLineRange = nsString.range(of: "First item that continues")
        let continuationRange = nsString.range(of: "onto the next source line")
        let firstParagraph = snapshot.attributedString.attribute(.paragraphStyle, at: firstLineRange.location, effectiveRange: nil) as? NSParagraphStyle
        let continuationParagraph = snapshot.attributedString.attribute(.paragraphStyle, at: continuationRange.location, effectiveRange: nil) as? NSParagraphStyle

        #expect(firstParagraph?.headIndent == marker.headIndent)
        #expect(continuationParagraph?.headIndent == marker.headIndent)
        #expect(continuationParagraph?.firstLineHeadIndent == marker.headIndent)
    }

    @Test
    func markdownPresentationAppliesMeasuredIndentToNestedOrderedAndBulletItems() throws {
        let snapshot = MarkdownPresentationDebug.snapshot(
            for: """
            9. Parent item
               - Nested child item
            10. Another parent item
            """,
            mode: .markupOnly
        )

        let parentMarker = try #require(snapshot.blockMarkers.first)
        let nestedMarker = try #require(snapshot.blockMarkers.dropFirst().first)
        let secondParentMarker = try #require(snapshot.blockMarkers.dropFirst(2).first)
        let nsString = snapshot.attributedString.string as NSString

        let parentRange = nsString.range(of: "Parent item")
        let nestedRange = nsString.range(of: "Nested child item")
        let secondParentRange = nsString.range(of: "Another parent item")

        let parentParagraph = snapshot.attributedString.attribute(.paragraphStyle, at: parentRange.location, effectiveRange: nil) as? NSParagraphStyle
        let nestedParagraph = snapshot.attributedString.attribute(.paragraphStyle, at: nestedRange.location, effectiveRange: nil) as? NSParagraphStyle
        let secondParentParagraph = snapshot.attributedString.attribute(.paragraphStyle, at: secondParentRange.location, effectiveRange: nil) as? NSParagraphStyle

        #expect(parentMarker.kind == .ordered("9."))
        #expect(nestedMarker.kind == .unordered)
        #expect(secondParentMarker.kind == .ordered("10."))
        #expect(nestedMarker.headIndent > parentMarker.headIndent)
        #expect(secondParentMarker.headIndent > parentMarker.headIndent)
        #expect(parentParagraph?.headIndent == parentMarker.headIndent)
        #expect(nestedParagraph?.headIndent == nestedMarker.headIndent)
        #expect(secondParentParagraph?.headIndent == secondParentMarker.headIndent)
    }
}
