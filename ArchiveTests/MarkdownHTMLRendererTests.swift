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
}
