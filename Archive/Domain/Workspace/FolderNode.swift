import Foundation

struct FolderNode: Identifiable, Hashable, Sendable {
    let url: URL
    var children: [FolderNode]

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    func containsFolder(at candidateURL: URL) -> Bool {
        let normalizedCandidate = candidateURL.standardizedFileURL
        if url.standardizedFileURL == normalizedCandidate {
            return true
        }

        return children.contains { $0.containsFolder(at: normalizedCandidate) }
    }
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
    var selectedBoardViewID: UUID?
    var savedBoardViews: [SavedBoardView] = []

    private enum CodingKeys: String, CodingKey {
        case version
        case presentationMode
        case selectedBoardViewID
        case savedBoardViews
    }

    init(
        version: Int = 1,
        presentationMode: NotesPresentationMode = .list,
        selectedBoardViewID: UUID? = nil,
        savedBoardViews: [SavedBoardView] = []
    ) {
        self.version = version
        self.presentationMode = presentationMode
        self.selectedBoardViewID = selectedBoardViewID
        self.savedBoardViews = savedBoardViews
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        presentationMode = try container.decodeIfPresent(NotesPresentationMode.self, forKey: .presentationMode) ?? .list
        selectedBoardViewID = try container.decodeIfPresent(UUID.self, forKey: .selectedBoardViewID)
        savedBoardViews = try container.decodeIfPresent([SavedBoardView].self, forKey: .savedBoardViews) ?? []
    }
}
