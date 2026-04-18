import SwiftUI

struct PropertiesInspectorView: View {
    @Binding var properties: [EditableProperty]
    let registry: PropertyRegistry
    let onChange: () -> Void
    let onAddProperty: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Properties")
                    .font(.headline)
                Spacer()
                Button("+ Property", action: onAddProperty)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }

            ForEach(Array(properties.enumerated()), id: \.element.id) { index, _ in
                PropertyEditorRow(
                    property: binding(for: index),
                    definition: registry.definition(for: properties[index].key)
                )
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func binding(for index: Int) -> Binding<EditableProperty> {
        Binding(
            get: { properties[index] },
            set: {
                properties[index] = $0
                onChange()
            }
        )
    }
}

struct PropertyCreationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var state = PropertyCreationState()
    let save: (PropertyCreationState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Property")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                TextField("Property name", text: $state.key)
                    .textFieldStyle(.roundedBorder)

                Picker("Type", selection: $state.kind) {
                    ForEach(PropertyKind.creatableKinds, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                if state.kind == .singleSelect || state.kind == .multiSelect {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Options")
                            .font(.subheadline.weight(.medium))
                        TextField("Comma-separated values", text: $state.optionsText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add") {
                    save(state)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.definition == nil)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct PropertyEditorRow: View {
    @Binding var property: EditableProperty
    let definition: PropertyDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(property.key)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(property.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
        .padding(.vertical, 2)
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
                .frame(minHeight: 76)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .boolean:
            Toggle(isOn: boolBinding) {
                Text("Enabled")
            }
            .toggleStyle(.switch)
        case .singleSelect:
            Picker(property.key, selection: stringBinding) {
                ForEach(PropertyEditorOptions.singleSelectOptions(for: property, definition: definition), id: \.self) { option in
                    Text(option).tag(option)
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

    private var stringBinding: Binding<String> {
        Binding(
            get: { property.value.stringValue },
            set: { property.value = .string($0) }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: {
                if case .bool(let value) = property.value {
                    return value
                }
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
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum PropertyEditorOptions {
    static func singleSelectOptions(for property: EditableProperty, definition: PropertyDefinition?) -> [String] {
        var options = definition?.options ?? []

        if case .string(let currentValue) = property.value,
           currentValue.isEmpty == false,
           options.contains(currentValue) == false {
            options.append(currentValue)
        }

        return options
    }
}
