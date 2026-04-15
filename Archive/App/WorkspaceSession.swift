import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceSession {
    let rootURL: URL
    let bookmarkData: Data

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
        workspaceRepository: WorkspaceRepository,
        noteRepository: NoteRepository,
        exportService: ExportService
    ) {
        self.rootURL = rootURL
        self.bookmarkData = bookmarkData
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
        BoardGroupingService.columns(
            for: filteredNotes,
            propertyKey: browserState.boardPropertyKey ?? viewPreferences.boardPropertyKey ?? "status",
            registry: propertyRegistry
        )
    }

    var currentNoteSummary: NoteSummary? {
        guard let selectedNoteID else { return nil }
        return notes.first(where: { $0.id == selectedNoteID })
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
            browserState.boardPropertyKey = viewPreferences.boardPropertyKey ?? propertyRegistry.defaultBoardPropertyKey
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
        guard let editorSession else { return }

        do {
            let savedDocument = try await noteRepository.saveDraft(editorSession.draft, original: editorSession.originalNote, registry: propertyRegistry)
            self.editorSession = EditorSession(note: savedDocument, exportService: exportService)
            await refresh()
            if let summary = notes.first(where: { $0.id == savedDocument.id }) {
                browserState.selectedNoteID = summary.id
            }
        } catch let NoteRepositoryError.versionConflict(message) {
            editorSession.conflictMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
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

    func updateBoardProperty(_ key: String) {
        browserState.boardPropertyKey = key
        viewPreferences.boardPropertyKey = key
        Task {
            try? await workspaceRepository.saveViewPreferences(viewPreferences, for: rootURL)
        }
    }

    func moveNote(_ note: NoteSummary, toBoardValue value: String?) async {
        guard let key = browserState.boardPropertyKey ?? viewPreferences.boardPropertyKey ?? propertyRegistry.defaultBoardPropertyKey else { return }

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
}

@MainActor
@Observable
final class NotesBrowserState {
    var selectedFolderURL: URL?
    var selectedNoteID: NoteID?
    var searchQuery = ""
    var searchResults: [SearchResult] = []
    var presentationMode: NotesPresentationMode = .list
    var boardPropertyKey: String?
}

@MainActor
@Observable
final class EditorSession {
    let originalNote: NoteDocument
    let noteID: NoteID
    private let exportService: ExportService

    var draft: NoteDraft
    var conflictMessage: String?
    var selectedMarkdownText = ""

    init(note: NoteDocument, exportService: ExportService) {
        self.originalNote = note
        self.noteID = note.id
        self.exportService = exportService
        self.draft = NoteDraft(note: note)
    }

    var isDirty: Bool {
        draft != NoteDraft(note: originalNote)
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
