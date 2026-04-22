import Foundation
import Testing
@testable import Archive

@MainActor
struct WorkspaceSessionTests {
    @Test
    func updatePropertyDefinitionOptionsDeduplicatesAndSurvivesReload() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(
            """
            ---
            title: Legacy
            status: Retired
            ---

            Body
            """.utf8
        ).write(to: root.appendingPathComponent("Legacy.md"), options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        session.propertyRegistry = PropertyRegistry(definitions: [
            "status": PropertyDefinition(key: "status", kind: .singleSelect, options: ["Draft", "Published", "Retired"])
        ])
        session.viewPreferences = WorkspaceViewPreferences(
            presentationMode: .board,
            selectedBoardViewID: nil,
            savedBoardViews: [
                SavedBoardView(name: "Status Board", groupByProperty: "status", laneOrder: ["Draft", "Published", "Retired"])
            ]
        )

        await session.updatePropertyDefinitionOptions(
            for: "status",
            options: ["Draft", "Draft", " Ready ", "", "Published", "Ready"]
        )

        #expect(session.propertyRegistry.definition(for: "status")?.options == ["Draft", "Ready", "Published"])
        #expect(session.viewPreferences.savedBoardViews.first?.laneOrder == ["Draft", "Ready", "Published"])

        let storedRegistry = try await dependencies.metadataStore.loadPropertyRegistry(for: root)
        let storedViews = try await dependencies.metadataStore.loadViewPreferences(for: root)
        #expect(storedRegistry.definition(for: "status")?.options == ["Draft", "Ready", "Published"])
        #expect(storedViews.savedBoardViews.first?.laneOrder == ["Draft", "Ready", "Published"])

        let reloadedSnapshot = try await dependencies.workspaceRepository.loadWorkspace(at: root)
        #expect(reloadedSnapshot.propertyRegistry.definition(for: "status")?.options == ["Draft", "Ready", "Published"])
        #expect(reloadedSnapshot.viewPreferences.savedBoardViews.first?.laneOrder == ["Draft", "Ready", "Published"])
    }

    @Test
    func savingPersistedBoardOptionsDoesNotReintroduceLegacyStatusValues() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(
            """
            ---
            title: Legacy
            status: Retired
            ---

            Body
            """.utf8
        ).write(to: root.appendingPathComponent("Legacy.md"), options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        session.propertyRegistry = PropertyRegistry(definitions: [
            "status": PropertyDefinition(key: "status", kind: .singleSelect, options: ["Draft", "Published"])
        ])
        session.viewPreferences = WorkspaceViewPreferences(
            presentationMode: .board,
            selectedBoardViewID: nil,
            savedBoardViews: [
                SavedBoardView(name: "Status Board", groupByProperty: "status", laneOrder: ["Draft", "Published"])
            ]
        )

        let persistedOptions = session.propertyRegistry.definition(for: "status")?.options ?? []
        await session.updatePropertyDefinitionOptions(for: "status", options: persistedOptions)

        #expect(session.propertyRegistry.definition(for: "status")?.options == ["Draft", "Published"])
        #expect(session.viewPreferences.savedBoardViews.first?.laneOrder == ["Draft", "Published"])

        let reloadedSnapshot = try await dependencies.workspaceRepository.loadWorkspace(at: root)
        #expect(reloadedSnapshot.propertyRegistry.definition(for: "status")?.options == ["Draft", "Published"])
        #expect(reloadedSnapshot.viewPreferences.savedBoardViews.first?.laneOrder == ["Draft", "Published"])
    }

    @Test
    func singleSelectEditorOptionsOnlyIncludeTheCurrentDeprecatedValue() {
        let definition = PropertyDefinition(key: "status", kind: .singleSelect, options: ["Draft", "Published"])

        let legacyProperty = EditableProperty(
            key: "status",
            kind: .singleSelect,
            value: .string("Retired"),
            isReadOnly: false,
            issue: nil
        )
        let activeProperty = EditableProperty(
            key: "status",
            kind: .singleSelect,
            value: .string("Draft"),
            isReadOnly: false,
            issue: nil
        )

        #expect(PropertyEditorOptions.singleSelectOptions(for: legacyProperty, definition: definition) == ["Draft", "Published", "Retired"])
        #expect(PropertyEditorOptions.singleSelectOptions(for: activeProperty, definition: definition) == ["Draft", "Published"])
    }

    @Test
    func filteredNotesRespectsFolderPathBoundaries() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let barFolder = root.appendingPathComponent("Bar", isDirectory: true)
        let siblingFolder = root.appendingPathComponent("Bar-2", isDirectory: true)
        let now = Date()

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        session.browserState.selectedFolderURL = barFolder
        session.notes = [
            NoteSummary(
                id: NoteID(resourceIdentifier: "bar", path: barFolder.appendingPathComponent("Inside.md").path),
                fileURL: barFolder.appendingPathComponent("Inside.md"),
                relativePath: "Bar/Inside.md",
                title: "Inside",
                bodyPreview: "",
                createdAt: now,
                modifiedAt: now,
                propertyValues: [:]
            ),
            NoteSummary(
                id: NoteID(resourceIdentifier: "bar-2", path: siblingFolder.appendingPathComponent("Outside.md").path),
                fileURL: siblingFolder.appendingPathComponent("Outside.md"),
                relativePath: "Bar-2/Outside.md",
                title: "Outside",
                bodyPreview: "",
                createdAt: now,
                modifiedAt: now.addingTimeInterval(-60),
                propertyValues: [:]
            )
        ]

        #expect(session.filteredNotes.map(\.title) == ["Inside"])
    }

    @Test
    func updatePresentationModeRollsBackWhenPersistenceFails() async throws {
        let root = try makeTemporaryRoot()
        let metadataDirectory = root.appendingPathComponent(".archive", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: metadataDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: metadataDirectory.path)
            try? FileManager.default.removeItem(at: root)
        }

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        session.browserState.presentationMode = .list
        session.viewPreferences.presentationMode = .list

        await session.updatePresentationMode(.board)

        #expect(session.browserState.presentationMode == .list)
        #expect(session.viewPreferences.presentationMode == .list)
        #expect(session.errorMessage != nil)
    }

    @Test
    func renameCurrentNoteFlushesDirtyDraftBeforeRenaming() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Draft.md")
        try Data(
            """
            ---
            title: Draft
            ---

            Original body
            """.utf8
        ).write(to: originalURL, options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        let document = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))
        editorSession.draft.body = "Edited before rename"
        editorSession.markEdited()

        session.notes = [NoteSummary(document: document)]
        session.browserState.selectedNoteID = document.id
        session.editorSession = editorSession

        await session.renameCurrentNote(to: "Renamed.md")

        let renamedURL = root.appendingPathComponent("Renamed.md")
        #expect(FileManager.default.fileExists(atPath: renamedURL.path))
        #expect(FileManager.default.fileExists(atPath: originalURL.path) == false)

        let renamedDocument = try await dependencies.noteRepository.loadDocument(
            at: renamedURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        #expect(renamedDocument.body == "Edited before rename")
    }

    @Test
    func createNoteFlushesDirtyCurrentDraftBeforeOpeningTheNewNote() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Draft.md")
        try Data(
            """
            ---
            title: Draft
            ---

            Original body
            """.utf8
        ).write(to: originalURL, options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        await session.refresh()
        let document = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))
        editorSession.draft.title = "Draft Updated"
        editorSession.draft.body = "Edited before creating another note"
        editorSession.markEdited()

        session.browserState.selectedNoteID = document.id
        session.editorSession = editorSession

        await session.createNote()
        await session.waitForPendingBackgroundRenames()

        let updatedOriginalURL = root.appendingPathComponent("Draft-Updated.md")
        let newNoteURL = root.appendingPathComponent("Untitled.md")

        #expect(FileManager.default.fileExists(atPath: updatedOriginalURL.path))
        #expect(FileManager.default.fileExists(atPath: newNoteURL.path))

        let updatedOriginalDocument = try await dependencies.noteRepository.loadDocument(
            at: updatedOriginalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        #expect(updatedOriginalDocument.body == "Edited before creating another note")
        #expect(updatedOriginalDocument.title == "Draft Updated")

        #expect(session.editorSession?.originalNote.fileURL == newNoteURL)
        #expect(session.editorSession?.draft.title == "Untitled")
    }

    @Test
    func createSecondUntitledNotePreservesFirstUntitledDraft() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Untitled.md")
        try Data(
            """
            ---
            title: Untitled
            ---

            Original body
            """.utf8
        ).write(to: originalURL, options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        await session.refresh()
        let document = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))
        editorSession.draft.body = "Edited before creating the next untitled note"
        editorSession.markEdited()

        session.browserState.selectedNoteID = document.id
        session.editorSession = editorSession

        await session.createNote()
        await session.waitForPendingBackgroundRenames()

        let secondUntitledURL = root.appendingPathComponent("Untitled-2.md")
        let savedOriginalDocument = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )

        #expect(FileManager.default.fileExists(atPath: originalURL.path))
        #expect(FileManager.default.fileExists(atPath: secondUntitledURL.path))
        #expect(savedOriginalDocument.body == "Edited before creating the next untitled note")
        #expect(session.editorSession?.originalNote.fileURL == secondUntitledURL)
        #expect(session.editorSession?.draft.title == "Untitled")
    }

    @Test
    func createNoteWaitsForPendingRenameBeforeAllocatingNextUntitledFilename() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Untitled.md")
        try Data(
            """
            ---
            title: Untitled
            ---

            Original body
            """.utf8
        ).write(to: originalURL, options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        await session.refresh()
        let document = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))
        editorSession.draft.title = "Project Plan"
        editorSession.markEdited()

        session.browserState.selectedNoteID = document.id
        session.editorSession = editorSession

        await session.createNote()
        await session.waitForPendingBackgroundRenames()

        let renamedOriginalURL = root.appendingPathComponent("Project-Plan.md")
        let newNoteURL = root.appendingPathComponent("Untitled.md")

        #expect(FileManager.default.fileExists(atPath: renamedOriginalURL.path))
        #expect(FileManager.default.fileExists(atPath: newNoteURL.path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Untitled-2.md").path) == false)
        #expect(session.editorSession?.originalNote.fileURL == newNoteURL)
    }

    @Test
    func flushActiveNoteRenamesFileToMatchEditedTitle() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Untitled.md")
        try Data(
            """
            ---
            title: Untitled
            ---

            Original body
            """.utf8
        ).write(to: originalURL, options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        let document = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))
        editorSession.draft.title = "Ship Log"
        editorSession.draft.body = "Updated body"
        editorSession.markEdited()

        session.notes = [NoteSummary(document: document)]
        session.browserState.selectedNoteID = document.id
        session.editorSession = editorSession

        await session.flushActiveNote()
        await session.waitForPendingBackgroundRenames()

        let renamedURL = root.appendingPathComponent("Ship-Log.md")
        #expect(FileManager.default.fileExists(atPath: renamedURL.path))
        #expect(FileManager.default.fileExists(atPath: originalURL.path) == false)
        #expect(session.notes.count == 1)
        #expect(session.notes.first?.fileURL == renamedURL)
        #expect(session.editorSession?.originalNote.fileURL == renamedURL)
        let renamedDocument = try await dependencies.noteRepository.loadDocument(
            at: renamedURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        #expect(session.currentNoteSummary?.fileURL == renamedURL)
        #expect(session.editorSession?.noteID == renamedDocument.id)
        #expect(session.editorSession?.autosaveState == .saved)
        #expect(renamedDocument.title == "Ship Log")
        #expect(renamedDocument.body == "Updated body")
    }

    @Test
    func flushActiveNoteKeepsSavedContentWhenAutoRenameCollides() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Untitled.md")
        let existingURL = root.appendingPathComponent("Ship-Log.md")
        try Data(
            """
            ---
            title: Untitled
            ---

            Original body
            """.utf8
        ).write(to: originalURL, options: .atomic)
        try Data(
            """
            ---
            title: Ship Log
            ---

            Existing body
            """.utf8
        ).write(to: existingURL, options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        let document = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))
        editorSession.draft.title = "Ship Log"
        editorSession.draft.body = "Updated body"
        editorSession.markEdited()

        session.notes = [NoteSummary(document: document)]
        session.browserState.selectedNoteID = document.id
        session.editorSession = editorSession

        await session.flushActiveNote()
        await session.waitForPendingBackgroundRenames()

        let persistedOriginal = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let untouchedExisting = try await dependencies.noteRepository.loadDocument(
            at: existingURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )

        #expect(FileManager.default.fileExists(atPath: originalURL.path))
        #expect(session.errorMessage == "A note named \"Ship-Log.md\" already exists in that location.")
        #expect(persistedOriginal.title == "Ship Log")
        #expect(persistedOriginal.body == "Updated body")
        #expect(untouchedExisting.body == "Existing body")
        #expect(session.editorSession?.originalNote.fileURL == originalURL)
        #expect(session.editorSession?.autosaveState == .saved)
    }

    @Test
    func flushActiveNotePreservesDisplayTitleWhileEscapingFilenameSpaces() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Untitled.md")
        try Data(
            """
            ---
            title: Untitled
            ---

            Original body
            """.utf8
        ).write(to: originalURL, options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        let document = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))
        editorSession.draft.title = "Ship Log"
        editorSession.markEdited()

        session.notes = [NoteSummary(document: document)]
        session.browserState.selectedNoteID = document.id
        session.editorSession = editorSession

        await session.flushActiveNote()
        await session.waitForPendingBackgroundRenames()

        let renamedURL = root.appendingPathComponent("Ship-Log.md")
        let renamedDocument = try await dependencies.noteRepository.loadDocument(
            at: renamedURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )

        #expect(renamedDocument.title == "Ship Log")
        #expect(session.editorSession?.draft.title == "Ship Log")
        #expect(session.editorSession?.originalNote.fileURL == renamedURL)
    }

    @Test
    func flushActiveNoteDoesNotRenameWhenTitleIsBlank() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Untitled.md")
        try Data(
            """
            ---
            title: Untitled
            ---

            Original body
            """.utf8
        ).write(to: originalURL, options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        let document = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))
        editorSession.draft.title = "   "
        editorSession.draft.body = "# From Body Heading\n\nUpdated body"
        editorSession.markEdited()

        session.notes = [NoteSummary(document: document)]
        session.browserState.selectedNoteID = document.id
        session.editorSession = editorSession

        await session.flushActiveNote()

        let persistedDocument = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )

        #expect(FileManager.default.fileExists(atPath: originalURL.path))
        #expect(session.errorMessage == nil)
        #expect(persistedDocument.title == "From Body Heading")
        #expect(persistedDocument.body == "# From Body Heading\n\nUpdated body")
    }

    @Test
    func blankTitleSaveCancelsPendingBackgroundRename() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Untitled.md")
        try Data(
            """
            ---
            title: Untitled
            ---

            Original body
            """.utf8
        ).write(to: originalURL, options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        let document = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))
        editorSession.draft.title = "Ship Log"
        editorSession.markEdited()

        session.notes = [NoteSummary(document: document)]
        session.browserState.selectedNoteID = document.id
        session.editorSession = editorSession

        await session.flushActiveNote()

        editorSession.draft.title = "   "
        editorSession.draft.body = "# Untitled\n\nOriginal body"
        editorSession.markEdited()

        await session.flushActiveNote()
        await session.waitForPendingBackgroundRenames()

        #expect(FileManager.default.fileExists(atPath: originalURL.path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Ship-Log.md").path) == false)
    }

    @Test
    func moveCurrentNoteFlushesDirtyDraftBeforeMoving() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Draft.md")
        try Data(
            """
            ---
            title: Draft
            ---

            Original body
            """.utf8
        ).write(to: originalURL, options: .atomic)

        let destinationFolder = root.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        let document = try await dependencies.noteRepository.loadDocument(
            at: originalURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))
        editorSession.draft.body = "Edited before move"
        editorSession.markEdited()

        session.notes = [NoteSummary(document: document)]
        session.browserState.selectedNoteID = document.id
        session.editorSession = editorSession

        await session.moveCurrentNote(to: destinationFolder)

        let movedURL = destinationFolder.appendingPathComponent("Draft.md")
        #expect(FileManager.default.fileExists(atPath: movedURL.path))
        #expect(FileManager.default.fileExists(atPath: originalURL.path) == false)

        let movedDocument = try await dependencies.noteRepository.loadDocument(
            at: movedURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        #expect(movedDocument.body == "Edited before move")
    }

    @Test
    func deleteCurrentNoteClearsSelectionAndEditor() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = root.appendingPathComponent("Draft.md")
        try Data(
            """
            ---
            title: Draft
            ---

            Original body
            """.utf8
        ).write(to: noteURL, options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        let document = try await dependencies.noteRepository.loadDocument(
            at: noteURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )

        session.notes = [NoteSummary(document: document)]
        session.browserState.selectedNoteID = document.id
        session.editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))

        await session.deleteCurrentNote()

        #expect(FileManager.default.fileExists(atPath: noteURL.path) == false)
        #expect(session.browserState.selectedNoteID == nil)
        #expect(session.editorSession == nil)
        #expect(session.notes.isEmpty)
    }

    @Test
    func moveNotePreservesDirtyDraftForCurrentEditor() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = root.appendingPathComponent("Draft.md")
        try Data(
            """
            ---
            title: Draft
            status: Draft
            ---

            Original body
            """.utf8
        ).write(to: noteURL, options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        let boardView = SavedBoardView(name: "Status Board", groupByProperty: "status", laneOrder: ["Draft", "Done"])
        session.propertyRegistry = PropertyRegistry(definitions: [
            "status": PropertyDefinition(key: "status", kind: .singleSelect, options: ["Draft", "Done"])
        ])
        session.viewPreferences = WorkspaceViewPreferences(
            presentationMode: .board,
            selectedBoardViewID: boardView.id,
            savedBoardViews: [boardView]
        )
        session.browserState.selectedBoardViewID = boardView.id

        let document = try await dependencies.noteRepository.loadDocument(
            at: noteURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        let editorSession = EditorSession(note: document, exportService: ExportService(renderer: MarkdownHTMLRenderer()))
        editorSession.draft.body = "Edited before board move"
        editorSession.markEdited()

        session.notes = [NoteSummary(document: document)]
        session.browserState.selectedNoteID = document.id
        session.editorSession = editorSession

        await session.moveNote(NoteSummary(document: document), toBoardValue: "Done")

        let updatedDocument = try await dependencies.noteRepository.loadDocument(
            at: noteURL,
            relativeTo: root,
            registry: session.propertyRegistry
        )
        #expect(updatedDocument.body == "Edited before board move")
        #expect(updatedDocument.editableProperties.first(where: { $0.key == "status" })?.value.stringValue == "Done")
    }

    @Test
    func refreshResetsSelectedFolderWhenItNoLongerExists() async throws {
        let root = try makeTemporaryRoot()
        let missingFolder = root.appendingPathComponent("Missing", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("Body".utf8).write(to: root.appendingPathComponent("Note.md"), options: .atomic)

        let dependencies = makeDependencies()
        let session = makeSession(
            root: root,
            workspaceRepository: dependencies.workspaceRepository,
            noteRepository: dependencies.noteRepository,
            defaults: dependencies.defaults
        )
        defer {
            dependencies.defaults.removePersistentDomain(forName: dependencies.suiteName)
        }

        session.browserState.selectedFolderURL = missingFolder

        await session.refresh()

        #expect(session.browserState.selectedFolderURL == root)
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeDependencies() -> (
        suiteName: String,
        defaults: UserDefaults,
        metadataStore: WorkspaceMetadataStore,
        noteRepository: NoteRepository,
        workspaceRepository: WorkspaceRepository
    ) {
        let suiteName = "WorkspaceSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let fileAccess = FileCoordinatorIO()
        let metadataStore = WorkspaceMetadataStore()
        let noteRepository = NoteRepository(fileAccess: fileAccess)
        let workspaceRepository = WorkspaceRepository(
            fileAccess: fileAccess,
            noteRepository: noteRepository,
            metadataStore: metadataStore,
            searchIndex: SearchIndex()
        )

        return (suiteName, defaults, metadataStore, noteRepository, workspaceRepository)
    }

    private func makeSession(
        root: URL,
        workspaceRepository: WorkspaceRepository,
        noteRepository: NoteRepository,
        defaults: UserDefaults
    ) -> WorkspaceSession {
        WorkspaceSession(
            rootURL: root,
            bookmarkData: Data(),
            appSettings: AppSettings(defaults: defaults),
            workspaceRepository: workspaceRepository,
            noteRepository: noteRepository,
            exportService: ExportService(renderer: MarkdownHTMLRenderer())
        )
    }
}
