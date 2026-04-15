import Foundation

struct FrontmatterEntry: Hashable, Sendable {
    var key: String
    var rawContent: String
    var parsedValue: PropertyValue?
    var issue: String?
}

enum FrontmatterSegment: Hashable, Sendable {
    case raw(String)
    case entry(FrontmatterEntry)
}

struct FrontmatterDocument: Hashable, Sendable {
    var segments: [FrontmatterSegment] = []

    func titleValue() -> String? {
        editableProperties(using: PropertyRegistry()).first(where: { $0.key == "title" })?.value.stringValue
    }

    func editableProperties(using registry: PropertyRegistry) -> [EditableProperty] {
        var properties: [EditableProperty] = []
        var seenKeys = Set<String>()

        for segment in segments {
            guard case .entry(let entry) = segment else { continue }
            guard seenKeys.insert(entry.key).inserted else {
                properties.append(
                    EditableProperty(
                        key: entry.key,
                        kind: .unsupported,
                        value: .raw(entry.rawContent),
                        isReadOnly: true,
                        issue: "Duplicate frontmatter key."
                    )
                )
                continue
            }

            if let parsedValue = entry.parsedValue {
                let definition = registry.definition(for: entry.key)
                let inferred = PropertyInference.inferKind(for: parsedValue)
                properties.append(
                    EditableProperty(
                        key: entry.key,
                        kind: definition?.kind ?? inferred,
                        value: parsedValue,
                        isReadOnly: false,
                        issue: entry.issue
                    )
                )
            } else {
                properties.append(
                    EditableProperty(
                        key: entry.key,
                        kind: .unsupported,
                        value: .raw(entry.rawContent),
                        isReadOnly: true,
                        issue: entry.issue ?? "This YAML value is preserved but not editable in V1."
                    )
                )
            }
        }

        return properties
    }
}

