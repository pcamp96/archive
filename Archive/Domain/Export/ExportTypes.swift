import Foundation

enum ExportFormat: String, Hashable, Sendable {
    case markdown
    case htmlFragment
}

struct ExportArtifact: Hashable, Sendable {
    let format: ExportFormat
    let content: String
}

