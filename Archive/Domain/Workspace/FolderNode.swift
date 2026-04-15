import Foundation

struct FolderNode: Identifiable, Hashable, Sendable {
    let url: URL
    var children: [FolderNode]

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct WorkspaceSnapshot: Sendable {
    let rootURL: URL
    let folderTree: FolderNode
    let notes: [NoteSummary]
    let propertyRegistry: PropertyRegistry
    let viewPreferences: WorkspaceViewPreferences
}

struct WorkspaceViewPreferences: Codable, Hashable, Sendable {
    var version = 1
    var presentationMode: NotesPresentationMode = .list
    var boardPropertyKey: String?
}

