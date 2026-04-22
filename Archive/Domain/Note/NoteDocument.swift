import Foundation

struct NoteSummary: Identifiable, Hashable, Sendable {
    let id: NoteID
    let fileURL: URL
    let relativePath: String
    let title: String
    let bodyPreview: String
    let searchableBodyText: String
    let createdAt: Date
    let modifiedAt: Date
    let propertyValues: [String: PropertyValue]

    init(
        id: NoteID,
        fileURL: URL,
        relativePath: String,
        title: String,
        bodyPreview: String,
        searchableBodyText: String? = nil,
        createdAt: Date,
        modifiedAt: Date,
        propertyValues: [String: PropertyValue]
    ) {
        self.id = id
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.title = title
        self.bodyPreview = bodyPreview
        self.searchableBodyText = searchableBodyText ?? bodyPreview
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.propertyValues = propertyValues
    }
}

extension NoteSummary {
    init(document: NoteDocument) {
        self.init(
            id: document.id,
            fileURL: document.fileURL,
            relativePath: document.relativePath,
            title: document.title,
            bodyPreview: document.body
                .components(separatedBy: .newlines)
                .first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false })?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            searchableBodyText: document.body,
            createdAt: document.createdAt,
            modifiedAt: document.modifiedAt,
            propertyValues: document.editableProperties.summaryPropertyMap()
        )
    }
}

extension Sequence where Element == EditableProperty {
    func summaryPropertyMap() -> [String: PropertyValue] {
        var properties: [String: PropertyValue] = [:]

        for property in self where property.key != "title" {
            guard properties[property.key] == nil else { continue }
            properties[property.key] = property.value
        }

        return properties
    }
}

struct NoteDocument: Hashable, Sendable {
    let id: NoteID
    let rootURL: URL
    let fileURL: URL
    let relativePath: String
    let title: String
    let frontmatter: FrontmatterDocument
    let editableProperties: [EditableProperty]
    let body: String
    let createdAt: Date
    let modifiedAt: Date
    let versionToken: FileVersionToken
}

struct NoteDraft: Hashable, Sendable {
    let id: NoteID
    let rootURL: URL
    let fileURL: URL
    let relativePath: String
    let baseVersionToken: FileVersionToken
    var title: String
    var properties: [EditableProperty]
    var body: String

    init(note: NoteDocument) {
        self.id = note.id
        self.rootURL = note.rootURL
        self.fileURL = note.fileURL
        self.relativePath = note.relativePath
        self.baseVersionToken = note.versionToken
        self.title = note.title
        self.properties = note.editableProperties.filter { $0.key != "title" }
        self.body = note.body
    }

    mutating func upsertProperty(_ property: EditableProperty) {
        if let index = properties.firstIndex(where: { $0.key == property.key }) {
            properties[index] = property
        } else {
            properties.append(property)
        }
    }
}
