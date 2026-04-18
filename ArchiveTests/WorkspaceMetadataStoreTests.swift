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

    @Test
    func metadataStoreLoadsLegacyViewPreferencesWithoutBoardKeys() async throws {
        let store = WorkspaceMetadataStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let metadataDirectory = root.appendingPathComponent(".archive", isDirectory: true)
        let viewsURL = metadataDirectory.appendingPathComponent("views.json")
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyJSON = """
        {
          "presentationMode" : "board",
          "version" : 1
        }
        """
        try Data(legacyJSON.utf8).write(to: viewsURL, options: .atomic)

        let loaded = try await store.loadViewPreferences(for: root)

        #expect(loaded.presentationMode == .board)
        #expect(loaded.savedBoardViews.isEmpty)
        #expect(loaded.selectedBoardViewID == nil)
    }

    @Test
    func metadataStoreFallsBackToDefaultsWhenRegistryJSONIsCorrupt() async throws {
        let store = WorkspaceMetadataStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let metadataDirectory = root.appendingPathComponent(".archive", isDirectory: true)
        let propertiesURL = metadataDirectory.appendingPathComponent("properties.json")
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("{not json".utf8).write(to: propertiesURL, options: .atomic)

        let loaded = try await store.loadPropertyRegistry(for: root)

        #expect(loaded == PropertyRegistry())
    }

    @Test
    func metadataStoreFallsBackToDefaultsWhenViewPreferencesJSONIsCorrupt() async throws {
        let store = WorkspaceMetadataStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let metadataDirectory = root.appendingPathComponent(".archive", isDirectory: true)
        let viewsURL = metadataDirectory.appendingPathComponent("views.json")
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("{not json".utf8).write(to: viewsURL, options: .atomic)

        let loaded = try await store.loadViewPreferences(for: root)

        #expect(loaded == WorkspaceViewPreferences())
    }

    @Test
    func snapshotMarksUnreadableFilesWithoutThrowing() async throws {
        let store = WorkspaceMetadataStore()
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let metadataDirectory = root.appendingPathComponent(".archive", isDirectory: true)
        let propertiesURL = metadataDirectory.appendingPathComponent("properties.json")
        try fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try Data("{}".utf8).write(to: propertiesURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: propertiesURL.path)

        let snapshot = await store.debugSnapshot(of: propertiesURL)

        #expect(snapshot == .unreadable)
    }

    @Test
    func debugWriteMetadataAcceptsUnreadableSnapshots() async throws {
        let store = WorkspaceMetadataStore()
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let registry = PropertyRegistry(definitions: [
            "status": PropertyDefinition(key: "status", kind: .singleSelect, options: ["Draft", "Published"])
        ])
        let viewPreferences = WorkspaceViewPreferences(presentationMode: .board)

        try await store.debugWriteMetadata(
            registry: registry,
            viewPreferences: viewPreferences,
            for: root,
            existingRegistry: .unreadable,
            existingViews: .unreadable
        )

        let loadedRegistry = try await store.loadPropertyRegistry(for: root)
        let loadedPreferences = try await store.loadViewPreferences(for: root)

        #expect(loadedRegistry == registry)
        #expect(loadedPreferences.presentationMode == .board)
    }
}
