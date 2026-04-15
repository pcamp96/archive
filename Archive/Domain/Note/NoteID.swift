import Foundation

struct NoteID: Hashable, Sendable, Codable, Identifiable {
    let resourceIdentifier: String
    let path: String

    var id: String { resourceIdentifier }
}

struct FileVersionToken: Hashable, Sendable, Codable {
    let modificationDate: Date?
    let fileSize: Int64?
}

