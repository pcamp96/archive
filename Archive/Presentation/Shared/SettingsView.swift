import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Editor") {
                Picker("Markdown Display", selection: $settings.markdownDisplayMode) {
                    ForEach(MarkdownDisplayMode.allCases) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.title)
                            Text(mode.subtitle)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Archive always writes canonical markdown to disk. Display mode only changes presentation, not storage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
