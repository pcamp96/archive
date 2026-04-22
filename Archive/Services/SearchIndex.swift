import Foundation

actor SearchIndex {
    private struct Entry: Sendable {
        let noteID: NoteID
        let title: String
        let body: String
        let propertyText: String
        let modifiedAt: Date
    }

    private var entries: [NoteID: Entry] = [:]

    func rebuild(with notes: [NoteSummary]) {
        entries = Dictionary(uniqueKeysWithValues: notes.map { note in
            (
                note.id,
                Entry(
                    noteID: note.id,
                    title: normalized(note.title),
                    body: normalized(note.searchableBodyText),
                    propertyText: normalized(note.propertyValues.values.map(\.stringValue).joined(separator: " ")),
                    modifiedAt: note.modifiedAt
                )
            )
        })
    }

    func update(with note: NoteSummary) {
        entries[note.id] = Entry(
            noteID: note.id,
            title: normalized(note.title),
            body: normalized(note.searchableBodyText),
            propertyText: normalized(note.propertyValues.values.map(\.stringValue).joined(separator: " ")),
            modifiedAt: note.modifiedAt
        )
    }

    func search(query: String) -> [SearchResult] {
        let normalizedQuery = normalized(query)
        guard normalizedQuery.isEmpty == false else { return [] }

        return entries.values.compactMap { entry in
            let score: Int
            if entry.title == normalizedQuery {
                score = 400
            } else if entry.title.hasPrefix(normalizedQuery) {
                score = 300
            } else if entry.title.contains(normalizedQuery) {
                score = 200
            } else if entry.body.contains(normalizedQuery) || entry.propertyText.contains(normalizedQuery) {
                score = 100
            } else {
                return nil
            }
            return SearchResult(noteID: entry.noteID, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                let leftDate = entries[lhs.noteID]?.modifiedAt ?? .distantPast
                let rightDate = entries[rhs.noteID]?.modifiedAt ?? .distantPast
                return leftDate > rightDate
            }
            return lhs.score > rhs.score
        }
    }

    private func normalized(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
