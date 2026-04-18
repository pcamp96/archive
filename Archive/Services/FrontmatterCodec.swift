import Foundation
import Yams

struct FrontmatterCodec {
    func serializedFrontmatter(
        from document: FrontmatterDocument,
        title: String,
        properties: [EditableProperty]
    ) -> String? {
        var consumedKeys = Set<String>()
        var chunks: [String] = []
        let titleValue = title.trimmingCharacters(in: .whitespacesAndNewlines)

        var editableMap: [String: EditableProperty] = [:]
        for property in properties where property.isReadOnly == false {
            guard editableMap[property.key] == nil else { continue }
            editableMap[property.key] = property
        }

        for segment in document.segments {
            switch segment {
            case .raw(let raw):
                chunks.append(raw)
            case .entry(let entry):
                if entry.key == "title" {
                    if titleValue.isEmpty == false {
                        chunks.append(render(key: "title", property: EditableProperty(key: "title", kind: .text, value: .string(titleValue), isReadOnly: false, issue: nil)))
                    }
                    consumedKeys.insert("title")
                    continue
                }

                if consumedKeys.contains(entry.key) {
                    chunks.append(entry.rawContent)
                    continue
                }

                guard let property = editableMap[entry.key], property.isReadOnly == false else {
                    chunks.append(entry.rawContent)
                    continue
                }

                chunks.append(render(key: entry.key, property: property))
                consumedKeys.insert(entry.key)
            }
        }

        if titleValue.isEmpty == false, consumedKeys.contains("title") == false {
            chunks.append(render(key: "title", property: EditableProperty(key: "title", kind: .text, value: .string(titleValue), isReadOnly: false, issue: nil)))
        }

        for property in properties where property.isReadOnly == false && consumedKeys.contains(property.key) == false {
            chunks.append(render(key: property.key, property: property))
            consumedKeys.insert(property.key)
        }

        guard chunks.isEmpty == false else { return nil }
        return "---\n" + chunks.joined(separator: "\n") + "\n---"
    }

    private func render(key: String, property: EditableProperty) -> String {
        let foundationValue: Any = switch property.value {
        case .string(let value):
            value
        case .bool(let value):
            value
        case .stringList(let values):
            values
        case .date(let value):
            value
        case .url(let value):
            value
        case .raw(let value):
            value
        }

        let object: [String: Any] = [key: foundationValue]
        return (try? Yams.dump(object: object).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "\(key): \(property.value.stringValue)"
    }
}
