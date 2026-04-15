import Foundation
import Observation

enum MarkdownDisplayMode: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case markdownOnly
    case hybrid
    case markupOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdownOnly:
            return "Markdown Only"
        case .hybrid:
            return "Hybrid"
        case .markupOnly:
            return "Markup Only"
        }
    }

    var subtitle: String {
        switch self {
        case .markdownOnly:
            return "Show raw markdown source."
        case .hybrid:
            return "Render structure while keeping markdown visible."
        case .markupOnly:
            return "Hide markdown markers and read the note as polished text."
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let markdownDisplayMode = "appSettings.markdownDisplayMode"
    }

    private let defaults: UserDefaults

    var markdownDisplayMode: MarkdownDisplayMode {
        didSet {
            defaults.set(markdownDisplayMode.rawValue, forKey: Keys.markdownDisplayMode)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Keys.markdownDisplayMode),
           let mode = MarkdownDisplayMode(rawValue: stored) {
            self.markdownDisplayMode = mode
        } else {
            self.markdownDisplayMode = .hybrid
        }
    }
}

