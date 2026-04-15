import Foundation
import Observation

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
            return note.fileURL.path.hasPrefix(folder.path)
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
        guard editorSession?.noteID != summary.id else {
            browserState.selectedNoteID = summary.id
            return
        }

        Task {
            do {
                if let editorSession, editorSession.isDirty {
                    await flushActiveNote()
                }
                let document = try await noteRepository.loadDocument(at: summary.fileURL, relativeTo: rootURL, registry: propertyRegistry)
                let editor = EditorSession(note: document, exportService: exportService)
                browserState.selectedNoteID = summary.id
                editorSession = editor
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func createNote() async {
        do {
            let targetFolder = browserState.selectedFolderURL ?? rootURL
            let createdURL = try await workspaceRepository.createNote(in: targetFolder, title: "Untitled")
            await refresh()
            if let summary = notes.first(where: { $0.fileURL == createdURL }) {
                openNote(summary)
            }
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

        do {
            let savedDocument = try await noteRepository.saveDraft(editorSession.draft, original: editorSession.originalNote, registry: propertyRegistry)
            editorSession.applySavedDocument(savedDocument)
            replaceLocalNote(with: savedDocument)
        } catch let NoteRepositoryError.versionConflict(message) {
            editorSession.conflictMessage = message
            editorSession.autosaveState = .conflict
        } catch {
            errorMessage = error.localizedDescription
            editorSession.autosaveState = .error(error.localizedDescription)
        }
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

    func updatePresentationMode(_ mode: NotesPresentationMode) {
        browserState.presentationMode = mode
        viewPreferences.presentationMode = mode
        Task {
            try? await workspaceRepository.saveViewPreferences(viewPreferences, for: rootURL)
        }
    }

    func updateBoardSelection(_ id: UUID) {
        browserState.selectedBoardViewID = id
        viewPreferences.selectedBoardViewID = id
        Task {
            try? await workspaceRepository.saveViewPreferences(viewPreferences, for: rootURL)
        }
    }

    func moveNote(_ note: NoteSummary, toBoardValue value: String?) async {
        guard let key = activeBoardView?.groupByProperty else { return }

        do {
            let document = try await noteRepository.loadDocument(at: note.fileURL, relativeTo: rootURL, registry: propertyRegistry)
            var draft = NoteDraft(note: document)
            let kind = propertyRegistry.definition(for: key)?.kind ?? .singleSelect
            draft.upsertProperty(
                EditableProperty(
                    key: key,
                    kind: kind,
                    value: .string(value ?? ""),
                    isReadOnly: false,
                    issue: nil
                )
            )
            _ = try await noteRepository.saveDraft(draft, original: document, registry: propertyRegistry)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameCurrentNote(to filename: String) async {
        guard let currentNoteSummary else { return }

        do {
            let destination = try await workspaceRepository.renameNote(
                at: currentNoteSummary.fileURL,
                to: filename
            )
            await refresh()
            if let summary = notes.first(where: { $0.fileURL == destination }) {
                openNote(summary)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveCurrentNote(to folderURL: URL) async {
        guard let currentNoteSummary else { return }

        do {
            let destination = try await workspaceRepository.moveNote(
                at: currentNoteSummary.fileURL,
                to: folderURL
            )
            await refresh()
            if let summary = notes.first(where: { $0.fileURL == destination }) {
                openNote(summary)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCurrentNote() async {
        guard let currentNoteSummary else { return }

        do {
            try await workspaceRepository.deleteNote(at: currentNoteSummary.fileURL)
            browserState.selectedNoteID = nil
            editorSession = nil
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
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

        ensureBoardViewExists(for: definition)
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

    private func ensureBoardViewExists(for definition: PropertyDefinition) {
        guard definition.isBoardEligible else { return }
        guard viewPreferences.savedBoardViews.contains(where: { $0.groupByProperty == definition.key }) == false else { return }

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
        Task {
            try? await workspaceRepository.saveViewPreferences(viewPreferences, for: rootURL)
        }
    }

    private func replaceLocalNote(with document: NoteDocument) {
        let summary = NoteSummary(document: document)
        if let index = notes.firstIndex(where: { $0.id == summary.id }) {
            notes[index] = summary
        } else {
            notes.append(summary)
        }
        notes.sort(using: KeyPathComparator(\.modifiedAt, order: .reverse))
        browserState.selectedNoteID = summary.id
        Task {
            await workspaceRepository.updateSearchIndex(with: summary)
            await refreshSearch()
        }
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
    let noteID: NoteID
    private let exportService: ExportService

    var draft: NoteDraft
    var conflictMessage: String?
    var selectedMarkdownText = ""
    var autosaveState: AutosaveState = .saved
    var autosaveNonce = 0
    var displayModeOverride: MarkdownDisplayMode?
    private var lastSavedDraft: NoteDraft

    init(note: NoteDocument, exportService: ExportService) {
        self.originalNote = note
        self.noteID = note.id
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

    func copyMarkdownSelection() {
        let text = selectedMarkdownText.isEmpty ? draft.body : selectedMarkdownText
        exportService.copyPlainText(text)
    }

    func copyHTMLSelection() {
        let text = selectedMarkdownText.isEmpty ? draft.body : selectedMarkdownText
        try? exportService.copyHTMLFragment(markdown: text)
    }
}
