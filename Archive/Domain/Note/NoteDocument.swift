import Foundation

struct NoteSummary: Identifiable, Hashable, Sendable {
    let id: NoteID
    let fileURL: URL
    let relativePath: String
    let title: String
    let bodyPreview: String
    let createdAt: Date
    let modifiedAt: Date
    let propertyValues: [String: PropertyValue]
}

extension NoteSummary {
    init(document: NoteDocument) {
        let propertyMap = Dictionary(uniqueKeysWithValues: document.editableProperties.map { ($0.key, $0.value) })
        self.init(
            id: document.id,
            fileURL: document.fileURL,
            relativePath: document.relativePath,
            title: document.title,
            bodyPreview: document.body
                .components(separatedBy: .newlines)
                .first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false })?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            createdAt: document.createdAt,
            modifiedAt: document.modifiedAt,
            propertyValues: propertyMap
        )
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
