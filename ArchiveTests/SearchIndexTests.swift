import Testing
@testable import Archive

struct SearchIndexTests {
    @Test
    func searchRanksTitleMatchesBeforeBodyMatches() async {
        let index = SearchIndex()
        let now = Date()
        await index.rebuild(with: [
            NoteSummary(
                id: NoteID(resourceIdentifier: "1", path: "/a.md"),
                fileURL: URL(fileURLWithPath: "/a.md"),
                relativePath: "a.md",
                title: "Archive Launch Plan",
                bodyPreview: "Body text",
                createdAt: now,
                modifiedAt: now,
                propertyValues: [:]
            ),
            NoteSummary(
                id: NoteID(resourceIdentifier: "2", path: "/b.md"),
                fileURL: URL(fileURLWithPath: "/b.md"),
                relativePath: "b.md",
                title: "Planning",
                bodyPreview: "archive appears here",
                createdAt: now,
                modifiedAt: now.addingTimeInterval(-60),
                propertyValues: [:]
            )
        ])

        let results = await index.search(query: "archive")
        #expect(results.first?.noteID.resourceIdentifier == "1")
        #expect(results.dropFirst().first?.noteID.resourceIdentifier == "2")
    }
}
