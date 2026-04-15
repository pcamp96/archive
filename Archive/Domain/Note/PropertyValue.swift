import Foundation

enum PropertyKind: String, Codable, CaseIterable, Hashable, Sendable {
    case text
    case textarea
    case boolean
    case singleSelect
    case multiSelect
    case date
    case url
    case unsupported

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .textarea: return "Text Area"
        case .boolean: return "Boolean"
        case .singleSelect: return "Single Select"
        case .multiSelect: return "Tags"
        case .date: return "Date"
        case .url: return "URL"
        case .unsupported: return "Unsupported"
        }
    }

    static var creatableKinds: [PropertyKind] {
        [.text, .textarea, .boolean, .singleSelect, .multiSelect, .date, .url]
    }
}

enum PropertyValue: Hashable, Sendable {
    case string(String)
    case bool(Bool)
    case stringList([String])
    case date(String)
    case url(String)
    case raw(String)

    var stringValue: String {
        switch self {
        case .string(let value), .date(let value), .url(let value), .raw(let value):
            return value
        case .bool(let value):
            return value ? "true" : "false"
        case .stringList(let values):
            return values.joined(separator: ", ")
        }
    }
}

struct EditableProperty: Identifiable, Hashable, Sendable {
    let key: String
    var kind: PropertyKind
    var value: PropertyValue
    var isReadOnly: Bool
    var issue: String?

    var id: String { key }
}

struct PropertyDefinition: Codable, Hashable, Sendable {
    var key: String
    var kind: PropertyKind
    var options: [String]

    var isBoardEligible: Bool {
        kind == .text || kind == .singleSelect
    }
}

struct PropertyCreationState: Identifiable, Hashable, Sendable {
    let id: UUID
    var key: String
    var kind: PropertyKind
    var optionsText: String

    init(
        id: UUID = UUID(),
        key: String = "",
        kind: PropertyKind = .text,
        optionsText: String = ""
    ) {
        self.id = id
        self.key = key
        self.kind = kind
        self.optionsText = optionsText
    }

    var normalizedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var optionValues: [String] {
        optionsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    var definition: PropertyDefinition? {
        guard normalizedKey.isEmpty == false else { return nil }
        return PropertyDefinition(key: normalizedKey, kind: kind, options: optionValues)
    }

    var initialValue: PropertyValue {
        switch kind {
        case .text, .textarea:
            return .string("")
        case .boolean:
            return .bool(false)
        case .singleSelect:
            return .string(optionValues.first ?? "")
        case .multiSelect:
            return .stringList([])
        case .date:
            return .date("")
        case .url:
            return .url("")
        case .unsupported:
            return .raw("")
        }
    }
}

struct PropertyRegistry: Codable, Hashable, Sendable {
    var version = 1
    var definitions: [String: PropertyDefinition] = [:]

    init(version: Int = 1, definitions: [String: PropertyDefinition] = [:]) {
        self.version = version
        self.definitions = definitions
    }

    func definition(for key: String) -> PropertyDefinition? {
        definitions[key]
    }

    var orderedDefinitions: [PropertyDefinition] {
        definitions.values.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    var defaultBoardPropertyKey: String? {
        if let status = definitions["status"], status.isBoardEligible {
            return status.key
        }
        return orderedDefinitions.first(where: \.isBoardEligible)?.key
    }
}

enum PropertyInference {
    static func inferKind(for value: PropertyValue) -> PropertyKind {
        switch value {
        case .string(let string):
            return string.contains("\n") ? .textarea : .text
        case .bool:
            return .boolean
        case .stringList:
            return .multiSelect
        case .date:
            return .date
        case .url:
            return .url
        case .raw:
            return .unsupported
        }
    }
}
