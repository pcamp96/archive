import Foundation
import Markdown

struct MarkdownHTMLRenderer {
    func renderFragment(from markdown: String) -> String {
        let document = Document(parsing: markdown)
        let renderer = HTMLFragmentRenderer()
        return renderer.render(document)
    }
}

private struct HTMLFragmentRenderer {
    func render(_ document: Document) -> String {
        renderAny(document)
    }

    private func renderAny(_ markup: any Markup) -> String {
        switch markup {
        case let document as Document:
            return document.children.map(renderAny).joined(separator: "\n")
        case let heading as Heading:
            let level = min(max(heading.level, 1), 6)
            return "<h\(level)>\(renderChildren(of: heading))</h\(level)>"
        case let paragraph as Paragraph:
            return "<p>\(renderChildren(of: paragraph))</p>"
        case let text as Text:
            return escape(text.string)
        case _ as SoftBreak:
            return "\n"
        case _ as LineBreak:
            return "<br />"
        case let emphasis as Emphasis:
            return "<em>\(renderChildren(of: emphasis))</em>"
        case let strong as Strong:
            return "<strong>\(renderChildren(of: strong))</strong>"
        case let inlineCode as InlineCode:
            return "<code>\(escape(inlineCode.code))</code>"
        case let codeBlock as CodeBlock:
            return "<pre><code>\(escape(codeBlock.code))</code></pre>"
        case let unorderedList as UnorderedList:
            return "<ul>\(unorderedList.listItems.map(renderAny).joined())</ul>"
        case let orderedList as OrderedList:
            return "<ol>\(orderedList.listItems.map(renderAny).joined())</ol>"
        case let listItem as ListItem:
            return "<li>\(listItem.children.map(renderAny).joined())</li>"
        case let link as Link:
            let destination = escapeAttribute(link.destination ?? "")
            return "<a href=\"\(destination)\">\(renderChildren(of: link))</a>"
        case let image as Image:
            let source = escapeAttribute(image.source ?? "")
            let alt = escapeAttribute(plainText(from: image))
            return "<img src=\"\(source)\" alt=\"\(alt)\" />"
        case let blockQuote as BlockQuote:
            return "<blockquote>\(blockQuote.children.map(renderAny).joined())</blockquote>"
        case _ as ThematicBreak:
            return "<hr />"
        default:
            return markup.children.map(renderAny).joined()
        }
    }

    private func renderChildren(of markup: any Markup) -> String {
        markup.children.map(renderAny).joined()
    }

    private func plainText(from markup: any Markup) -> String {
        if let text = markup as? Text {
            return text.string
        }
        return markup.children.map(plainText).joined(separator: " ")
    }

    private func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ string: String) -> String {
        escape(string).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
