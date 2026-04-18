import Foundation

enum NoteRepositoryError: LocalizedError {
    case versionConflict(message: String)

    var errorDescription: String? {
        switch self {
        case .versionConflict(let message):
            return message
        }
    }
}

final class NoteRepository: @unchecked Sendable {
    private let fileAccess: FileCoordinatorIO
    private let scanner = FrontmatterScanner()
    private let codec = FrontmatterCodec()

    init(fileAccess: FileCoordinatorIO) {
        self.fileAccess = fileAccess
    }

    func loadSummary(at url: URL, relativeTo rootURL: URL, registry: PropertyRegistry) async throws -> NoteSummary {
        let source = try fileAccess.readString(at: url)
        let parsed = scanner.parse(source)
        let metadata = try fileAccess.metadata(for: url)
        let editableProperties = parsed.frontmatter.editableProperties(using: registry)
        let title = resolvedTitle(
            explicitTitle: editableProperties.first(where: { $0.key == "title" })?.value.stringValue,
            body: parsed.body,
            fallbackURL: url
        )

        return NoteSummary(
            id: metadata.id,
            fileURL: url,
            relativePath: url.path.replacingOccurrences(of: rootURL.path + "/", with: ""),
            title: title,
            bodyPreview: preview(from: parsed.body),
            createdAt: metadata.createdAt,
            modifiedAt: metadata.modifiedAt,
            propertyValues: editableProperties.summaryPropertyMap()
        )
    }

    func loadDocument(at url: URL, relativeTo rootURL: URL, registry: PropertyRegistry) async throws -> NoteDocument {
        let source = try fileAccess.readString(at: url)
        let parsed = scanner.parse(source)
        let metadata = try fileAccess.metadata(for: url)
        let editableProperties = parsed.frontmatter.editableProperties(using: registry)
        let title = resolvedTitle(
            explicitTitle: editableProperties.first(where: { $0.key == "title" })?.value.stringValue,
            body: parsed.body,
            fallbackURL: url
        )

        return NoteDocument(
            id: metadata.id,
            rootURL: rootURL,
            fileURL: url,
            relativePath: url.path.replacingOccurrences(of: rootURL.path + "/", with: ""),
            title: title,
            frontmatter: parsed.frontmatter,
            editableProperties: editableProperties,
            body: parsed.body,
            createdAt: metadata.createdAt,
            modifiedAt: metadata.modifiedAt,
            versionToken: metadata.token
        )
    }

    func saveDraft(_ draft: NoteDraft, original: NoteDocument, registry: PropertyRegistry) async throws -> NoteDocument {
        let currentMetadata = try fileAccess.metadata(for: draft.fileURL)
        guard currentMetadata.token == draft.baseVersionToken else {
            throw NoteRepositoryError.versionConflict(message: "The note changed on disk after it was opened. Reload, overwrite, or duplicate the draft before saving again.")
        }

        let frontmatter = codec.serializedFrontmatter(
            from: original.frontmatter,
            title: draft.title,
            properties: draft.properties
        )

        var output = ""
        if let frontmatter {
            output += frontmatter + "\n\n"
        }
        output += draft.body
        try fileAccess.writeAtomically(output, to: draft.fileURL)

        return try await loadDocument(at: draft.fileURL, relativeTo: draft.rootURL, registry: registry)
    }

    func serializeBodyOnly(frontmatter: String?, body: String) -> String {
        if let frontmatter, frontmatter.isEmpty == false {
            return "\(frontmatter)\n\n\(body)"
        }
        return body
    }

    private func preview(from body: String) -> String {
        body
            .components(separatedBy: .newlines)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty == false })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func resolvedTitle(explicitTitle: String?, body: String, fallbackURL: URL) -> String {
        if let explicitTitle, explicitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return explicitTitle
        }

        if let heading = body
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("# ") })?
            .replacingOccurrences(of: "# ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines),
           heading.isEmpty == false {
            return heading
        }

        return fallbackURL.deletingPathExtension().lastPathComponent
    }
}
