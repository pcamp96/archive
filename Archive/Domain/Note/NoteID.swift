import Foundation

struct NoteID: Sendable, Codable, Identifiable {
    let resourceIdentifier: String
    let path: String

    var id: String { normalizedPath }

    private var normalizedPath: String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

extension NoteID: Hashable {
    static func == (lhs: NoteID, rhs: NoteID) -> Bool {
        lhs.normalizedPath == rhs.normalizedPath
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(normalizedPath)
    }
}

struct FileVersionToken: Hashable, Sendable, Codable {
    let modificationDate: Date?
    let fileSize: Int64?
}
