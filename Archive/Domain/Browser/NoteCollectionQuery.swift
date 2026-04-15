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

enum BoardCardDensity: String, Codable, CaseIterable, Hashable, Sendable {
    case compact
    case comfortable
}

struct SavedBoardView: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var groupByProperty: String
    var laneOrder: [String]
    var density: BoardCardDensity

    init(
        id: UUID = UUID(),
        name: String,
        groupByProperty: String,
        laneOrder: [String] = [],
        density: BoardCardDensity = .comfortable
    ) {
        self.id = id
        self.name = name
        self.groupByProperty = groupByProperty
        self.laneOrder = laneOrder
        self.density = density
    }
}
