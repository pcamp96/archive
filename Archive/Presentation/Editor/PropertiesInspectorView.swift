import SwiftUI

struct PropertiesInspectorView: View {
    @Binding var properties: [EditableProperty]
    let registry: PropertyRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Properties")
                .font(.headline)

            if properties.isEmpty {
                Text("No editable properties in this note yet.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(Array(properties.enumerated()), id: \.element.id) { index, property in
                    PropertyEditorRow(
                        property: binding(for: index),
                        definition: registry.definition(for: property.key)
                    )
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private func binding(for index: Int) -> Binding<EditableProperty> {
        Binding(
            get: { properties[index] },
            set: { properties[index] = $0 }
        )
    }
}

private struct PropertyEditorRow: View {
    @Binding var property: EditableProperty
    let definition: PropertyDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(property.key)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(property.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if property.isReadOnly {
                Text(property.value.stringValue)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                editor
            }

            if let issue = property.issue {
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var editor: some View {
        switch property.kind {
        case .text:
            TextField(property.key, text: stringBinding)
                .textFieldStyle(.roundedBorder)
        case .textarea:
            TextEditor(text: stringBinding)
                .font(.body)
                .frame(minHeight: 72)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        case .boolean:
            Toggle(isOn: boolBinding) {
                Text("Enabled")
            }
            .toggleStyle(.switch)
        case .singleSelect:
            Picker(property.key, selection: stringBinding) {
                ForEach(definition?.options ?? [], id: \.self) { option in
                    Text(option).tag(option)
                }
                if let currentValue = currentStringValue, (definition?.options.contains(currentValue) == false) {
                    Text(currentValue).tag(currentValue)
                }
            }
            .pickerStyle(.menu)
        case .multiSelect:
            TextField("Comma-separated values", text: tagsBinding)
                .textFieldStyle(.roundedBorder)
        case .date:
            DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                .datePickerStyle(.field)
        case .url:
            TextField("URL", text: urlBinding)
                .textFieldStyle(.roundedBorder)
        case .unsupported:
            Text(property.value.stringValue)
                .foregroundStyle(.secondary)
        }
    }

    private var currentStringValue: String? {
        if case .string(let value) = property.value {
            return value
        }
        return nil
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { property.value.stringValue },
            set: { property.value = .string($0) }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: {
                if case .bool(let value) = property.value { return value }
                return false
            },
            set: { property.value = .bool($0) }
        )
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: {
                if case .stringList(let values) = property.value {
                    return values.joined(separator: ", ")
                }
                return property.value.stringValue
            },
            set: { newValue in
                let values = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                property.value = .stringList(values)
            }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                if case .date(let value) = property.value,
                   let date = Self.dateFormatter.date(from: value) {
                    return date
                }
                return Date()
            },
            set: { property.value = .date(Self.dateFormatter.string(from: $0)) }
        )
    }

    private var urlBinding: Binding<String> {
        Binding(
            get: {
                if case .url(let value) = property.value {
                    return value
                }
                return property.value.stringValue
            },
            set: { property.value = .url($0) }
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

