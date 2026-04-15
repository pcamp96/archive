import Foundation

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

        var registry = try await metadataStore.loadPropertyRegistry(for: rootURL)
        let initialSummaries = try await loadSummaries(from: fileURLs, rootURL: rootURL, registry: registry)
        registry = merge(registry: registry, with: initialSummaries)
        try await metadataStore.savePropertyRegistry(registry, for: rootURL)

        let summaries = try await loadSummaries(from: fileURLs, rootURL: rootURL, registry: registry)
        let viewPreferences = try await metadataStore.loadViewPreferences(for: rootURL)
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

    func search(query: String, rootURL: URL) async -> [SearchResult] {
        await searchIndex.search(query: query)
    }

    func createNote(in folderURL: URL, title: String) async throws -> URL {
        let sanitizedStem = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let baseStem = sanitizedStem.isEmpty ? "Untitled" : sanitizedStem

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

    func renameNote(at url: URL, to newFilename: String) async throws -> URL {
        let sanitized = newFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitized.isEmpty == false else { return url }
        let stem = (sanitized as NSString).deletingPathExtension
        let destination = url.deletingLastPathComponent().appendingPathComponent(stem).appendingPathExtension(url.pathExtension)
        guard destination != url else { return url }
        try fileAccess.moveItem(at: url, to: destination)
        return destination
    }

    func moveNote(at url: URL, to folderURL: URL) async throws -> URL {
        let destination = folderURL.appendingPathComponent(url.lastPathComponent)
        guard destination != url else { return url }
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
}

enum BoardGroupingService {
    static func columns(for notes: [NoteSummary], propertyKey: String, registry: PropertyRegistry) -> [BoardColumn] {
        let definition = registry.definition(for: propertyKey)
        guard definition?.isBoardEligible == true else {
            return [BoardColumn(key: nil, title: "No Value", notes: notes)]
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

        let configuredKeys = definition?.options.map(Optional.some) ?? []
        let discoveredKeys = grouped.keys.filter { $0 != nil && configuredKeys.contains($0) == false }.sorted { ($0 ?? "") < ($1 ?? "") }
        let orderedKeys = configuredKeys + discoveredKeys + [nil]

        return orderedKeys.compactMap { key in
            let notes = (grouped[key] ?? []).sorted(using: KeyPathComparator(\.modifiedAt, order: .reverse))
            guard notes.isEmpty == false || key == nil else { return nil }
            return BoardColumn(key: key, title: key ?? "No Value", notes: notes)
        }
    }
}
