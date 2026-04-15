import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    enum PresentedError: Identifiable {
        case message(title: String, details: String)

        var id: String {
            switch self {
            case .message(let title, let details):
                return "\(title)|\(details)"
            }
        }

        var title: String {
            switch self {
            case .message(let title, _):
                return title
            }
        }

        var details: String {
            switch self {
            case .message(_, let details):
                return details
            }
        }
    }

    private let bookmarkStore: BookmarkStore
    private let workspaceRepository: WorkspaceRepository
    private let noteRepository: NoteRepository
    private let exportService: ExportService

    var workspaceSession: WorkspaceSession?
    var recentWorkspaces: [RecentWorkspace] = []
    var presentedError: PresentedError?

    init(
        bookmarkStore: BookmarkStore,
        workspaceRepository: WorkspaceRepository,
        noteRepository: NoteRepository,
        exportService: ExportService
    ) {
        self.bookmarkStore = bookmarkStore
        self.workspaceRepository = workspaceRepository
        self.noteRepository = noteRepository
        self.exportService = exportService
        self.recentWorkspaces = bookmarkStore.loadRecents()
    }

    func restoreLastWorkspaceIfPossible() async {
        guard workspaceSession == nil, let recent = bookmarkStore.loadLastWorkspace() else { return }
        do {
            try await openWorkspace(at: recent.url, bookmarkData: recent.bookmarkData)
        } catch {
            presentedError = .message(
                title: "Workspace Unavailable",
                details: "Archive could not reopen the previous workspace. Select it again to continue.\n\n\(error.localizedDescription)"
            )
        }
    }

    func refreshActiveWorkspace() async {
        guard let workspaceSession else { return }
        await workspaceSession.refresh()
    }

    func promptForWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Open Workspace"
        panel.message = "Choose a folder that contains markdown notes."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                try await openWorkspace(at: url, bookmarkData: nil)
            } catch {
                presentedError = .message(
                    title: "Unable to Open Workspace",
                    details: error.localizedDescription
                )
            }
        }
    }

    func openRecentWorkspace(_ recent: RecentWorkspace) {
        Task {
            do {
                try await openWorkspace(at: recent.url, bookmarkData: recent.bookmarkData)
            } catch {
                presentedError = .message(
                    title: "Unable to Open Workspace",
                    details: error.localizedDescription
                )
            }
        }
    }

    func createNote() {
        guard let workspaceSession else { return }
        Task {
            await workspaceSession.createNote()
        }
    }

    func saveCurrentNote() {
        guard let workspaceSession else { return }
        Task {
            await workspaceSession.saveActiveNote()
        }
    }

    func switchPresentationMode() {
        workspaceSession?.browserState.presentationMode.toggle()
    }

    private func openWorkspace(at url: URL, bookmarkData: Data?) async throws {
        let resolvedBookmark = try bookmarkStore.makeBookmark(for: url, existing: bookmarkData)
        bookmarkStore.recordWorkspace(url: url, bookmarkData: resolvedBookmark)
        recentWorkspaces = bookmarkStore.loadRecents()

        let session = WorkspaceSession(
            rootURL: url,
            bookmarkData: resolvedBookmark,
            workspaceRepository: workspaceRepository,
            noteRepository: noteRepository,
            exportService: exportService
        )
        workspaceSession = session
        await session.refresh()
    }
}

struct RecentWorkspace: Codable, Hashable, Sendable, Identifiable {
    let path: String
    let bookmarkData: Data

    var id: String { path }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var displayName: String {
        url.lastPathComponent
    }
}

