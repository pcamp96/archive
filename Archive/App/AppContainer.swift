import Foundation

@MainActor
@Observable
final class AppContainer {
    let fileAccess: FileCoordinatorIO
    let bookmarkStore: BookmarkStore
    let metadataStore: WorkspaceMetadataStore
    let noteRepository: NoteRepository
    let workspaceRepository: WorkspaceRepository
    let searchIndex: SearchIndex
    let exportService: ExportService
    let publishService: PublishService
    let appSession: AppSession

    init() {
        let fileAccess = FileCoordinatorIO()
        let bookmarkStore = BookmarkStore()
        let metadataStore = WorkspaceMetadataStore()
        let noteRepository = NoteRepository(fileAccess: fileAccess)
        let searchIndex = SearchIndex()
        let workspaceRepository = WorkspaceRepository(
            fileAccess: fileAccess,
            noteRepository: noteRepository,
            metadataStore: metadataStore,
            searchIndex: searchIndex
        )
        let exportService = ExportService(renderer: MarkdownHTMLRenderer())
        let publishService = PublishService()

        self.fileAccess = fileAccess
        self.bookmarkStore = bookmarkStore
        self.metadataStore = metadataStore
        self.noteRepository = noteRepository
        self.searchIndex = searchIndex
        self.workspaceRepository = workspaceRepository
        self.exportService = exportService
        self.publishService = publishService
        self.appSession = AppSession(
            bookmarkStore: bookmarkStore,
            workspaceRepository: workspaceRepository,
            noteRepository: noteRepository,
            exportService: exportService
        )
    }
}

