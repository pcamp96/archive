import AppKit
import Foundation
import Observation

private actor BackgroundRenameWorker {
    private let workspaceRepository: WorkspaceRepository
    private let noteRepository: NoteRepository

    init(workspaceRepository: WorkspaceRepository, noteRepository: NoteRepository) {
        self.workspaceRepository = workspaceRepository
        self.noteRepository = noteRepository
    }

    func renameDocumentIfNeeded(
        _ document: NoteDocument,
        to title: String,
        rootURL: URL,
        registry: PropertyRegistry
    ) async throws -> NoteDocument? {
        let destination = try await workspaceRepository.renameNote(at: document.fileURL, to: title)
        guard destination.standardizedFileURL != document.fileURL.standardizedFileURL else {
            return nil
        }

        try Task.checkCancellation()
        return try await noteRepository.loadDocument(at: destination, relativeTo: rootURL, registry: registry)
    }
}

@MainActor
@Observable
final class WorkspaceSession {
    let rootURL: URL
    let bookmarkData: Data
    let appSettings: AppSettings

    nonisolated private let workspaceRepository: WorkspaceRepository
    nonisolated private let noteRepository: NoteRepository
    private let exportService: ExportService

    var browserState = NotesBrowserState()
    var editorSession: EditorSession?
    var folderTree: FolderNode?
    var notes: [NoteSummary] = []
    var propertyRegistry = PropertyRegistry()
    var viewPreferences = WorkspaceViewPreferences()
    var isLoading = false
    var errorMessage: String?
    private var noteOpenRequestNonce = 0
    private let backgroundRenameWorker: BackgroundRenameWorker
    private var backgroundRenameTickets: [String: UUID] = [:]
    private var backgroundRenameTitles: [String: String] = [:]
    private var backgroundRenameTasks: [String: Task<Void, Never>] = [:]

    init(
        rootURL: URL,
        bookmarkData: Data,
        appSettings: AppSettings,
        workspaceRepository: WorkspaceRepository,
        noteRepository: NoteRepository,
        exportService: ExportService
    ) {
        self.rootURL = rootURL
        self.bookmarkData = bookmarkData
        self.appSettings = appSettings
        self.workspaceRepository = workspaceRepository
        self.noteRepository = noteRepository
        self.exportService = exportService
        self.backgroundRenameWorker = BackgroundRenameWorker(
            workspaceRepository: workspaceRepository,
            noteRepository: noteRepository
        )
    }

    var selectedNoteID: NoteID? {
        get { browserState.selectedNoteID }
        set { browserState.selectedNoteID = newValue }
    }

    var selectedFolderURL: URL? {
        get { browserState.selectedFolderURL }
        set { browserState.selectedFolderURL = newValue }
    }

    var filteredNotes: [NoteSummary] {
        let baseNotes = notes.filter { note in
            guard let folder = browserState.selectedFolderURL else { return true }
            return note.fileURL.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/")
                || note.fileURL.standardizedFileURL.deletingLastPathComponent() == folder.standardizedFileURL
        }

        let query = browserState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return baseNotes.sorted(using: KeyPathComparator(\.modifiedAt, order: .reverse))
        }

        let allowedIDs = Set(baseNotes.map(\.id))
        let results = browserState.searchResults.filter { allowedIDs.contains($0.noteID) }
        let resultMap = Dictionary(uniqueKeysWithValues: results.map { ($0.noteID, $0) })
        return baseNotes
            .filter { resultMap[$0.id] != nil }
            .sorted {
                let lhs = resultMap[$0.id]?.score ?? 0
                let rhs = resultMap[$1.id]?.score ?? 0
                if lhs == rhs {
                    if $0.modifiedAt == $1.modifiedAt {
                        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                    return $0.modifiedAt > $1.modifiedAt
                }
                return lhs > rhs
            }
    }

    var boardColumns: [BoardColumn] {
        guard let activeBoardView else { return [] }
        return BoardGroupingService.columns(for: filteredNotes, boardView: activeBoardView, registry: propertyRegistry)
    }

    var currentNoteSummary: NoteSummary? {
        guard let selectedNoteID else { return nil }
        return notes.first(where: { $0.id == selectedNoteID })
    }

    var currentEditorNoteSummary: NoteSummary? {
        guard let editorNoteID = editorSession?.noteID else { return nil }
        return notes.first(where: { $0.id == editorNoteID })
    }

    var activeBoardView: SavedBoardView? {
        if let selectedID = browserState.selectedBoardViewID ?? viewPreferences.selectedBoardViewID {
            return viewPreferences.savedBoardViews.first(where: { $0.id == selectedID })
        }
        return viewPreferences.savedBoardViews.first
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await workspaceRepository.loadWorkspace(at: rootURL)
            folderTree = snapshot.folderTree
            notes = snapshot.notes.sorted(using: KeyPathComparator(\.modifiedAt, order: .reverse))
            propertyRegistry = snapshot.propertyRegistry
            viewPreferences = snapshot.viewPreferences
            browserState.presentationMode = viewPreferences.presentationMode
            browserState.selectedBoardViewID = viewPreferences.selectedBoardViewID ?? viewPreferences.savedBoardViews.first?.id
            if let selectedFolderURL = browserState.selectedFolderURL,
               folderTree?.containsFolder(at: selectedFolderURL) == false {
                browserState.selectedFolderURL = rootURL
            }
            if browserState.selectedFolderURL == nil {
                browserState.selectedFolderURL = rootURL
            }
            if let selectedNoteID, notes.contains(where: { $0.id == selectedNoteID }) == false {
                browserState.selectedNoteID = nil
                editorSession = nil
            }
            await refreshSearch()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openNote(_ summary: NoteSummary) {
        noteOpenRequestNonce += 1
        let openRequestNonce = noteOpenRequestNonce

        Task {
            await openNote(summary, requestNonce: openRequestNonce)
        }
    }

    func selectNote(_ summary: NoteSummary) {
        browserState.selectedNoteID = summary.id
    }

    func revealNote(_ summary: NoteSummary) {
        browserState.selectedNoteID = summary.id
        openNote(summary)
    }

    func createNote(in folderURL: URL? = nil) async {
        do {
            if let activeNoteID = editorSession?.noteID {
                guard await flushActiveEditorIfNeeded(
                    matching: activeNoteID,
                    fallbackMessage: "Save the current note before creating another one."
                ) else {
                    return
                }
                await waitForPendingBackgroundRenames()
            }
            let targetFolder = folderURL ?? browserState.selectedFolderURL ?? rootURL
            let createdURL = try await workspaceRepository.createNote(in: targetFolder, title: "Untitled")
            noteOpenRequestNonce += 1
            let openRequestNonce = noteOpenRequestNonce
            let document = try await noteRepository.loadDocument(at: createdURL, relativeTo: rootURL, registry: propertyRegistry)
            await refresh()
            guard noteOpenRequestNonce == openRequestNonce else { return }
            browserState.selectedNoteID = document.id
            editorSession = EditorSession(note: document, exportService: exportService)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createFolder(named name: String, in parentURL: URL? = nil) async {
        do {
            let targetFolder = parentURL ?? browserState.selectedFolderURL ?? rootURL
            let createdURL = try await workspaceRepository.createFolder(in: targetFolder, name: name)
            browserState.selectedFolderURL = createdURL
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveActiveNote() async {
        await flushActiveNote()
    }

    func flushActiveNote() async {
        guard let editorSession else { return }
        guard editorSession.isDirty else { return }
        editorSession.autosaveState = .saving
        let draftToSave = editorSession.draft
        let noteID = editorSession.noteID
        let originalFileURL = editorSession.originalNote.fileURL
        cancelPendingBackgroundRename(for: noteID.resourceIdentifier)

        do {
            let persistedDocument = try await noteRepository.saveDraft(draftToSave, original: editorSession.originalNote, registry: propertyRegistry)

            guard let currentEditorSession = self.editorSession, currentEditorSession.noteID == noteID else {
                replaceLocalNote(
                    with: persistedDocument,
                    replacingNoteID: noteID,
                    replacingFileURL: originalFileURL,
                    shouldSelect: browserState.selectedNoteID == noteID
                )
                queueBackgroundRenameIfNeeded(for: persistedDocument, expectedSavedDraft: draftToSave)
                return
            }

            currentEditorSession.reconcileSavedDocument(persistedDocument, expectedSavedDraft: draftToSave)
            replaceLocalNote(
                with: persistedDocument,
                replacingNoteID: noteID,
                replacingFileURL: originalFileURL,
                shouldSelect: true
            )
            queueBackgroundRenameIfNeeded(for: persistedDocument, expectedSavedDraft: draftToSave)
        } catch let NoteRepositoryError.versionConflict(message) {
            editorSession.conflictMessage = message
            editorSession.autosaveState = .conflict
        } catch {
            errorMessage = error.localizedDescription
            editorSession.autosaveState = .error(error.localizedDescription)
        }
    }

    private func openNote(_ summary: NoteSummary, requestNonce: Int) async {
        do {
            guard noteOpenRequestNonce == requestNonce else { return }

            if let currentEditorSession = editorSession, currentEditorSession.noteID == summary.id {
                browserState.selectedNoteID = summary.id
                return
            }

            if let activeNoteID = editorSession?.noteID {
                guard await flushActiveEditorIfNeeded(
                    matching: activeNoteID,
                    fallbackMessage: "Save the current note before opening another note."
                ) else {
                    return
                }
            }

            guard noteOpenRequestNonce == requestNonce else { return }
            browserState.selectedNoteID = summary.id
            let document = try await noteRepository.loadDocument(at: summary.fileURL, relativeTo: rootURL, registry: propertyRegistry)
            guard noteOpenRequestNonce == requestNonce, browserState.selectedNoteID == summary.id else { return }
            editorSession = EditorSession(note: document, exportService: exportService)
        } catch {
            guard noteOpenRequestNonce == requestNonce else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func flushActiveEditorIfNeeded(matching noteID: NoteID, fallbackMessage: String) async -> Bool {
        guard let editorSession, editorSession.noteID == noteID else { return true }
        guard editorSession.isDirty else { return true }

        await flushActiveNote()

        guard let editorSession = self.editorSession, editorSession.noteID == noteID else { return true }
        guard editorSession.isDirty == false else {
            switch self.editorSession?.autosaveState {
            case .conflict:
                errorMessage = editorSession.conflictMessage ?? fallbackMessage
            case .error(let message):
                errorMessage = message
            default:
                errorMessage = fallbackMessage
            }
            return false
        }

        return true
    }

    private func queueBackgroundRenameIfNeeded(for document: NoteDocument, expectedSavedDraft: NoteDraft) {
        let title = expectedSavedDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let renameKey = document.id.resourceIdentifier
        guard title.isEmpty == false else {
            cancelPendingBackgroundRename(for: renameKey)
            return
        }

        let ticket = UUID()
        backgroundRenameTickets[renameKey] = ticket
        backgroundRenameTitles[renameKey] = title
        backgroundRenameTasks[renameKey]?.cancel()

        let rootURL = self.rootURL
        let registry = self.propertyRegistry
        let task = Task(priority: .utility) {
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                guard shouldRunBackgroundRename(for: renameKey, title: title, ticket: ticket) else {
                    finishBackgroundRenameTask(for: renameKey, ticket: ticket)
                    return
                }

                let renamedDocument = try await backgroundRenameWorker.renameDocumentIfNeeded(
                    document,
                    to: title,
                    rootURL: rootURL,
                    registry: registry
                )
                guard let renamedDocument else {
                    guard backgroundRenameTickets[renameKey] == ticket else { return }
                    finishBackgroundRenameTask(for: renameKey, ticket: ticket)
                    return
                }

                applyBackgroundRename(
                    renamedDocument,
                    replacing: document,
                    expectedSavedDraft: expectedSavedDraft,
                    renameKey: renameKey,
                    ticket: ticket
                )
            } catch is CancellationError {
                finishBackgroundRenameTask(for: renameKey, ticket: ticket)
            } catch {
                guard backgroundRenameTickets[renameKey] == ticket else { return }
                errorMessage = error.localizedDescription
                finishBackgroundRenameTask(for: renameKey, ticket: ticket)
            }
        }

        backgroundRenameTasks[renameKey] = task
    }

    private func applyBackgroundRename(
        _ renamedDocument: NoteDocument,
        replacing originalDocument: NoteDocument,
        expectedSavedDraft: NoteDraft,
        renameKey: String,
        ticket: UUID
    ) {
        guard backgroundRenameTickets[renameKey] == ticket else { return }

        if let currentEditorSession = editorSession,
           currentEditorSession.noteID.resourceIdentifier == renameKey {
            currentEditorSession.reconcileSavedDocument(renamedDocument, expectedSavedDraft: expectedSavedDraft)
        }

        let shouldSelectRenamedNote = editorSession?.noteID.resourceIdentifier == renameKey
            || browserState.selectedNoteID?.resourceIdentifier == renameKey
        replaceLocalNote(
            with: renamedDocument,
            replacingNoteID: originalDocument.id,
            replacingFileURL: originalDocument.fileURL,
            shouldSelect: shouldSelectRenamedNote
        )
        finishBackgroundRenameTask(for: renameKey, ticket: ticket)
    }

    private func finishBackgroundRenameTask(for renameKey: String, ticket: UUID) {
        guard backgroundRenameTickets[renameKey] == ticket else { return }
        backgroundRenameTickets.removeValue(forKey: renameKey)
        backgroundRenameTitles.removeValue(forKey: renameKey)
        backgroundRenameTasks.removeValue(forKey: renameKey)
    }

    private func cancelPendingBackgroundRename(for renameKey: String) {
        backgroundRenameTickets.removeValue(forKey: renameKey)
        backgroundRenameTitles.removeValue(forKey: renameKey)
        backgroundRenameTasks[renameKey]?.cancel()
        backgroundRenameTasks.removeValue(forKey: renameKey)
    }

    private func shouldRunBackgroundRename(for renameKey: String, title: String, ticket: UUID) -> Bool {
        backgroundRenameTickets[renameKey] == ticket && backgroundRenameTitles[renameKey] == title
    }

    func waitForPendingBackgroundRenames() async {
        let tasks = Array(backgroundRenameTasks.values)
        for task in tasks {
            await task.value
        }
    }

    private func waitForPendingBackgroundRename(for noteID: NoteID) async {
        let renameKey = noteID.resourceIdentifier
        guard let task = backgroundRenameTasks[renameKey] else { return }
        await task.value
    }

    func autosaveIfNeeded(for session: EditorSession) async {
        guard editorSession?.noteID == session.noteID else { return }
        guard session.isDirty else { return }
        do {
            try await Task.sleep(for: .milliseconds(700))
        } catch {
            return
        }
        guard editorSession?.noteID == session.noteID else { return }
        await flushActiveNote()
    }

    func refreshSearch() async {
        let trimmedQuery = browserState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            browserState.searchResults = []
            return
        }

        browserState.searchResults = await workspaceRepository.search(
            query: trimmedQuery,
            rootURL: rootURL
        )
    }

    func updatePresentationMode(_ mode: NotesPresentationMode) async {
        let previousBrowserMode = browserState.presentationMode
        let previousViewPreferences = viewPreferences
        browserState.presentationMode = mode
        viewPreferences.presentationMode = mode
        do {
            try await workspaceRepository.saveViewPreferences(viewPreferences, for: rootURL)
        } catch {
            browserState.presentationMode = previousBrowserMode
            viewPreferences = previousViewPreferences
            errorMessage = error.localizedDescription
        }
    }

    func updateBoardSelection(_ id: UUID) async {
        let previousBrowserSelection = browserState.selectedBoardViewID
        let previousViewPreferences = viewPreferences
        browserState.selectedBoardViewID = id
        viewPreferences.selectedBoardViewID = id
        do {
            try await workspaceRepository.saveViewPreferences(viewPreferences, for: rootURL)
        } catch {
            browserState.selectedBoardViewID = previousBrowserSelection
            viewPreferences = previousViewPreferences
            errorMessage = error.localizedDescription
        }
    }

    func moveNote(_ note: NoteSummary, toBoardValue value: String?) async {
        guard let key = activeBoardView?.groupByProperty else { return }
        let kind = propertyRegistry.definition(for: key)?.kind ?? .singleSelect
        let updatedProperty = EditableProperty(
            key: key,
            kind: kind,
            value: .string(value ?? ""),
            isReadOnly: false,
            issue: nil
        )

        do {
            if let editorSession, editorSession.noteID == note.id {
                editorSession.draft.upsertProperty(updatedProperty)
                editorSession.markEdited()
                guard await flushActiveEditorIfNeeded(
                    matching: note.id,
                    fallbackMessage: "Save the current note before updating its board column."
                ) else {
                    return
                }
                await refresh()
                return
            }

            let document = try await noteRepository.loadDocument(at: note.fileURL, relativeTo: rootURL, registry: propertyRegistry)
            var draft = NoteDraft(note: document)
            draft.upsertProperty(updatedProperty)
            _ = try await noteRepository.saveDraft(draft, original: document, registry: propertyRegistry)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameCurrentNote(to filename: String) async {
        guard let currentNoteSummary else { return }
        await renameNote(currentNoteSummary, to: filename)
    }

    func renameNote(_ note: NoteSummary, to filename: String) async {
        guard let preparedNoteSummary = await prepareNoteForFileMutation(
            note,
            fallbackMessage: "Save the current note before renaming or moving it."
        ) else { return }

        do {
            let destination = try await workspaceRepository.renameNote(
                at: preparedNoteSummary.fileURL,
                to: filename
            )
            await refresh()
            if let summary = notes.first(where: { $0.fileURL == destination }) {
                revealNote(summary)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveCurrentNote(to folderURL: URL) async {
        guard let currentNoteSummary else { return }
        await moveNote(currentNoteSummary, to: folderURL)
    }

    func moveNote(_ note: NoteSummary, to folderURL: URL) async {
        guard let preparedNoteSummary = await prepareNoteForFileMutation(
            note,
            fallbackMessage: "Save the current note before renaming or moving it."
        ) else { return }

        do {
            let destination = try await workspaceRepository.moveNote(
                at: preparedNoteSummary.fileURL,
                to: folderURL
            )
            await refresh()
            if let summary = notes.first(where: { $0.fileURL == destination }) {
                revealNote(summary)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCurrentNote() async {
        guard let currentNoteSummary else { return }
        await deleteNote(currentNoteSummary)
    }

    func deleteNote(_ note: NoteSummary) async {
        guard let preparedNoteSummary = await prepareNoteForFileMutation(
            note,
            fallbackMessage: "Save the current note before deleting it."
        ) else { return }

        do {
            try await workspaceRepository.deleteNote(at: preparedNoteSummary.fileURL)
            if browserState.selectedNoteID == preparedNoteSummary.id {
                browserState.selectedNoteID = nil
            }
            if editorSession?.noteID == preparedNoteSummary.id {
                editorSession = nil
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealNoteInFinder(_ note: NoteSummary) {
        NSWorkspace.shared.activateFileViewerSelecting([note.fileURL])
    }

    func copyRelativePath(for note: NoteSummary) {
        exportService.copyPlainText(note.relativePath)
    }

    func createProperty(_ state: PropertyCreationState, addToCurrentNote: Bool) async {
        guard let definition = state.definition else { return }

        propertyRegistry.definitions[definition.key] = definition
        do {
            try await workspaceRepository.savePropertyRegistry(propertyRegistry, for: rootURL)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        if addToCurrentNote, let editorSession {
            editorSession.draft.upsertProperty(
                EditableProperty(
                    key: definition.key,
                    kind: definition.kind,
                    value: state.initialValue,
                    isReadOnly: false,
                    issue: nil
                )
            )
            editorSession.markEdited()
        }

        await ensureBoardViewExists(for: definition)
    }

    func updatePropertyDefinitionOptions(for key: String, options: [String]) async {
        guard var definition = propertyRegistry.definitions[key] else { return }

        let normalizedOptions = normalizedUniqueOptions(from: options)
        var updatedRegistry = propertyRegistry
        var updatedViewPreferences = viewPreferences

        definition.options = normalizedOptions
        updatedRegistry.definitions[key] = definition

        for index in updatedViewPreferences.savedBoardViews.indices where updatedViewPreferences.savedBoardViews[index].groupByProperty == key {
            updatedViewPreferences.savedBoardViews[index].laneOrder = normalizedOptions
        }

        do {
            try await workspaceRepository.saveMetadata(
                registry: updatedRegistry,
                viewPreferences: updatedViewPreferences,
                for: rootURL
            )
            propertyRegistry = updatedRegistry
            viewPreferences = updatedViewPreferences
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createDefaultWorkflowProperty() async {
        let statusProperty = PropertyCreationState(
            key: "status",
            kind: .singleSelect,
            optionsText: "Idea, Draft, In Review, Ready, Published"
        )
        await createProperty(statusProperty, addToCurrentNote: false)
        browserState.presentationMode = .board
        viewPreferences.presentationMode = .board
        if let boardID = viewPreferences.savedBoardViews.first(where: { $0.groupByProperty == "status" })?.id {
            browserState.selectedBoardViewID = boardID
            viewPreferences.selectedBoardViewID = boardID
        }
        do {
            try await workspaceRepository.saveViewPreferences(viewPreferences, for: rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureBoardViewExists(for definition: PropertyDefinition) async {
        guard definition.isBoardEligible else { return }
        guard viewPreferences.savedBoardViews.contains(where: { $0.groupByProperty == definition.key }) == false else { return }

        let previousViewPreferences = viewPreferences
        let previousSelectedBoardID = browserState.selectedBoardViewID
        let boardView = SavedBoardView(
            name: "\(definition.key.capitalized) Board",
            groupByProperty: definition.key,
            laneOrder: definition.options
        )
        viewPreferences.savedBoardViews.append(boardView)
        if viewPreferences.selectedBoardViewID == nil {
            viewPreferences.selectedBoardViewID = boardView.id
            browserState.selectedBoardViewID = boardView.id
        }
        do {
            try await workspaceRepository.saveViewPreferences(viewPreferences, for: rootURL)
        } catch {
            viewPreferences = previousViewPreferences
            browserState.selectedBoardViewID = previousSelectedBoardID
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedUniqueOptions(from options: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for option in options {
            let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            guard seen.insert(trimmed).inserted else { continue }
            normalized.append(trimmed)
        }

        return normalized
    }

    private func replaceLocalNote(
        with document: NoteDocument,
        replacingNoteID: NoteID? = nil,
        replacingFileURL: URL? = nil,
        shouldSelect: Bool
    ) {
        let summary = NoteSummary(document: document)
        let normalizedReplacingFileURL = replacingFileURL?.standardizedFileURL
        if let index = notes.firstIndex(where: {
            $0.fileURL.standardizedFileURL == summary.fileURL.standardizedFileURL
                || $0.id == summary.id
                || (replacingNoteID != nil && $0.id == replacingNoteID)
                || (normalizedReplacingFileURL != nil && $0.fileURL.standardizedFileURL == normalizedReplacingFileURL)
        }) {
            notes[index] = summary
        } else {
            notes.append(summary)
        }
        notes.removeAll { existing in
            existing.id != summary.id
                && existing.fileURL.standardizedFileURL != summary.fileURL.standardizedFileURL
                && ((replacingNoteID != nil && existing.id == replacingNoteID)
                    || (normalizedReplacingFileURL != nil && existing.fileURL.standardizedFileURL == normalizedReplacingFileURL))
        }
        notes.sort(using: KeyPathComparator(\.modifiedAt, order: .reverse))
        if shouldSelect {
            browserState.selectedNoteID = summary.id
        }
        Task {
            await workspaceRepository.updateSearchIndex(with: summary)
            await refreshSearch()
        }
    }

    private func prepareNoteForFileMutation(_ note: NoteSummary, fallbackMessage: String) async -> NoteSummary? {
        guard await flushActiveEditorIfNeeded(
            matching: note.id,
            fallbackMessage: fallbackMessage
        ) else {
            return nil
        }
        await waitForPendingBackgroundRename(for: note.id)
        return notes.first(where: { $0.id == note.id }) ?? note
    }
}

@MainActor
@Observable
final class NotesBrowserState {
    var selectedFolderURL: URL?
    var selectedNoteID: NoteID?
    var searchQuery = ""
    var searchResults: [SearchResult] = []
    var presentationMode: NotesPresentationMode = .list
    var selectedBoardViewID: UUID?
}

enum AutosaveState: Equatable {
    case saved
    case dirty
    case saving
    case conflict
    case error(String)

    var label: String {
        switch self {
        case .saved:
            return "Saved"
        case .dirty:
            return "Edited"
        case .saving:
            return "Saving…"
        case .conflict:
            return "Conflict"
        case .error:
            return "Save Error"
        }
    }
}

@MainActor
@Observable
final class EditorSession {
    var originalNote: NoteDocument
    private let exportService: ExportService

    var draft: NoteDraft
    var conflictMessage: String?
    var selectedMarkdownText = ""
    var autosaveState: AutosaveState = .saved
    var autosaveNonce = 0
    var displayModeOverride: MarkdownDisplayMode?
    private var lastSavedDraft: NoteDraft

    var noteID: NoteID {
        originalNote.id
    }

    init(note: NoteDocument, exportService: ExportService) {
        self.originalNote = note
        self.exportService = exportService
        self.draft = NoteDraft(note: note)
        self.lastSavedDraft = NoteDraft(note: note)
    }

    var isDirty: Bool {
        draft != lastSavedDraft
    }

    func markEdited() {
        conflictMessage = nil
        autosaveState = .dirty
        autosaveNonce += 1
    }

    func applySavedDocument(_ document: NoteDocument) {
        originalNote = document
        draft = NoteDraft(note: document)
        lastSavedDraft = draft
        autosaveState = .saved
        conflictMessage = nil
    }

    func reconcileSavedDocument(_ document: NoteDocument, expectedSavedDraft: NoteDraft) {
        let currentDraft = draft
        originalNote = document

        if currentDraft.matchesEditableContent(of: expectedSavedDraft) {
            applySavedDocument(document)
            return
        }

        var rebasedDraft = NoteDraft(note: document)
        rebasedDraft.title = currentDraft.title
        rebasedDraft.properties = currentDraft.properties
        rebasedDraft.body = currentDraft.body

        draft = rebasedDraft
        lastSavedDraft = NoteDraft(note: document)
        autosaveState = .dirty
        conflictMessage = nil
    }

    func copyMarkdownSelection() {
        let text = selectedMarkdownText.isEmpty ? draft.body : selectedMarkdownText
        exportService.copyPlainText(text)
    }

    func copyHTMLSelection() {
        let text = selectedMarkdownText.isEmpty ? draft.body : selectedMarkdownText
        try? exportService.copyHTMLFragment(markdown: text)
    }
}

private extension NoteDraft {
    func matchesEditableContent(of other: NoteDraft) -> Bool {
        title == other.title
            && properties == other.properties
            && body == other.body
    }
}
