import Foundation

enum NotesPresentationMode: String, Codable, CaseIterable, Hashable, Sendable {
    case list
    case board

    mutating func toggle() {
        self = self == .list ? .board : .list
    }
}

struct BoardColumn: Identifiable, Hashable, Sendable {
    let key: String?
    let title: String
    let notes: [NoteSummary]

    var id: String { key ?? "__none__" }
}

