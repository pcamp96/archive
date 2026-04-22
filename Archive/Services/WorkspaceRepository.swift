import Foundation

enum WorkspaceRepositoryError: LocalizedError, Equatable {
    case noteAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .noteAlreadyExists(let filename):
            return "A note named \"\(filename)\" already exists in that location."
        }
    }
}

final class WorkspaceRepository: @unchecked Sendable {
    private let fileAccess: FileCoordinatorIO
    private let noteRepository: NoteRepository
    private let metadataStore: WorkspaceMetadataStore
    private let searchIndex: SearchIndex

    init(
        fileAccess: FileCoordinatorIO,
        noteRepository: NoteRepository,
        metadataStore: WorkspaceMetadataStore,
        searchIndex: SearchIndex
    ) {
        self.fileAccess = fileAccess
        self.noteRepository = noteRepository
        self.metadataStore = metadataStore
        self.searchIndex = searchIndex
    }

    func loadWorkspace(at rootURL: URL) async throws -> WorkspaceSnapshot {
        let folderTree = try fileAccess.folderTree(in: rootURL)
        let fileURLs = try fileAccess.markdownFileURLs(in: rootURL)

        let persistedRegistry = try await metadataStore.loadPropertyRegistry(for: rootURL)
        let initialSummaries = try await loadSummaries(from: fileURLs, rootURL: rootURL, registry: persistedRegistry)
        let registry = merge(registry: persistedRegistry, with: initialSummaries)
        if registry != persistedRegistry {
            try? await metadataStore.savePropertyRegistry(registry, for: rootURL)
        }

        let summaries = registry == persistedRegistry
            ? initialSummaries
            : try await loadSummaries(from: fileURLs, rootURL: rootURL, registry: registry)
        var viewPreferences = try await metadataStore.loadViewPreferences(for: rootURL)
        if viewPreferences.savedBoardViews.isEmpty, let propertyKey = registry.defaultBoardPropertyKey {
            let defaultBoard = SavedBoardView(
                name: propertyKey == "status" ? "Status Board" : "\(propertyKey.capitalized) Board",
                groupByProperty: propertyKey,
                laneOrder: registry.definition(for: propertyKey)?.options ?? []
            )
            viewPreferences.savedBoardViews = [defaultBoard]
            viewPreferences.selectedBoardViewID = defaultBoard.id
            try? await metadataStore.saveViewPreferences(viewPreferences, for: rootURL)
        } else if viewPreferences.presentationMode == .board, viewPreferences.savedBoardViews.isEmpty {
            viewPreferences.presentationMode = .list
            viewPreferences.selectedBoardViewID = nil
            try? await metadataStore.saveViewPreferences(viewPreferences, for: rootURL)
        }
        if let selectedBoardViewID = viewPreferences.selectedBoardViewID,
           viewPreferences.savedBoardViews.contains(where: { $0.id == selectedBoardViewID }) == false {
            viewPreferences.selectedBoardViewID = viewPreferences.savedBoardViews.first?.id
            try? await metadataStore.saveViewPreferences(viewPreferences, for: rootURL)
        } else if viewPreferences.selectedBoardViewID == nil, let firstBoardID = viewPreferences.savedBoardViews.first?.id {
            viewPreferences.selectedBoardViewID = firstBoardID
            try? await metadataStore.saveViewPreferences(viewPreferences, for: rootURL)
        }
        await searchIndex.rebuild(with: summaries)

        return WorkspaceSnapshot(
            rootURL: rootURL,
            folderTree: folderTree,
            notes: summaries,
            propertyRegistry: registry,
            viewPreferences: viewPreferences
        )
    }

    func saveViewPreferences(_ preferences: WorkspaceViewPreferences, for rootURL: URL) async throws {
        try await metadataStore.saveViewPreferences(preferences, for: rootURL)
    }

    func savePropertyRegistry(_ registry: PropertyRegistry, for rootURL: URL) async throws {
        try await metadataStore.savePropertyRegistry(registry, for: rootURL)
    }

    func saveMetadata(
        registry: PropertyRegistry,
        viewPreferences: WorkspaceViewPreferences,
        for rootURL: URL
    ) async throws {
        try await metadataStore.saveMetadata(registry: registry, viewPreferences: viewPreferences, for: rootURL)
    }

    func search(query: String, rootURL: URL) async -> [SearchResult] {
        await searchIndex.search(query: query)
    }

    func updateSearchIndex(with summary: NoteSummary) async {
        await searchIndex.update(with: summary)
    }

    func createNote(in folderURL: URL, title: String) async throws -> URL {
        let baseStem = normalizedNoteStem(from: title) ?? "Untitled"

        var candidate = folderURL.appendingPathComponent("\(baseStem).md")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folderURL.appendingPathComponent("\(baseStem) \(suffix).md")
            suffix += 1
        }

        let contents = """
        ---
        title: \(baseStem)
        ---

        """
        try fileAccess.createFile(at: candidate, contents: contents)
        return candidate
    }

    func createFolder(in parentURL: URL, name: String) async throws -> URL {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else { return parentURL }

        let sanitized = trimmedName.replacingOccurrences(of: "/", with: "-")
        var candidate = parentURL.appendingPathComponent(sanitized, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parentURL.appendingPathComponent("\(sanitized) \(suffix)", isDirectory: true)
            suffix += 1
        }

        try fileAccess.createDirectoryIfNeeded(at: candidate)
        return candidate
    }

    func renameNote(at url: URL, to newFilename: String) async throws -> URL {
        guard let stem = normalizedNoteStem(from: newFilename) else { return url }
        let destination = url.deletingLastPathComponent().appendingPathComponent(stem).appendingPathExtension(url.pathExtension)
        guard destination != url else { return url }
        if try refersToSameFile(url, and: destination) {
            try renameCaseOnlyNote(at: url, to: destination)
            return destination
        }
        try ensureNoteDoesNotAlreadyExist(at: destination, excluding: url)
        try fileAccess.moveItem(at: url, to: destination)
        return destination
    }

    func moveNote(at url: URL, to folderURL: URL) async throws -> URL {
        let destination = folderURL.appendingPathComponent(url.lastPathComponent)
        guard destination != url else { return url }
        try ensureNoteDoesNotAlreadyExist(at: destination, excluding: url)
        try fileAccess.moveItem(at: url, to: destination)
        return destination
    }

    func deleteNote(at url: URL) async throws {
        try fileAccess.trashItem(at: url)
    }

    private func loadSummaries(from fileURLs: [URL], rootURL: URL, registry: PropertyRegistry) async throws -> [NoteSummary] {
        var summaries: [NoteSummary] = []
        for url in fileURLs {
            do {
                let summary = try await noteRepository.loadSummary(at: url, relativeTo: rootURL, registry: registry)
                summaries.append(summary)
            } catch {
                continue
            }
        }
        return summaries
    }

    private func merge(registry: PropertyRegistry, with summaries: [NoteSummary]) -> PropertyRegistry {
        var merged = registry
        let persistedDefinitionKeys = Set(registry.definitions.keys)

        for summary in summaries {
            for (key, value) in summary.propertyValues where key != "title" {
                if merged.definitions[key] == nil {
                    let kind: PropertyKind
                    switch PropertyInference.inferKind(for: value) {
                    case .text:
                        kind = key == "status" ? .singleSelect : .text
                    default:
                        kind = PropertyInference.inferKind(for: value)
                    }

                    let options: [String]
                    switch value {
                    case .string(let string):
                        options = kind == .singleSelect ? [string] : []
                    case .stringList(let values):
                        options = values
                    default:
                        options = []
                    }

                    merged.definitions[key] = PropertyDefinition(key: key, kind: kind, options: options.sorted())
                } else if case .string(let valueString) = value, merged.definitions[key]?.kind == .singleSelect {
                    guard persistedDefinitionKeys.contains(key) == false else { continue }
                    if merged.definitions[key]?.options.contains(valueString) == false {
                        merged.definitions[key]?.options.append(valueString)
                        merged.definitions[key]?.options.sort()
                    }
                } else if case .stringList(let values) = value, merged.definitions[key]?.kind == .multiSelect {
                    let existing = Set(merged.definitions[key]?.options ?? [])
                    let combined = Array(existing.union(values)).sorted()
                    merged.definitions[key]?.options = combined
                }
            }
        }

        return merged
    }

    private func ensureNoteDoesNotAlreadyExist(at destination: URL, excluding source: URL) throws {
        let normalizedDestination = destination.standardizedFileURL
        let normalizedSource = source.standardizedFileURL
        guard normalizedDestination != normalizedSource else { return }
        guard FileManager.default.fileExists(atPath: normalizedDestination.path) == false else {
            throw WorkspaceRepositoryError.noteAlreadyExists(normalizedDestination.lastPathComponent)
        }
    }

    private func refersToSameFile(_ source: URL, and destination: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: destination.path) else { return false }
        let sourceMetadata = try fileAccess.metadata(for: source)
        let destinationMetadata = try fileAccess.metadata(for: destination)
        return sourceMetadata.id.resourceIdentifier == destinationMetadata.id.resourceIdentifier
    }

    private func renameCaseOnlyNote(at source: URL, to destination: URL) throws {
        let tempURL = source
            .deletingLastPathComponent()
            .appendingPathComponent(".archive-rename-\(UUID().uuidString)")
            .appendingPathExtension(source.pathExtension)
        try fileAccess.moveItem(at: source, to: tempURL)
        do {
            try fileAccess.moveItem(at: tempURL, to: destination)
        } catch {
            try? fileAccess.moveItem(at: tempURL, to: source)
            throw error
        }
    }

    private func normalizedNoteStem(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let sanitized = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let stem: String
        if sanitized.lowercased().hasSuffix(".md") {
            stem = String(sanitized.dropLast(3))
        } else {
            stem = sanitized
        }

        let normalized = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum BoardGroupingService {
    static func columns(
        for notes: [NoteSummary],
        boardView: SavedBoardView,
        registry: PropertyRegistry
    ) -> [BoardColumn] {
        let propertyKey = boardView.groupByProperty
        let definition = registry.definition(for: propertyKey)
        guard definition?.isBoardEligible == true else {
            return [BoardColumn(key: nil, title: "Unassigned", notes: notes)]
        }

        var grouped: [String?: [NoteSummary]] = [:]
        for note in notes {
            let key: String?
            switch note.propertyValues[propertyKey] {
            case .string(let value):
                key = value.isEmpty ? nil : value
            default:
                key = nil
            }
            grouped[key, default: []].append(note)
        }

        let configuredKeys = boardView.laneOrder.isEmpty
            ? (definition?.options.map(Optional.some) ?? [])
            : boardView.laneOrder.map(Optional.some)
        let discoveredKeys = grouped.keys.filter { $0 != nil && configuredKeys.contains($0) == false }.sorted { ($0 ?? "") < ($1 ?? "") }
        let orderedKeys = configuredKeys + discoveredKeys + [nil]

        return orderedKeys.compactMap { key in
            let notes = (grouped[key] ?? []).sorted(using: KeyPathComparator(\.modifiedAt, order: .reverse))
            guard notes.isEmpty == false || key == nil else { return nil }
            return BoardColumn(key: key, title: key ?? "Unassigned", notes: notes)
        }
    }
}
