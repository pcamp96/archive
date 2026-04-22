import Foundation
import Testing
@testable import Archive

struct WorkspaceRepositoryTests {
    @Test
    func createFolderSanitizesNamesAndAddsSuffixes() async throws {
        let repository = makeRepository()
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try await repository.createFolder(in: root, name: "Sprint/Notes")
        let second = try await repository.createFolder(in: root, name: "Sprint/Notes")

        #expect(first.lastPathComponent == "Sprint-Notes")
        #expect(second.lastPathComponent == "Sprint-Notes 2")
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test
    func createNoteCreatesFirstNoteAndSuffixesSecondOne() async throws {
        let repository = makeRepository()
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try await repository.createNote(in: root, title: "Untitled")
        let second = try await repository.createNote(in: root, title: "Untitled")

        #expect(first.lastPathComponent == "Untitled.md")
        #expect(second.lastPathComponent == "Untitled-2.md")
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))

        let firstContents = try String(contentsOf: first)
        let secondContents = try String(contentsOf: second)
        #expect(firstContents.contains("title: Untitled"))
        #expect(secondContents.contains("title: Untitled"))
    }

    @Test
    func createNotePreservesDisplayTitleWhileEscapingFilenameSpaces() async throws {
        let repository = makeRepository()
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = try await repository.createNote(in: root, title: "Ship Log")
        let contents = try String(contentsOf: noteURL)

        #expect(noteURL.lastPathComponent == "Ship-Log.md")
        #expect(contents.contains("title: Ship Log"))
    }

    @Test
    func renameNoteDoesNotOverwriteExistingDestination() async throws {
        let repository = makeRepository()
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Original.md")
        let existingURL = root.appendingPathComponent("Existing.md")
        try makeMarkdownNote(at: originalURL, contents: "Original")
        try makeMarkdownNote(at: existingURL, contents: "Existing")

        do {
            _ = try await repository.renameNote(at: originalURL, to: "Existing.md")
            Issue.record("Expected rename collision to throw.")
        } catch let error as WorkspaceRepositoryError {
            #expect(error == .noteAlreadyExists("Existing.md"))
        }

        let existingContents = try String(contentsOf: existingURL)
        #expect(existingContents == "Existing")
    }

    @Test
    func renameNoteSanitizesSeparatorsAndPreservesDotsInTitles() async throws {
        let repository = makeRepository()
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Original.md")
        try makeMarkdownNote(at: originalURL, contents: "Original")

        let renamedURL = try await repository.renameNote(at: originalURL, to: "Release/Notes v0.0.1.md")

        #expect(renamedURL.lastPathComponent == "Release-Notes-v0.0.1.md")
        #expect(FileManager.default.fileExists(atPath: renamedURL.path))
        #expect(FileManager.default.fileExists(atPath: originalURL.path) == false)
    }

    @Test
    func renameNoteAllowsCaseOnlyFilenameChanges() async throws {
        let repository = makeRepository()
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Ship Log.md")
        try makeMarkdownNote(at: originalURL, contents: "Original")

        let renamedURL = try await repository.renameNote(at: originalURL, to: "ship log")
        let directoryContents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let filenames = directoryContents.map(\.lastPathComponent)

        #expect(renamedURL.lastPathComponent == "ship-log.md")
        #expect(FileManager.default.fileExists(atPath: renamedURL.path))
        #expect(filenames == ["ship-log.md"])
    }

    @Test
    func moveNoteDoesNotOverwriteExistingDestination() async throws {
        let repository = makeRepository()
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceFolder = root.appendingPathComponent("Source", isDirectory: true)
        let destinationFolder = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let originalURL = sourceFolder.appendingPathComponent("Note.md")
        let existingURL = destinationFolder.appendingPathComponent("Note.md")
        try makeMarkdownNote(at: originalURL, contents: "Original")
        try makeMarkdownNote(at: existingURL, contents: "Existing")

        do {
            _ = try await repository.moveNote(at: originalURL, to: destinationFolder)
            Issue.record("Expected move collision to throw.")
        } catch let error as WorkspaceRepositoryError {
            #expect(error == .noteAlreadyExists("Note.md"))
        }

        let existingContents = try String(contentsOf: existingURL)
        #expect(existingContents == "Existing")
    }

    @Test
    func loadWorkspaceCreatesDefaultBoardFromStatusProperty() async throws {
        let repository = makeRepository()
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeMarkdownNote(
            at: root.appendingPathComponent("Draft.md"),
            contents: """
            ---
            title: Draft
            status: Draft
            ---

            Body
            """
        )

        let snapshot = try await repository.loadWorkspace(at: root)

        #expect(snapshot.viewPreferences.savedBoardViews.count == 1)
        #expect(snapshot.viewPreferences.selectedBoardViewID == snapshot.viewPreferences.savedBoardViews.first?.id)
        #expect(snapshot.viewPreferences.savedBoardViews.first?.groupByProperty == "status")
        #expect(snapshot.viewPreferences.savedBoardViews.first?.laneOrder == ["Draft"])
    }

    @Test
    func loadWorkspaceFallsBackToListWhenBoardModeHasNoSavedBoards() async throws {
        let repository = makeRepository()
        let metadataStore = WorkspaceMetadataStore()
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeMarkdownNote(
            at: root.appendingPathComponent("Note.md"),
            contents: """
            ---
            title: Note
            ---

            Body
            """
        )

        try await metadataStore.saveViewPreferences(
            WorkspaceViewPreferences(
                presentationMode: .board,
                selectedBoardViewID: UUID(),
                savedBoardViews: []
            ),
            for: root
        )

        let snapshot = try await repository.loadWorkspace(at: root)

        #expect(snapshot.viewPreferences.presentationMode == .list)
        #expect(snapshot.viewPreferences.selectedBoardViewID == nil)
        #expect(snapshot.viewPreferences.savedBoardViews.isEmpty)
    }

    @Test
    func loadWorkspaceRepairsInvalidSelectedBoardViewID() async throws {
        let repository = makeRepository()
        let metadataStore = WorkspaceMetadataStore()
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeMarkdownNote(
            at: root.appendingPathComponent("Note.md"),
            contents: """
            ---
            title: Note
            status: Draft
            ---

            Body
            """
        )

        let validBoard = SavedBoardView(name: "Status Board", groupByProperty: "status", laneOrder: ["Draft"])
        try await metadataStore.saveViewPreferences(
            WorkspaceViewPreferences(
                presentationMode: .board,
                selectedBoardViewID: UUID(),
                savedBoardViews: [validBoard]
            ),
            for: root
        )

        let snapshot = try await repository.loadWorkspace(at: root)
        let storedPreferences = try await metadataStore.loadViewPreferences(for: root)

        #expect(snapshot.viewPreferences.selectedBoardViewID == validBoard.id)
        #expect(storedPreferences.selectedBoardViewID == validBoard.id)
    }

    @Test
    func loadWorkspaceSucceedsWhenMetadataWritesFail() async throws {
        let repository = makeRepository()
        let fileManager = FileManager.default
        let root = try makeTemporaryRoot()
        let metadataDirectory = root.appendingPathComponent(".archive", isDirectory: true)
        try fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: metadataDirectory.path)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: metadataDirectory.path)
            try? fileManager.removeItem(at: root)
        }

        try makeMarkdownNote(
            at: root.appendingPathComponent("Draft.md"),
            contents: """
            ---
            title: Draft
            status: Draft
            ---

            Body
            """
        )

        let snapshot = try await repository.loadWorkspace(at: root)

        #expect(snapshot.propertyRegistry.definition(for: "status")?.options == ["Draft"])
        #expect(snapshot.viewPreferences.savedBoardViews.first?.groupByProperty == "status")
    }

    @Test
    func loadWorkspaceSkipsUnreadableChildFolders() async throws {
        let repository = makeRepository()
        let fileManager = FileManager.default
        let root = try makeTemporaryRoot()
        let restrictedFolder = root.appendingPathComponent("Restricted", isDirectory: true)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: restrictedFolder.path)
            try? fileManager.removeItem(at: root)
        }

        try makeMarkdownNote(
            at: root.appendingPathComponent("Readable.md"),
            contents: """
            ---
            title: Readable
            ---

            Body
            """
        )
        try fileManager.createDirectory(at: restrictedFolder, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restrictedFolder.path)

        let snapshot = try await repository.loadWorkspace(at: root)

        #expect(snapshot.notes.map(\.title) == ["Readable"])
        #expect(snapshot.folderTree.children.isEmpty)
    }

    @Test
    func loadWorkspaceHandlesDuplicateFrontmatterKeys() async throws {
        let repository = makeRepository()
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeMarkdownNote(
            at: root.appendingPathComponent("Duplicate.md"),
            contents: """
            ---
            title: Duplicate
            status: Draft
            status: Published
            ---

            Body
            """
        )

        let snapshot = try await repository.loadWorkspace(at: root)

        #expect(snapshot.notes.count == 1)
        #expect(snapshot.notes.first?.propertyValues["status"]?.stringValue == "Draft")
    }

    private func makeRepository() -> WorkspaceRepository {
        let fileAccess = FileCoordinatorIO()
        let noteRepository = NoteRepository(fileAccess: fileAccess)
        return WorkspaceRepository(
            fileAccess: fileAccess,
            noteRepository: noteRepository,
            metadataStore: WorkspaceMetadataStore(),
            searchIndex: SearchIndex()
        )
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeMarkdownNote(at url: URL, contents: String) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
    }
}
