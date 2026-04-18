import Foundation
import Testing
@testable import Archive

struct NoteSummaryTests {
    @Test
    func summaryDoesNotDuplicateTitleAsProperty() {
        let document = NoteDocument(
            id: NoteID(resourceIdentifier: "note", path: "/Archive/Test.md"),
            rootURL: URL(fileURLWithPath: "/Archive"),
            fileURL: URL(fileURLWithPath: "/Archive/Test.md"),
            relativePath: "Test.md",
            title: "Test title",
            frontmatter: FrontmatterDocument(segments: []),
            editableProperties: [
                EditableProperty(key: "title", kind: .text, value: .string("Test title"), isReadOnly: false, issue: nil),
                EditableProperty(key: "status", kind: .singleSelect, value: .string("Draft"), isReadOnly: false, issue: nil)
            ],
            body: "Body",
            createdAt: .distantPast,
            modifiedAt: .distantPast,
            versionToken: FileVersionToken(modificationDate: nil, fileSize: nil)
        )

        let summary = NoteSummary(document: document)

        #expect(summary.propertyValues["title"] == nil)
        #expect(summary.propertyValues["status"]?.stringValue == "Draft")
    }

    @Test
    func summaryKeepsFirstValueWhenPropertiesContainDuplicates() {
        let document = NoteDocument(
            id: NoteID(resourceIdentifier: "note", path: "/Archive/Test.md"),
            rootURL: URL(fileURLWithPath: "/Archive"),
            fileURL: URL(fileURLWithPath: "/Archive/Test.md"),
            relativePath: "Test.md",
            title: "Test title",
            frontmatter: FrontmatterDocument(segments: []),
            editableProperties: [
                EditableProperty(key: "status", kind: .singleSelect, value: .string("Draft"), isReadOnly: false, issue: nil),
                EditableProperty(key: "status", kind: .singleSelect, value: .string("Published"), isReadOnly: true, issue: "Duplicate"),
                EditableProperty(key: "priority", kind: .text, value: .string("High"), isReadOnly: false, issue: nil)
            ],
            body: "Body",
            createdAt: .distantPast,
            modifiedAt: .distantPast,
            versionToken: FileVersionToken(modificationDate: nil, fileSize: nil)
        )

        let summary = NoteSummary(document: document)

        #expect(summary.propertyValues["status"]?.stringValue == "Draft")
        #expect(summary.propertyValues["priority"]?.stringValue == "High")
    }
}
