import Foundation

struct SearchResult: Hashable, Sendable {
    let noteID: NoteID
    let score: Int
}

