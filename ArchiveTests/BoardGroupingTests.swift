import Foundation
import Testing
@testable import Archive

struct BoardGroupingTests {
    @Test
    func boardGroupingUsesConfiguredOptionsAndNoValueBucket() {
        let registry = PropertyRegistry(definitions: [
            "status": PropertyDefinition(key: "status", kind: .singleSelect, options: ["Draft", "Published"])
        ])

        let notes = [
            NoteSummary(
                id: NoteID(resourceIdentifier: "1", path: "/draft.md"),
                fileURL: URL(fileURLWithPath: "/draft.md"),
                relativePath: "draft.md",
                title: "Draft",
                bodyPreview: "",
                createdAt: .distantPast,
                modifiedAt: .distantPast,
                propertyValues: ["status": .string("Draft")]
            ),
            NoteSummary(
                id: NoteID(resourceIdentifier: "2", path: "/empty.md"),
                fileURL: URL(fileURLWithPath: "/empty.md"),
                relativePath: "empty.md",
                title: "Empty",
                bodyPreview: "",
                createdAt: .distantPast,
                modifiedAt: .distantPast,
                propertyValues: [:]
            )
        ]

        let boardView = SavedBoardView(
            name: "Status Board",
            groupByProperty: "status",
            laneOrder: ["Draft", "Published"]
        )

        let columns = BoardGroupingService.columns(for: notes, boardView: boardView, registry: registry)
        #expect(columns.map(\.title) == ["Draft", "Unassigned"])
        #expect(columns.first?.notes.count == 1)
        #expect(columns.last?.notes.count == 1)
    }
}
