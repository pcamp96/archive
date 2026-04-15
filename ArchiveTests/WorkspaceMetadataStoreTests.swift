import Foundation
import Testing
@testable import Archive

struct WorkspaceMetadataStoreTests {
    @Test
    func metadataStoreSavesAndLoadsRegistry() async throws {
        let store = WorkspaceMetadataStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = PropertyRegistry(definitions: [
            "status": PropertyDefinition(key: "status", kind: .singleSelect, options: ["Draft", "Published"])
        ])

        try await store.savePropertyRegistry(registry, for: root)
        let loaded = try await store.loadPropertyRegistry(for: root)

        #expect(loaded == registry)
    }
}
