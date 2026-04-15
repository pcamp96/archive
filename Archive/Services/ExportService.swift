import AppKit
import Foundation

@MainActor
final class ExportService {
    private let renderer: MarkdownHTMLRenderer

    init(renderer: MarkdownHTMLRenderer) {
        self.renderer = renderer
    }

    func copyPlainText(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func copyHTMLFragment(markdown: String) throws {
        let html = renderer.renderFragment(from: markdown)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        pasteboard.setString(html, forType: .html)
    }

    func htmlFragment(for markdown: String) -> String {
        renderer.renderFragment(from: markdown)
    }
}

