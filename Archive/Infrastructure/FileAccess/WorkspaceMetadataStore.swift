import Foundation

actor WorkspaceMetadataStore {
    private let fileManager = FileManager.default

    enum ExistingFileSnapshot: Equatable {
        case missing
        case readable(Data)
        case unreadable
    }

    func loadPropertyRegistry(for rootURL: URL) async throws -> PropertyRegistry {
        let url = propertyRegistryURL(for: rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return PropertyRegistry() }
        guard let data = try? Data(contentsOf: url),
              let registry = try? JSONDecoder().decode(PropertyRegistry.self, from: data) else {
            return PropertyRegistry()
        }
        return registry
    }

    func savePropertyRegistry(_ registry: PropertyRegistry, for rootURL: URL) async throws {
        try ensureMetadataDirectory(for: rootURL)
        let data = try JSONEncoder.pretty.encode(registry)
        try data.write(to: propertyRegistryURL(for: rootURL), options: .atomic)
    }

    func loadViewPreferences(for rootURL: URL) async throws -> WorkspaceViewPreferences {
        let url = viewsURL(for: rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return WorkspaceViewPreferences() }
        guard let data = try? Data(contentsOf: url),
              let preferences = try? JSONDecoder().decode(WorkspaceViewPreferences.self, from: data) else {
            return WorkspaceViewPreferences()
        }
        return preferences
    }

    func saveViewPreferences(_ preferences: WorkspaceViewPreferences, for rootURL: URL) async throws {
        try ensureMetadataDirectory(for: rootURL)
        let data = try JSONEncoder.pretty.encode(preferences)
        try data.write(to: viewsURL(for: rootURL), options: .atomic)
    }

    func saveMetadata(
        registry: PropertyRegistry,
        viewPreferences: WorkspaceViewPreferences,
        for rootURL: URL
    ) async throws {
        try ensureMetadataDirectory(for: rootURL)

        let registryURL = propertyRegistryURL(for: rootURL)
        let viewsURL = viewsURL(for: rootURL)
        let existingRegistry = snapshot(of: registryURL)
        let existingViews = snapshot(of: viewsURL)
        try writeMetadata(
            registry: registry,
            viewPreferences: viewPreferences,
            registryURL: registryURL,
            viewsURL: viewsURL,
            existingRegistry: existingRegistry,
            existingViews: existingViews
        )
    }

    private func writeMetadata(
        registry: PropertyRegistry,
        viewPreferences: WorkspaceViewPreferences,
        registryURL: URL,
        viewsURL: URL,
        existingRegistry: ExistingFileSnapshot,
        existingViews: ExistingFileSnapshot
    ) throws {
        let registryData = try JSONEncoder.pretty.encode(registry)
        let viewsData = try JSONEncoder.pretty.encode(viewPreferences)

        do {
            try registryData.write(to: registryURL, options: .atomic)
            try viewsData.write(to: viewsURL, options: .atomic)
        } catch {
            try? restore(existingRegistry, to: registryURL)
            try? restore(existingViews, to: viewsURL)
            throw error
        }
    }

    private func ensureMetadataDirectory(for rootURL: URL) throws {
        try fileManager.createDirectory(at: metadataDirectory(for: rootURL), withIntermediateDirectories: true)
    }

    private func metadataDirectory(for rootURL: URL) -> URL {
        rootURL.appendingPathComponent(".archive", isDirectory: true)
    }

    private func propertyRegistryURL(for rootURL: URL) -> URL {
        metadataDirectory(for: rootURL).appendingPathComponent("properties.json")
    }

    private func viewsURL(for rootURL: URL) -> URL {
        metadataDirectory(for: rootURL).appendingPathComponent("views.json")
    }

    private func snapshot(of url: URL) -> ExistingFileSnapshot {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        return .readable(data)
    }

    private func restore(_ snapshot: ExistingFileSnapshot, to url: URL) throws {
        switch snapshot {
        case .missing:
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        case let .readable(data):
            try data.write(to: url, options: .atomic)
        case .unreadable:
            return
        }
    }

#if DEBUG
    func debugSnapshot(of url: URL) -> ExistingFileSnapshot {
        snapshot(of: url)
    }

    func debugWriteMetadata(
        registry: PropertyRegistry,
        viewPreferences: WorkspaceViewPreferences,
        for rootURL: URL,
        existingRegistry: ExistingFileSnapshot,
        existingViews: ExistingFileSnapshot
    ) async throws {
        try ensureMetadataDirectory(for: rootURL)
        try writeMetadata(
            registry: registry,
            viewPreferences: viewPreferences,
            registryURL: propertyRegistryURL(for: rootURL),
            viewsURL: viewsURL(for: rootURL),
            existingRegistry: existingRegistry,
            existingViews: existingViews
        )
    }
#endif
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
