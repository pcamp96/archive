import Foundation

actor WorkspaceMetadataStore {
    private let fileManager = FileManager.default

    func loadPropertyRegistry(for rootURL: URL) async throws -> PropertyRegistry {
        let url = propertyRegistryURL(for: rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return PropertyRegistry() }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PropertyRegistry.self, from: data)
    }

    func savePropertyRegistry(_ registry: PropertyRegistry, for rootURL: URL) async throws {
        try ensureMetadataDirectory(for: rootURL)
        let data = try JSONEncoder.pretty.encode(registry)
        try data.write(to: propertyRegistryURL(for: rootURL), options: .atomic)
    }

    func loadViewPreferences(for rootURL: URL) async throws -> WorkspaceViewPreferences {
        let url = viewsURL(for: rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return WorkspaceViewPreferences() }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WorkspaceViewPreferences.self, from: data)
    }

    func saveViewPreferences(_ preferences: WorkspaceViewPreferences, for rootURL: URL) async throws {
        try ensureMetadataDirectory(for: rootURL)
        let data = try JSONEncoder.pretty.encode(preferences)
        try data.write(to: viewsURL(for: rootURL), options: .atomic)
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
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
